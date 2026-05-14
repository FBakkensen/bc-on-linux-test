codeunit 50104 "Max Sellable Handler Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure StockoutWarningOffClearsMaxSellableWarning()
    var
        SalesSetup: Record "Sales & Receivables Setup";
    begin
        // GIVEN setup with both flags on
        SalesSetup.Init();
        SalesSetup."Stockout Warning" := true;
        SalesSetup."Max Sellable Warning" := true;
        SalesSetup.Insert();

        // WHEN Stockout Warning is validated to false
        SalesSetup.Validate("Stockout Warning", false);

        // THEN Max Sellable Warning is silently cleared
        Assert.IsFalse(SalesSetup."Max Sellable Warning", 'Turning Stockout Warning off must clear Max Sellable Warning.');
    end;

    [Test]
    procedure GateStockoutOffMaxSellableOffYieldsNoDispatch()
    begin
        // (Stockout off, Max Sellable off) → silent
        WriteSetup(false, false);
        Assert.AreEqual(0, RunGateWithTinyInventoryAndBigQty(100, 50, false), 'No dispatch when Max Sellable Warning is off (and Stockout off).');
    end;

    [Test]
    procedure GateStockoutOnMaxSellableOffYieldsNoDispatch()
    begin
        // (Stockout on, Max Sellable off) → silent (Max Sellable disabled)
        WriteSetup(true, false);
        Assert.AreEqual(0, RunGateWithTinyInventoryAndBigQty(100, 50, false), 'No dispatch when Max Sellable Warning is off (regardless of Stockout).');
    end;

    [Test]
    procedure GateStockoutHitSuppressesMaxSellableNotification()
    begin
        // (Stockout on, Max Sellable on, stockout hits) → standard wins, no Max Sellable dispatch
        WriteSetup(true, true);
        Assert.AreEqual(0, RunGateWithTinyInventoryAndBigQty(100, 50, true), 'Stockout hit must suppress the Max Sellable notification (standard CU 311 wins).');
    end;

    [Test]
    procedure GateStockoutMissAndMaxSellableExceededDispatches()
    begin
        // (Stockout on, Max Sellable on, stockout miss, max sellable < qty) → dispatch
        WriteSetup(true, true);
        Assert.AreEqual(1, RunGateWithTinyInventoryAndBigQty(100, 50, false), 'Stockout miss + Max Sellable exceeded must dispatch a notification.');
    end;

    [Test]
    procedure GateMaxSellableNotExceededYieldsNoDispatch()
    begin
        // (Stockout on, Max Sellable on, stockout miss, max sellable >= qty) → silent
        WriteSetup(true, true);
        Assert.AreEqual(0, RunGateWithBigInventoryAndSmallQty(50, 100, false), 'Quantity within Max Sellable must not dispatch.');
    end;

    [Test]
    procedure GateStockoutOffMaxSellableOnDispatchesIfReached()
    begin
        // (Stockout off, Max Sellable on) — unreachable by UI, but if forced via direct
        // Insert/Modify the gate still runs Calculate (stockout step is skipped).
        WriteSetup(false, true);
        Assert.AreEqual(1, RunGateWithTinyInventoryAndBigQty(100, 50, false), 'With Stockout off and Max Sellable on, the gate proceeds straight to Calculate and dispatches.');
    end;

    local procedure WriteSetup(StockoutWarning: Boolean; MaxSellableWarning: Boolean)
    var
        SalesSetup: Record "Sales & Receivables Setup";
    begin
        if not SalesSetup.Get() then begin
            SalesSetup.Init();
            SalesSetup.Insert();
        end;
        SalesSetup."Stockout Warning" := StockoutWarning;
        SalesSetup."Max Sellable Warning" := MaxSellableWarning;
        SalesSetup.Modify();
    end;

    local procedure RunGateWithTinyInventoryAndBigQty(EnteredQty: Decimal; OnHand: Decimal; StockoutHits: Boolean): Integer
    begin
        exit(RunGate(EnteredQty, OnHand, StockoutHits));
    end;

    local procedure RunGateWithBigInventoryAndSmallQty(EnteredQty: Decimal; OnHand: Decimal; StockoutHits: Boolean): Integer
    begin
        exit(RunGate(EnteredQty, OnHand, StockoutHits));
    end;

    local procedure RunGate(EnteredQty: Decimal; OnHand: Decimal; StockoutHits: Boolean): Integer
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
        SalesLine: Record "Sales Line";
        Handler: Codeunit "Max Sellable Validate Handler";
        EventSourceStub: Codeunit "Event Source Stub";
        StockoutCheckerStub: Codeunit "Stockout Checker Stub";
        NotifDispatcherStub: Codeunit "Notification Dispatcher Stub";
        EventSource: Interface "IEventSource";
        StockoutChecker: Interface "IStockoutChecker";
        NotificationDispatcher: Interface "INotificationDispatcher";
    begin
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert();

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := OnHand;
        ILE."Remaining Quantity" := OnHand;
        ILE.Insert();

        SalesLine."Document Type" := SalesLine."Document Type"::Order;
        SalesLine."Document No." := 'SO-1';
        SalesLine."Line No." := 10000;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine."No." := 'ITEM-A';
        SalesLine."Shipment Date" := WorkDate();
        SalesLine.Quantity := EnteredQty;
        SalesLine."Qty. per Unit of Measure" := 1;

        StockoutCheckerStub.SetWouldStockOut(StockoutHits);

        EventSource := EventSourceStub;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotifDispatcherStub;

        Handler.RunGatedFlow(SalesLine, EventSource, StockoutChecker, NotificationDispatcher);
        exit(NotifDispatcherStub.GetDispatchCount());
    end;
}
