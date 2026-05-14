codeunit 50100 "Max Sellable Calc Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure CalculateWithEmptyStubsReturnsZero()
    var
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        ExcludingSalesLine: Record "Sales Line";
        EventSourceStub: Codeunit "Event Source Stub";
        StockoutCheckerStub: Codeunit "Stockout Checker Stub";
        NotificationDispatcherStub: Codeunit "Notification Dispatcher Stub";
        EventSource: Interface "IEventSource";
        StockoutChecker: Interface "IStockoutChecker";
        NotificationDispatcher: Interface "INotificationDispatcher";
        Result: Decimal;
    begin
        // GIVEN three trivial stub implementations of the BC seam interfaces
        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        // WHEN Calculate runs with an empty SKU at WorkDate
        Result := MaxSellableCalc.Calculate(
            '', '', '', WorkDate(), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        // THEN the placeholder returns 0 (min-walk algorithm lands in the next slice)
        Assert.AreEqual(0, Result, 'Calculate must return 0 with empty stubs.');
    end;
}
