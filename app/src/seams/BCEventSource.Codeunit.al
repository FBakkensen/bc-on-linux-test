codeunit 50001 "BC Event Source" implements "IEventSource"
{
    Access = Public;

    procedure CollectEvents(var Item: Record Item; var ExcludingSalesLine: Record "Sales Line"; var EventBuf: Record "Max Sellable Event Buf" temporary)
    begin
        CollectSalesLineEvents(Item, ExcludingSalesLine, EventBuf);
        CollectPurchaseLineEvents(Item, EventBuf);
        CollectTransferLineEvents(Item, EventBuf);
        CollectServiceLineEvents(Item, EventBuf);
        CollectProdOrderEvents(Item, EventBuf);
        CollectAssemblyEvents(Item, EventBuf);
        CollectJobPlanningEvents(Item, EventBuf);
    end;

    local procedure CollectJobPlanningEvents(var Item: Record Item; var EventBuf: Record "Max Sellable Event Buf" temporary)
    var
        JPL: Record "Job Planning Line";
    begin
        // ADR 0001 deviation #3: replicate BC's "no Line Type filter" behaviour. A line
        // tagged Both Budget and Billable contributes once as the Budget leg and once
        // as the Billable leg — counted twice on purpose so Max Sellable stays in lock
        // step with BC's own Job availability views rather than de-duping in our code.
        JPL.FilterLinesWithItemToPlan(Item);
        if JPL.FindSet() then
            repeat
                AppendEvent(EventBuf, JPL."Planning Date", -JPL."Remaining Qty. (Base)");
                if JPL."Line Type" = JPL."Line Type"::"Both Budget and Billable" then
                    AppendEvent(EventBuf, JPL."Planning Date", -JPL."Remaining Qty. (Base)");
            until JPL.Next() = 0;
    end;

    local procedure CollectAssemblyEvents(var Item: Record Item; var EventBuf: Record "Max Sellable Event Buf" temporary)
    var
        AsmHeader: Record "Assembly Header";
        AsmLine: Record "Assembly Line";
    begin
        // ADR 0001 deviation #2: Document Type = Order only. Blanket Assembly headers
        // and lines are excluded — Max Sellable follows the Qty. on Asm. Component
        // FlowField, not CU 99000854's special-case for blanket components.
        AsmHeader.SetItemToPlanFilters(Item, AsmHeader."Document Type"::Order);
        if AsmHeader.FindSet() then
            repeat
                AppendEvent(EventBuf, AsmHeader."Due Date", AsmHeader."Remaining Quantity (Base)");
            until AsmHeader.Next() = 0;

        AsmLine.SetItemToPlanFilters(Item, AsmLine."Document Type"::Order);
        if AsmLine.FindSet() then
            repeat
                AppendEvent(EventBuf, AsmLine."Due Date", -AsmLine."Remaining Quantity (Base)");
            until AsmLine.Next() = 0;
    end;

    local procedure CollectProdOrderEvents(var Item: Record Item; var EventBuf: Record "Max Sellable Event Buf" temporary)
    var
        ProdOrderLine: Record "Prod. Order Line";
        ProdOrderComp: Record "Prod. Order Component";
    begin
        // ADR 0001 deviation #1: IncludeFirmPlanned=true → Planned + Firm Planned + Released.
        ProdOrderLine.FilterLinesWithItemToPlan(Item, true);
        if ProdOrderLine.FindSet() then
            repeat
                AppendEvent(EventBuf, ProdOrderLine."Due Date", ProdOrderLine."Remaining Qty. (Base)");
            until ProdOrderLine.Next() = 0;

        ProdOrderComp.FilterLinesWithItemToPlan(Item, true);
        if ProdOrderComp.FindSet() then
            repeat
                AppendEvent(EventBuf, ProdOrderComp."Due Date", -ProdOrderComp."Remaining Qty. (Base)");
            until ProdOrderComp.Next() = 0;
    end;

    local procedure CollectServiceLineEvents(var Item: Record Item; var EventBuf: Record "Max Sellable Event Buf" temporary)
    var
        ServiceLine: Record "Service Line";
    begin
        ServiceLine.FilterLinesWithItemToPlan(Item);
        if ServiceLine.FindSet() then
            repeat
                AppendEvent(EventBuf, ServiceLine."Needed by Date", -ServiceLine."Outstanding Qty. (Base)");
            until ServiceLine.Next() = 0;
    end;

    local procedure CollectTransferLineEvents(var Item: Record Item; var EventBuf: Record "Max Sellable Event Buf" temporary)
    var
        TransferLine: Record "Transfer Line";
    begin
        TransferLine.FilterLinesWithItemToPlan(Item, true, false);
        if TransferLine.FindSet() then
            repeat
                AppendEvent(EventBuf, TransferLine."Receipt Date", TransferLine."Outstanding Qty. (Base)");
            until TransferLine.Next() = 0;

        TransferLine.FilterLinesWithItemToPlan(Item, false, false);
        if TransferLine.FindSet() then
            repeat
                AppendEvent(EventBuf, TransferLine."Shipment Date", -TransferLine."Outstanding Qty. (Base)");
            until TransferLine.Next() = 0;
    end;

    local procedure CollectPurchaseLineEvents(var Item: Record Item; var EventBuf: Record "Max Sellable Event Buf" temporary)
    var
        PurchLine: Record "Purchase Line";
    begin
        PurchLine.FilterLinesWithItemToPlan(Item, PurchLine."Document Type"::Order);
        if PurchLine.FindSet() then
            repeat
                AppendEvent(EventBuf, PurchLine."Expected Receipt Date", PurchLine."Outstanding Qty. (Base)");
            until PurchLine.Next() = 0;

        PurchLine.FilterLinesWithItemToPlan(Item, PurchLine."Document Type"::"Return Order");
        if PurchLine.FindSet() then
            repeat
                AppendEvent(EventBuf, PurchLine."Expected Receipt Date", -PurchLine."Outstanding Qty. (Base)");
            until PurchLine.Next() = 0;
    end;

    local procedure CollectSalesLineEvents(var Item: Record Item; var ExcludingSalesLine: Record "Sales Line"; var EventBuf: Record "Max Sellable Event Buf" temporary)
    var
        SalesLine: Record "Sales Line";
    begin
        SalesLine.FilterLinesWithItemToPlan(Item, SalesLine."Document Type"::Order);
        if SalesLine.FindSet() then
            repeat
                if not IsSameLine(SalesLine, ExcludingSalesLine) then
                    AppendEvent(EventBuf, SalesLine."Shipment Date", -SalesLine."Outstanding Qty. (Base)");
            until SalesLine.Next() = 0;

        SalesLine.FilterLinesWithItemToPlan(Item, SalesLine."Document Type"::"Return Order");
        if SalesLine.FindSet() then
            repeat
                if not IsSameLine(SalesLine, ExcludingSalesLine) then
                    AppendEvent(EventBuf, SalesLine."Shipment Date", SalesLine."Outstanding Qty. (Base)");
            until SalesLine.Next() = 0;
    end;

    local procedure IsSameLine(var Candidate: Record "Sales Line"; var Excluded: Record "Sales Line"): Boolean
    begin
        exit(
            (Candidate."Document Type" = Excluded."Document Type") and
            (Candidate."Document No." = Excluded."Document No.") and
            (Candidate."Line No." = Excluded."Line No.") and
            (Excluded."Document No." <> ''));
    end;

    local procedure AppendEvent(var EventBuf: Record "Max Sellable Event Buf" temporary; EventDate: Date; SignedQtyBase: Decimal)
    begin
        if SignedQtyBase = 0 then
            exit;
        EventBuf.Init();
        EventBuf."Entry No." := EventBuf.Count() + 1;
        EventBuf."Event Date" := EventDate;
        EventBuf."Signed Quantity (Base)" := SignedQtyBase;
        EventBuf.Insert();
    end;
}
