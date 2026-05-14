codeunit 50002 "Max Sellable Validate Handler"
{
    procedure RunGatedFlow(
        var SalesLine: Record "Sales Line";
        EventSource: Interface "IEventSource";
        StockoutChecker: Interface "IStockoutChecker";
        NotificationDispatcher: Interface "INotificationDispatcher"): Boolean
    var
        SalesSetup: Record "Sales & Receivables Setup";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        Notif: Notification;
        MaxSellable: Decimal;
        MaxSellableMsg: Label 'Max Sellable Quantity for %1 on %2 is %3, but %4 was entered.', Comment = '%1=Item No., %2=Shipment Date, %3=Max Sellable Qty, %4=Entered Qty';
    begin
        if SalesLine.Type <> SalesLine.Type::Item then
            exit(false);
        if SalesLine."No." = '' then
            exit(false);
        if SalesLine.Quantity <= 0 then
            exit(false);

        if not SalesSetup.Get() then
            exit(false);
        if not SalesSetup."Max Sellable Warning" then
            exit(false);
        if SalesSetup."Stockout Warning" and StockoutChecker.SalesLineWouldStockOut(SalesLine) then
            exit(false);

        MaxSellable := MaxSellableCalc.Calculate(
            SalesLine."No.", SalesLine."Variant Code", SalesLine."Location Code",
            SalesLine."Shipment Date", SalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        if MaxSellable >= SalesLine.Quantity then
            exit(false);

        Notif.Id := '8a0c2f4b-3d36-4d44-9b08-1d7e9b5a4c11';
        Notif.Message := StrSubstNo(MaxSellableMsg, SalesLine."No.", SalesLine."Shipment Date", MaxSellable, SalesLine.Quantity);
        NotificationDispatcher.Dispatch(Notif, SalesLine.RecordId);
        exit(true);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales & Receivables Setup", 'OnAfterValidateEvent', 'Stockout Warning', false, false)]
    local procedure ClearMaxSellableOnStockoutOff(var Rec: Record "Sales & Receivables Setup"; var xRec: Record "Sales & Receivables Setup"; CurrFieldNo: Integer)
    begin
        if not Rec."Stockout Warning" then
            Rec."Max Sellable Warning" := false;
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnAfterValidateEvent', 'Quantity', false, false)]
    local procedure OnAfterValidateQuantity(var Rec: Record "Sales Line"; var xRec: Record "Sales Line"; CurrFieldNo: Integer)
    begin
        RunWithProdInterfaces(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnAfterValidateEvent', 'Shipment Date', false, false)]
    local procedure OnAfterValidateShipmentDate(var Rec: Record "Sales Line"; var xRec: Record "Sales Line"; CurrFieldNo: Integer)
    begin
        RunWithProdInterfaces(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnAfterValidateEvent', 'No.', false, false)]
    local procedure OnAfterValidateNo(var Rec: Record "Sales Line"; var xRec: Record "Sales Line"; CurrFieldNo: Integer)
    begin
        RunWithProdInterfaces(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnAfterValidateEvent', 'Variant Code', false, false)]
    local procedure OnAfterValidateVariantCode(var Rec: Record "Sales Line"; var xRec: Record "Sales Line"; CurrFieldNo: Integer)
    begin
        RunWithProdInterfaces(Rec);
    end;

    [EventSubscriber(ObjectType::Table, Database::"Sales Line", 'OnAfterValidateEvent', 'Location Code', false, false)]
    local procedure OnAfterValidateLocationCode(var Rec: Record "Sales Line"; var xRec: Record "Sales Line"; CurrFieldNo: Integer)
    begin
        RunWithProdInterfaces(Rec);
    end;

    local procedure RunWithProdInterfaces(var SalesLine: Record "Sales Line")
    var
        BCEventSource: Codeunit "BC Event Source";
        BCStockoutChecker: Codeunit "BC Stockout Checker";
        BCNotificationDispatcher: Codeunit "BC Notification Dispatcher";
        EventSource: Interface "IEventSource";
        StockoutChecker: Interface "IStockoutChecker";
        NotificationDispatcher: Interface "INotificationDispatcher";
    begin
        EventSource := BCEventSource;
        StockoutChecker := BCStockoutChecker;
        NotificationDispatcher := BCNotificationDispatcher;
        RunGatedFlow(SalesLine, EventSource, StockoutChecker, NotificationDispatcher);
    end;
}
