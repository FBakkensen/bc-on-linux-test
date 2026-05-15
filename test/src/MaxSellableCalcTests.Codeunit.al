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
        Initialize();

        // GIVEN three trivial stub implementations of the BC seam interfaces
        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        // WHEN Calculate runs with an empty SKU at WorkDate
        Result := MaxSellableCalc.Calculate(
            '', '', '', WorkDate(), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        // THEN no item, no events → 0
        Assert.AreEqual(0, Result, 'Calculate must return 0 with empty stubs.');
    end;

    [Test]
    procedure CalculateReturnsStartingInventoryWhenNoEvents()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
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
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        // GIVEN an item with 100 base-UoM on-hand from a past ILE
        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert();

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert();

        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        // WHEN Calculate runs with no future events
        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        // THEN starting inventory is the answer
        Assert.AreEqual(100, Result, 'Calculate must return starting inventory when no events.');
    end;

    [Test]
    procedure CalculateAddsFutureSupplyEvent()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
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
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert();

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert();

        // GIVEN a +50 supply event dated after ShipmentDate
        EventSourceStub.AddEvent(WorkDate() + 3, 50);

        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        // WHEN Calculate runs at WorkDate
        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        // THEN starting 100 + supply 50 = 150
        Assert.AreEqual(150, Result, 'Calculate must include future supply events in the projection.');
    end;

    [Test]
    procedure CalculateSubtractsFutureDemandEvent()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
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
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert();

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert();

        // GIVEN a -30 demand event dated after ShipmentDate
        EventSourceStub.AddEvent(WorkDate() + 3, -30);

        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        // THEN starting 100 - demand 30 = 70
        Assert.AreEqual(70, Result, 'Calculate must subtract future demand events from the projection.');
    end;

    [Test]
    procedure CalculateMinWalkPicksMiddleDateDip()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
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
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert();

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert();

        // GIVEN three events: +20 on D1, -50 on D2, +10 on D3 — balance dips at D2
        // Balance trace: 100 -> 120 -> 70 -> 80; min is 70 mid-stream.
        EventSourceStub.AddEvent(WorkDate() + 1, 20);
        EventSourceStub.AddEvent(WorkDate() + 2, -50);
        EventSourceStub.AddEvent(WorkDate() + 3, 10);

        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        // THEN the min-walk returns the mid-stream limiting balance (70), not the final balance (80)
        Assert.AreEqual(70, Result, 'Min-walk must return the mid-stream limiting balance, not the final.');
    end;

    [Test]
    procedure CalculatePastShipmentDateClampsFloor()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
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
        Initialize();
        WorkDate(DMY2Date(20, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert();

        // GIVEN one ILE on or before the past ShipmentDate, and a later ILE
        //       that should NOT count because FloorDate clamps to the past date.
        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := DMY2Date(5, 1, 2026);
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert();

        ILE.Init();
        ILE."Entry No." := 2;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := DMY2Date(15, 1, 2026);
        ILE.Quantity := 999;
        ILE."Remaining Quantity" := 999;
        ILE.Insert();

        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        // WHEN ShipmentDate is in the past relative to WorkDate
        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', DMY2Date(10, 1, 2026), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        // THEN the floor is the past ShipmentDate — only the ILE on/before that date counts
        Assert.AreEqual(100, Result, 'Past ShipmentDate must clamp the floor; later ILE must not count.');
    end;

    [Test]
    procedure CalculateAlreadyNegativeProjectionReturnsZero()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
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
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert();

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 50;
        ILE."Remaining Quantity" := 50;
        ILE.Insert();

        // GIVEN demand that drags the projection negative
        EventSourceStub.AddEvent(WorkDate() + 2, -100);

        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        // THEN the result clamps to 0
        Assert.AreEqual(0, Result, 'A negative projected balance must clamp to 0.');
    end;

    [Test]
    procedure CalculateExcludesEditingSalesLine()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
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
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert();

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert();

        // GIVEN two demand events, each tagged with the originating Sales Line "Line No."
        EventSourceStub.AddEventFromLine(WorkDate() + 1, -50, 10000);
        EventSourceStub.AddEventFromLine(WorkDate() + 1, -20, 20000);

        // AND the line currently being edited is the 10000-line
        ExcludingSalesLine."Line No." := 10000;

        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        // THEN only the other line's -20 demand is subtracted: 100 - 20 = 80
        Assert.AreEqual(80, Result, 'Calculate must exclude the editing Sales Line from the demand aggregate.');
    end;

    [Test]
    procedure CalculateConvertsBaseUoMToLineUoM()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
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
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert();

        // GIVEN 60 base units on hand
        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 60;
        ILE."Remaining Quantity" := 60;
        ILE.Insert();

        // AND the editing Sales Line uses a 6-pack UoM (Qty. per Unit of Measure = 6)
        ExcludingSalesLine."Qty. per Unit of Measure" := 6;

        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        // THEN 60 base / 6 per-pack = 10 packs in the line's UoM
        Assert.AreEqual(10, Result, 'Calculate must convert base UoM back to the line UoM.');
    end;

    [Test]
    procedure CalculateIsSideEffectFreeForPBT()
    var
        Item: Record Item;
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        StockoutCheckerStub: Codeunit "Stockout Checker Stub";
        NotificationDispatcherStub: Codeunit "Notification Dispatcher Stub";
        EventSource: Interface "IEventSource";
        StockoutChecker: Interface "IStockoutChecker";
        NotificationDispatcher: Interface "INotificationDispatcher";
    begin
        Initialize();
        // Calculate must not raise notifications, write data, or otherwise leak side
        // effects — PBT runs it in a UI-restricted session where any of those would
        // crash the background task. Pinning that invariant here so it can't regress.
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert();

        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotificationDispatcherStub;

        MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher);

        Assert.AreEqual(0, NotificationDispatcherStub.GetDispatchCount(), 'Calculate must not dispatch notifications — PBT-safe.');
    end;

    local procedure Initialize()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
    begin
        Item.DeleteAll();
        ILE.DeleteAll();
    end;
}
