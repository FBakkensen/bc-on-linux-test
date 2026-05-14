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
    begin
        exit(0);
    end;
}
