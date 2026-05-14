codeunit 50000 "Max Sellable Calc"
{
    Access = Public;

    procedure Calculate(
        ItemNo: Code[20];
        VariantCode: Code[10];
        LocationCode: Code[10];
        ShipmentDate: Date;
        var ExcludingSalesLine: Record "Sales Line";
        EventSource: Interface "IEventSource";
        StockoutChecker: Interface "IStockoutChecker";
        NotificationDispatcher: Interface "INotificationDispatcher"): Decimal
    var
        Item: Record Item;
        EventBuf: Record "Max Sellable Event Buf" temporary;
        FloorDate: Date;
        Balance: Decimal;
        Projected: Decimal;
    begin
        if ItemNo = '' then
            exit(0);
        FloorDate := FloorOf(ShipmentDate);
        Balance := StartingOnHandAt(ItemNo, VariantCode, LocationCode, FloorDate);

        if Item.Get(ItemNo) then;
        EventSource.CollectEvents(Item, ExcludingSalesLine, EventBuf);
        Projected := MinWalk(EventBuf, Balance);
        if Projected < 0 then
            exit(0);
        exit(ToLineUoM(Projected, ExcludingSalesLine));
    end;

    local procedure ToLineUoM(BaseQty: Decimal; var ExcludingSalesLine: Record "Sales Line"): Decimal
    var
        QtyPerBase: Decimal;
    begin
        QtyPerBase := ExcludingSalesLine."Qty. per Unit of Measure";
        if QtyPerBase = 0 then
            QtyPerBase := 1;
        exit(BaseQty / QtyPerBase);
    end;

    local procedure MinWalk(var EventBuf: Record "Max Sellable Event Buf" temporary; StartingBalance: Decimal): Decimal
    var
        Balance: Decimal;
        MinBalance: Decimal;
    begin
        // Min over the post-event running balances. If no events fire, the
        // projection never moves off StartingBalance, so return that.
        EventBuf.SetCurrentKey("Event Date");
        if not EventBuf.FindSet() then
            exit(StartingBalance);
        Balance := StartingBalance + EventBuf."Signed Quantity (Base)";
        MinBalance := Balance;
        while EventBuf.Next() <> 0 do begin
            Balance += EventBuf."Signed Quantity (Base)";
            if Balance < MinBalance then
                MinBalance := Balance;
        end;
        exit(MinBalance);
    end;

    local procedure StartingOnHandAt(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; FloorDate: Date): Decimal
    var
        ILE: Record "Item Ledger Entry";
    begin
        ILE.SetRange("Item No.", ItemNo);
        ILE.SetRange("Variant Code", VariantCode);
        ILE.SetRange("Location Code", LocationCode);
        ILE.SetRange("Posting Date", 0D, FloorDate);
        ILE.CalcSums(Quantity);
        exit(ILE.Quantity);
    end;

    local procedure FloorOf(ShipmentDate: Date): Date
    begin
        if (ShipmentDate <> 0D) and (ShipmentDate < WorkDate()) then
            exit(ShipmentDate);
        exit(WorkDate());
    end;
}
