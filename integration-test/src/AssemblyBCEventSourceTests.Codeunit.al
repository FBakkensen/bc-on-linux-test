codeunit 50156 "Assembly Evt Src Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure AssemblyOrderHeaderRaisesMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertAssemblyHeader("Assembly Document Type"::Order, UniqueDocNo(), ItemNo, '', '', WorkDate() + 2, 20);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(120, Result, 'Assembly Order header must raise Max Sellable for the assembled item on Due Date.');
    end;

    [Test]
    procedure AssemblyOrderLineLowersMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertAssemblyLine("Assembly Document Type"::Order, UniqueDocNo(), 10000, ItemNo, '', '', WorkDate() + 2, 30);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(70, Result, 'Assembly Order line must lower Max Sellable for the component on Due Date.');
    end;

    [Test]
    procedure BlanketAssemblyOrdersDoNotAffectMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        // ADR 0001 deviation #2: Assembly inclusion is Document Type = Order only.
        // Blanket Assembly headers and lines are excluded — matches the Qty. on Asm. Component
        // FlowField, NOT CU 99000854 InventoryProfileOffsetting which special-cases blanket
        // assembly components as demand.
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertAssemblyHeader("Assembly Document Type"::"Blanket Order", UniqueDocNo(), ItemNo, '', '', WorkDate() + 2, 999);
        InsertAssemblyLine("Assembly Document Type"::"Blanket Order", UniqueDocNo(), 10000, ItemNo, '', '', WorkDate() + 2, 999);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(100, Result, 'ADR 0001 deviation #2: Blanket Assembly orders/lines must not affect Max Sellable.');
    end;

    local procedure MakeItem(var Item: Record Item) ItemNo: Code[20]
    begin
        ItemNo := CopyStr('MST' + Format(CurrentDateTime, 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20);
        Item.Init();
        Item."No." := ItemNo;
        Item.Insert();
    end;

    local procedure UniqueDocNo(): Code[20]
    begin
        exit(CopyStr('ASM-' + Format(CurrentDateTime, 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20));
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

    local procedure InsertAssemblyHeader(DocType: Enum "Assembly Document Type"; DocNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; DueDate: Date; RemainingQtyBase: Decimal)
    var
        AsmHeader: Record "Assembly Header";
    begin
        AsmHeader.Init();
        AsmHeader."Document Type" := DocType;
        AsmHeader."No." := DocNo;
        AsmHeader."Item No." := ItemNo;
        AsmHeader."Variant Code" := VariantCode;
        AsmHeader."Location Code" := LocationCode;
        AsmHeader."Due Date" := DueDate;
        AsmHeader.Quantity := RemainingQtyBase;
        AsmHeader."Quantity (Base)" := RemainingQtyBase;
        AsmHeader."Remaining Quantity" := RemainingQtyBase;
        AsmHeader."Remaining Quantity (Base)" := RemainingQtyBase;
        AsmHeader."Qty. per Unit of Measure" := 1;
        AsmHeader.Insert();
    end;

    local procedure InsertAssemblyLine(DocType: Enum "Assembly Document Type"; DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; DueDate: Date; RemainingQtyBase: Decimal)
    var
        AsmLine: Record "Assembly Line";
    begin
        AsmLine.Init();
        AsmLine."Document Type" := DocType;
        AsmLine."Document No." := DocNo;
        AsmLine."Line No." := LineNo;
        AsmLine.Type := AsmLine.Type::Item;
        AsmLine."No." := ItemNo;
        AsmLine."Variant Code" := VariantCode;
        AsmLine."Location Code" := LocationCode;
        AsmLine."Due Date" := DueDate;
        AsmLine.Quantity := RemainingQtyBase;
        AsmLine."Quantity (Base)" := RemainingQtyBase;
        AsmLine."Remaining Quantity" := RemainingQtyBase;
        AsmLine."Remaining Quantity (Base)" := RemainingQtyBase;
        AsmLine."Qty. per Unit of Measure" := 1;
        AsmLine.Insert();
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
