namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Sales.Document;

codeunit 50005 "Max Sellable PBT"
{
    Access = Public;
    TableNo = "Sales Line";

    trigger OnRun()
    var
        Params: Dictionary of [Text, Text];
        Results: Dictionary of [Text, Text];
    begin
        Params := Page.GetBackgroundParameters();
        Results := ComputeFromParameters(Params);
        Page.SetBackgroundTaskResult(Results);
    end;

    procedure ComputeFromParameters(Params: Dictionary of [Text, Text]) Results: Dictionary of [Text, Text]
    var
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        BCEventSource: Codeunit "BC Event Source";
        EventSource: Interface "IEventSource";
        ItemNo: Code[20];
        VariantCode: Code[10];
        LocationCode: Code[10];
        ShipmentDate: Date;
        Qty: Decimal;
    begin
        ItemNo := CopyStr(GetText(Params, 'ItemNo'), 1, MaxStrLen(ItemNo));
        VariantCode := CopyStr(GetText(Params, 'VariantCode'), 1, MaxStrLen(VariantCode));
        LocationCode := CopyStr(GetText(Params, 'LocationCode'), 1, MaxStrLen(LocationCode));
        Evaluate(ShipmentDate, GetText(Params, 'ShipmentDate'));
        SetExcludingSalesLine(ExcludingSalesLine, Params);

        EventSource := BCEventSource;

        Qty := MaxSellableCalc.Calculate(
            ItemNo, VariantCode, LocationCode, ShipmentDate, ExcludingSalesLine,
            EventSource);

        Results.Add('Qty', Format(Qty, 0, 9));
    end;

    procedure BuildParameters(var SalesLine: Record "Sales Line") Params: Dictionary of [Text, Text]
    begin
        Params.Add('ItemNo', SalesLine."No.");
        Params.Add('VariantCode', SalesLine."Variant Code");
        Params.Add('LocationCode', SalesLine."Location Code");
        Params.Add('ShipmentDate', Format(SalesLine."Shipment Date", 0, 9));
        Params.Add('DocType', Format(SalesLine."Document Type".AsInteger()));
        Params.Add('DocNo', SalesLine."Document No.");
        Params.Add('LineNo', Format(SalesLine."Line No."));
    end;

    local procedure SetExcludingSalesLine(var SalesLine: Record "Sales Line"; Params: Dictionary of [Text, Text])
    var
        DocTypeInt: Integer;
        LineNo: Integer;
    begin
        Evaluate(DocTypeInt, GetText(Params, 'DocType'));
        Evaluate(LineNo, GetText(Params, 'LineNo'));
        SalesLine."Document Type" := Enum::"Sales Document Type".FromInteger(DocTypeInt);
        SalesLine."Document No." := CopyStr(GetText(Params, 'DocNo'), 1, MaxStrLen(SalesLine."Document No."));
        SalesLine."Line No." := LineNo;
    end;

    local procedure GetText(Params: Dictionary of [Text, Text]; KeyName: Text): Text
    var
        Value: Text;
    begin
        if Params.Get(KeyName, Value) then
            exit(Value);
        exit('');
    end;
}
