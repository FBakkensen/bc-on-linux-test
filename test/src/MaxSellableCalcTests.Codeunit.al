namespace FBakkensen.BcLinuxSmoke.Tests;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Sales.Document;
using System.TestLibraries.Utilities;

codeunit 50100 "Max Sellable Calc Tests"
{
    Subtype = Test;
    Access = Internal;
    Permissions = tabledata Item = ID,
                  tabledata "Item Ledger Entry" = ID;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure CalculateWithEmptyStubsReturnsZero()
    var
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        EventSource: Interface "IEventSource";
        Result: Decimal;
    begin
        Initialize();

        EventSource := EventSourceStub;

        Result := MaxSellableCalc.Calculate(
            '', '', '', WorkDate(), ExcludingSalesLine, EventSource);

        Assert.AreEqual(0, Result, 'Calculate must return 0 with empty stubs.');
    end;

    [Test]
    procedure CalculateReturnsStartingInventoryWhenNoEvents()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        EventSource: Interface "IEventSource";
        Result: Decimal;
    begin
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert(false);

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert(false);

        EventSource := EventSourceStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine, EventSource);

        Assert.AreEqual(100, Result, 'Calculate must return starting inventory when no events.');
    end;

    [Test]
    procedure CalculateAddsFutureSupplyEvent()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        EventSource: Interface "IEventSource";
        Result: Decimal;
    begin
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert(false);

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert(false);

        EventSourceStub.AddEvent(WorkDate() + 3, 50);
        EventSource := EventSourceStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine, EventSource);

        Assert.AreEqual(150, Result, 'Calculate must include future supply events in the projection.');
    end;

    [Test]
    procedure CalculateSubtractsFutureDemandEvent()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        EventSource: Interface "IEventSource";
        Result: Decimal;
    begin
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert(false);

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert(false);

        EventSourceStub.AddEvent(WorkDate() + 3, -30);
        EventSource := EventSourceStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine, EventSource);

        Assert.AreEqual(70, Result, 'Calculate must subtract future demand events from the projection.');
    end;

    [Test]
    procedure CalculateMinWalkPicksMiddleDateDip()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        EventSource: Interface "IEventSource";
        Result: Decimal;
    begin
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert(false);

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert(false);

        // Three events: +20 on D1, -50 on D2, +10 on D3.
        // Balance trace: 100 -> 120 -> 70 -> 80; min is 70 mid-stream.
        EventSourceStub.AddEvent(WorkDate() + 1, 20);
        EventSourceStub.AddEvent(WorkDate() + 2, -50);
        EventSourceStub.AddEvent(WorkDate() + 3, 10);
        EventSource := EventSourceStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine, EventSource);

        Assert.AreEqual(70, Result, 'Min-walk must return the mid-stream limiting balance, not the final.');
    end;

    [Test]
    procedure CalculatePastShipmentDateClampsFloor()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        EventSource: Interface "IEventSource";
        Result: Decimal;
    begin
        Initialize();
        WorkDate(DMY2Date(20, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert(false);

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := DMY2Date(5, 1, 2026);
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert(false);

        ILE.Init();
        ILE."Entry No." := 2;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := DMY2Date(15, 1, 2026);
        ILE.Quantity := 999;
        ILE."Remaining Quantity" := 999;
        ILE.Insert(false);

        EventSource := EventSourceStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', DMY2Date(10, 1, 2026), ExcludingSalesLine, EventSource);

        Assert.AreEqual(100, Result, 'Past ShipmentDate must clamp the floor; later ILE must not count.');
    end;

    [Test]
    procedure CalculateAlreadyNegativeProjectionReturnsZero()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        EventSource: Interface "IEventSource";
        Result: Decimal;
    begin
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert(false);

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 50;
        ILE."Remaining Quantity" := 50;
        ILE.Insert(false);

        EventSourceStub.AddEvent(WorkDate() + 2, -100);
        EventSource := EventSourceStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine, EventSource);

        Assert.AreEqual(0, Result, 'A negative projected balance must clamp to 0.');
    end;

    [Test]
    procedure CalculateExcludesEditingSalesLine()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        EventSource: Interface "IEventSource";
        Result: Decimal;
    begin
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert(false);

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 100;
        ILE."Remaining Quantity" := 100;
        ILE.Insert(false);

        EventSourceStub.AddEventFromLine(WorkDate() + 1, -50, 10000);
        EventSourceStub.AddEventFromLine(WorkDate() + 1, -20, 20000);

        ExcludingSalesLine."Line No." := 10000;
        EventSource := EventSourceStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine, EventSource);

        Assert.AreEqual(80, Result, 'Calculate must exclude the editing Sales Line from the demand aggregate.');
    end;

    [Test]
    procedure CalculateConvertsBaseUoMToLineUoM()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        EventSource: Interface "IEventSource";
        Result: Decimal;
    begin
        Initialize();
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert(false);

        ILE.Init();
        ILE."Entry No." := 1;
        ILE."Item No." := 'ITEM-A';
        ILE."Posting Date" := WorkDate() - 5;
        ILE.Quantity := 60;
        ILE."Remaining Quantity" := 60;
        ILE.Insert(false);

        ExcludingSalesLine."Qty. per Unit of Measure" := 6;
        EventSource := EventSourceStub;

        Result := MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine, EventSource);

        Assert.AreEqual(10, Result, 'Calculate must convert base UoM back to the line UoM.');
    end;

    [Test]
    procedure CalculateIsSideEffectFreeForPBT()
    var
        Item: Record Item;
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        EventSourceStub: Codeunit "Event Source Stub";
        NotificationDispatcherStub: Codeunit "Notification Dispatcher Stub";
        EventSource: Interface "IEventSource";
    begin
        Initialize();
        // Calculate must not dispatch notifications — PBT runs it in a UI-restricted
        // session where any such side effect would crash the background task.
        WorkDate(DMY2Date(15, 1, 2026));

        Item.Init();
        Item."No." := 'ITEM-A';
        Item.Insert(false);

        EventSource := EventSourceStub;

        MaxSellableCalc.Calculate(
            'ITEM-A', '', '', WorkDate(), ExcludingSalesLine, EventSource);

        Assert.AreEqual(0, NotificationDispatcherStub.GetDispatchCount(), 'Calculate must not dispatch notifications — PBT-safe.');
    end;

    local procedure Initialize()
    var
        Item: Record Item;
        ILE: Record "Item Ledger Entry";
    begin
        Item.DeleteAll(false);
        ILE.DeleteAll(false);
    end;
}
