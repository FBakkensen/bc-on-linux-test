codeunit 50001 "BC Event Source" implements "IEventSource"
{
    Access = Public;

    procedure CollectEvents(var Item: Record Item; var ExcludingSalesLine: Record "Sales Line"; var EventBuf: Record "Max Sellable Event Buf" temporary)
    begin
        CollectSalesLineEvents(Item, ExcludingSalesLine, EventBuf);
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
