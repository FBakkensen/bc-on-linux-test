codeunit 50006 "Max Sellable Subscribers"
{
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
        MaxSellableValidateHandler: Codeunit "Max Sellable Validate Handler";
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
        MaxSellableValidateHandler.RunGatedFlow(SalesLine, EventSource, StockoutChecker, NotificationDispatcher);
    end;
}
