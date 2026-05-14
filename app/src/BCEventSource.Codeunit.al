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
