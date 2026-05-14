codeunit 50157 "Job Planning Evt Src Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure BudgetLineLowersMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertJobPlanningLine("Job Planning Line Status"::Order, "Job Planning Line Line Type"::Budget, UniqueJobNo(), 10000, ItemNo, '', '', WorkDate() + 2, 25);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(75, Result, 'Status=Order, Line Type=Budget Job Planning Line must lower Max Sellable.');
    end;

    [Test]
    procedure BillableLineLowersMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertJobPlanningLine("Job Planning Line Status"::Order, "Job Planning Line Line Type"::Billable, UniqueJobNo(), 10000, ItemNo, '', '', WorkDate() + 2, 25);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(75, Result, 'Status=Order, Line Type=Billable Job Planning Line must lower Max Sellable.');
    end;

    [Test]
    procedure BothBudgetAndBillableLineCountedTwice()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        // ADR 0001 deviation #3: BC's Job availability does not apply a Line Type filter.
        // We honour that verbatim — a Both Budget and Billable line contributes its
        // Remaining Qty. (Base) once as the Budget leg and once as the Billable leg,
        // matching BC standard's double-count rather than de-duping in our own code.
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertJobPlanningLine("Job Planning Line Status"::Order, "Job Planning Line Line Type"::"Both Budget and Billable", UniqueJobNo(), 10000, ItemNo, '', '', WorkDate() + 2, 25);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(50, Result, 'ADR 0001 deviation #3: Both Budget and Billable line must count twice (25 + 25 = 50 demand).');
    end;

    [Test]
    procedure NonOrderStatusJobPlanningLinesAreIgnored()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertJobPlanningLine("Job Planning Line Status"::Planning, "Job Planning Line Line Type"::Budget, UniqueJobNo(), 10000, ItemNo, '', '', WorkDate() + 2, 999);
        InsertJobPlanningLine("Job Planning Line Status"::Quote, "Job Planning Line Line Type"::Budget, UniqueJobNo(), 10000, ItemNo, '', '', WorkDate() + 2, 999);
        InsertJobPlanningLine("Job Planning Line Status"::Completed, "Job Planning Line Line Type"::Budget, UniqueJobNo(), 10000, ItemNo, '', '', WorkDate() + 2, 999);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(100, Result, 'Job Planning Lines with Status other than Order must not affect Max Sellable.');
    end;

    local procedure MakeItem(var Item: Record Item) ItemNo: Code[20]
    begin
        ItemNo := CopyStr('MST' + Format(CurrentDateTime, 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20);
        Item.Init();
        Item."No." := ItemNo;
        Item.Insert();
    end;

    local procedure UniqueJobNo(): Code[20]
    begin
        exit(CopyStr('PRJ-' + Format(CurrentDateTime, 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20));
    end;

    local procedure SeedOnHand(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; PostingDate: Date; Qty: Decimal)
    var
        ILE: Record "Item Ledger Entry";
        Last: Record "Item Ledger Entry";
        NextEntryNo: Integer;
    begin
        if Last.FindLast() then
            NextEntryNo := Last."Entry No." + 1
        else
            NextEntryNo := 1;
        ILE.Init();
        ILE."Entry No." := NextEntryNo;
        ILE."Item No." := ItemNo;
        ILE."Variant Code" := VariantCode;
        ILE."Location Code" := LocationCode;
        ILE."Posting Date" := PostingDate;
        ILE.Quantity := Qty;
        ILE."Remaining Quantity" := Qty;
        ILE.Open := Qty > 0;
        ILE.Positive := Qty > 0;
        ILE.Insert();
    end;

    local procedure InsertJobPlanningLine(Status: Enum "Job Planning Line Status"; LineType: Enum "Job Planning Line Line Type"; JobNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; PlanningDate: Date; RemainingQtyBase: Decimal)
    var
        JPL: Record "Job Planning Line";
    begin
        JPL.Init();
        JPL.Status := Status;
        JPL."Job No." := JobNo;
        JPL."Job Task No." := 'T1';
        JPL."Line No." := LineNo;
        JPL.Type := JPL.Type::Item;
        JPL."Line Type" := LineType;
        JPL."No." := ItemNo;
        JPL."Variant Code" := VariantCode;
        JPL."Location Code" := LocationCode;
        JPL."Planning Date" := PlanningDate;
        JPL.Quantity := RemainingQtyBase;
        JPL."Quantity (Base)" := RemainingQtyBase;
        JPL."Remaining Qty." := RemainingQtyBase;
        JPL."Remaining Qty. (Base)" := RemainingQtyBase;
        JPL."Qty. per Unit of Measure" := 1;
        JPL.Insert();
    end;

    local procedure RunCalculate(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; ShipmentDate: Date): Decimal
    var
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        BCEventSource: Codeunit "BC Event Source";
        StockoutCheckerStub: Codeunit "IT Stockout Checker Stub";
        NotifDispatcherStub: Codeunit "IT Notif. Dispatcher Stub";
        EventSource: Interface "IEventSource";
        StockoutChecker: Interface "IStockoutChecker";
        NotificationDispatcher: Interface "INotificationDispatcher";
    begin
        EventSource := BCEventSource;
        StockoutChecker := StockoutCheckerStub;
        NotificationDispatcher := NotifDispatcherStub;
        exit(MaxSellableCalc.Calculate(
            ItemNo, VariantCode, LocationCode, ShipmentDate, ExcludingSalesLine,
            EventSource, StockoutChecker, NotificationDispatcher));
    end;
}
