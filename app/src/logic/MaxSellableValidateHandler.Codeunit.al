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
}
