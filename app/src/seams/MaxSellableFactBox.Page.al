namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Sales.Document;

page 50000 "Max Sellable FactBox"
{
    PageType = CardPart;
    SourceTable = "Sales Line";
    Caption = 'Max Sellable Qty';
    ApplicationArea = Basic, Suite;
    Extensible = false;

    layout
    {
        area(Content)
        {
            field(MaxSellableQty; MaxSellableQty)
            {
                Caption = 'Max Sellable Qty';
                Editable = false;
                DecimalPlaces = 0 : 5;
                AutoFormatType = 0;
                ToolTip = 'Specifies how many of the line''s unit of measure can still be promised on the Shipment Date, computed asynchronously via Page Background Task.';
            }
        }
    }

    var
        MaxSellableQty: Decimal;

    trigger OnAfterGetCurrRecord()
    begin
        EnqueuePBT();
    end;

    trigger OnPageBackgroundTaskCompleted(TaskId: Integer; Results: Dictionary of [Text, Text])
    var
        QtyText: Text;
        Qty: Decimal;
    begin
        if Results.Get('Qty', QtyText) then
            if Evaluate(Qty, QtyText, 9) then
                MaxSellableQty := Qty;
    end;

    local procedure EnqueuePBT()
    var
        PBT: Codeunit "Max Sellable PBT";
        Params: Dictionary of [Text, Text];
        TaskId: Integer;
    begin
        if Rec.Type <> Rec.Type::Item then
            exit;
        if Rec."No." = '' then
            exit;
        Params := PBT.BuildParameters(Rec);
        CurrPage.EnqueueBackgroundTask(TaskId, Codeunit::"Max Sellable PBT", Params);
    end;
}
