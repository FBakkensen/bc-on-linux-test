namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Sales.Document;

codeunit 50000 "Max Sellable Calc"
{
    Access = Public;
    Permissions = tabledata Item = R;

    procedure Calculate(
        ItemNo: Code[20];
        VariantCode: Code[10];
        LocationCode: Code[10];
        ShipmentDate: Date;
        var ExcludingSalesLine: Record "Sales Line";
        EventSource: Interface "IEventSource"): Decimal
    var
        Item: Record Item;
        TempEventBuf: Record "Max Sellable Event Buf" temporary;
        FloorDate: Date;
        Balance: Decimal;
        Projected: Decimal;
    begin
        if ItemNo = '' then
            exit(0);
        FloorDate := FloorOf(ShipmentDate);
        Balance := StartingOnHandAt(ItemNo, VariantCode, LocationCode, FloorDate);

        if Item.Get(ItemNo) then begin
            Item.SetRange("Variant Filter", VariantCode);
            Item.SetRange("Location Filter", LocationCode);
        end;
        EventSource.CollectEvents(Item, ExcludingSalesLine, TempEventBuf);
        Projected := MinWalk(TempEventBuf, Balance);
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

    local procedure MinWalk(var TempEventBuf: Record "Max Sellable Event Buf" temporary; StartingBalance: Decimal): Decimal
    var
        Balance: Decimal;
        MinBalance: Decimal;
    begin
        TempEventBuf.SetCurrentKey("Event Date");
        if not TempEventBuf.FindSet() then
            exit(StartingBalance);
        Balance := StartingBalance + TempEventBuf."Signed Quantity (Base)";
        MinBalance := Balance;
        while TempEventBuf.Next() <> 0 do begin
            Balance += TempEventBuf."Signed Quantity (Base)";
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
