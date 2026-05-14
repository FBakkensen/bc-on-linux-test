codeunit 50159 "Max Sellable FactBox Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure PBTComputesMaxSellableForSingleLine()
    var
        Item: Record Item;
        SalesLine: Record "Sales Line";
        PBT: Codeunit "Max Sellable PBT";
        Params: Dictionary of [Text, Text];
        Results: Dictionary of [Text, Text];
        ItemNo: Code[20];
        DocNo: Code[20];
        QtyText: Text;
        Qty: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();

        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);

        SalesLine."Document Type" := SalesLine."Document Type"::Order;
        SalesLine."Document No." := DocNo;
        SalesLine."Line No." := 10000;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine."No." := ItemNo;
        SalesLine."Shipment Date" := WorkDate();
        SalesLine.Quantity := 100;
        SalesLine."Qty. per Unit of Measure" := 1;
        SalesLine.Insert();

        Params := PBT.BuildParameters(SalesLine);
        Results := PBT.ComputeFromParameters(Params);

        Assert.IsTrue(Results.Get('Qty', QtyText), 'PBT must return a Qty key in its output dictionary.');
        Evaluate(Qty, QtyText, 9);
        Assert.AreEqual(100, Qty, 'PBT result must match the Max Sellable Qty for the line tuple (starting on-hand, no other events).');
    end;

    [Test]
    procedure PBTReflectsUpstreamPurchaseReceiptChange()
    var
        Item: Record Item;
        SalesLine: Record "Sales Line";
        PBT: Codeunit "Max Sellable PBT";
        Params: Dictionary of [Text, Text];
        Results: Dictionary of [Text, Text];
        ItemNo: Code[20];
        DocNo: Code[20];
        QtyText: Text;
        Qty: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();

        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);

        SalesLine."Document Type" := SalesLine."Document Type"::Order;
        SalesLine."Document No." := DocNo;
        SalesLine."Line No." := 10000;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine."No." := ItemNo;
        SalesLine."Shipment Date" := WorkDate();
        SalesLine.Quantity := 100;
        SalesLine."Qty. per Unit of Measure" := 1;
        SalesLine.Insert();

        // Upstream change: a Purchase Order line will receive +50 in the future.
        InsertPurchaseOrderLine(ItemNo, '', '', WorkDate() + 3, 50);

        Params := PBT.BuildParameters(SalesLine);
        Results := PBT.ComputeFromParameters(Params);

        Results.Get('Qty', QtyText);
        Evaluate(Qty, QtyText, 9);
        Assert.AreEqual(150, Qty, 'A new Purchase Order line must be reflected in the PBT result on the next compute.');
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
        exit(CopyStr('SO-' + Format(CurrentDateTime, 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20));
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

    local procedure InsertPurchaseOrderLine(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; ExpectedReceiptDate: Date; OutstandingQtyBase: Decimal)
    var
        PurchLine: Record "Purchase Line";
    begin
        PurchLine.Init();
        PurchLine."Document Type" := PurchLine."Document Type"::Order;
        PurchLine."Document No." := CopyStr('PO-' + Format(CurrentDateTime, 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20);
        PurchLine."Line No." := 10000;
        PurchLine.Type := PurchLine.Type::Item;
        PurchLine."No." := ItemNo;
        PurchLine."Variant Code" := VariantCode;
        PurchLine."Location Code" := LocationCode;
        PurchLine."Expected Receipt Date" := ExpectedReceiptDate;
        PurchLine.Quantity := OutstandingQtyBase;
        PurchLine."Quantity (Base)" := OutstandingQtyBase;
        PurchLine."Outstanding Quantity" := OutstandingQtyBase;
        PurchLine."Outstanding Qty. (Base)" := OutstandingQtyBase;
        PurchLine."Qty. per Unit of Measure" := 1;
        PurchLine.Insert();
    end;
}
