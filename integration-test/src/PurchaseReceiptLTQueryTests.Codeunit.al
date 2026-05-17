codeunit 50164 "Purch Receipt LT Query Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure EmitsRowAndJoinsPurchaseHeaderForExpectedReceiptDate()
    var
        PurchReceiptLT: Query "Purchase Receipt LT";
        ItemNo: Code[20];
        PoNo: Code[20];
        ReceiptNo: Code[20];
        OrderDate: Date;
        ExpectedReceiptDate: Date;
        PostingDate: Date;
        Rows: Integer;
    begin
        // GIVEN a Purchase Header with Expected Receipt Date 2 days before the
        // posted receipt's posting date, and matching receipt header + line
        ItemNo := UniqueItemNo();
        PoNo := UniquePoNo();
        ReceiptNo := UniqueReceiptNo();
        OrderDate := WorkDate();
        ExpectedReceiptDate := OrderDate + 5;
        PostingDate := OrderDate + 7;

        InsertPurchaseHeader(PoNo, OrderDate, ExpectedReceiptDate);
        InsertPurchRcptHeader(ReceiptNo, PoNo, 'V-001', OrderDate);
        InsertReceiptLine(ReceiptNo, 10000, ItemNo, '', 'BLUE', PostingDate, 12);

        // WHEN we read the query filtered to our test item
        PurchReceiptLT.SetFilter(itemNo, ItemNo);
        PurchReceiptLT.Open();
        while PurchReceiptLT.Read() do begin
            Rows += 1;
            // THEN the joined Purchase Header supplies the expected date —
            // the join (line → receipt header → purchase header via order
            // no.) is what proves the API surface matches the spec.
            Assert.AreEqual('BLUE', PurchReceiptLT.locationCode, 'locationCode passes through.');
            Assert.AreEqual('V-001', PurchReceiptLT.vendorNo, 'vendorNo joined from receipt header.');
            Assert.AreEqual(PostingDate, PurchReceiptLT.receiptPostingDate, 'receiptPostingDate from receipt line.');
            Assert.AreEqual(OrderDate, PurchReceiptLT.poOrderDate, 'poOrderDate joined from receipt header.');
            Assert.AreEqual(ExpectedReceiptDate, PurchReceiptLT.expectedReceiptDate, 'expectedReceiptDate joined from Purchase Header.');
            Assert.AreEqual(12, PurchReceiptLT.quantity, 'quantity passes through.');
            Assert.AreEqual(ReceiptNo, PurchReceiptLT.documentNo, 'documentNo from receipt line.');
        end;
        PurchReceiptLT.Close();

        Assert.AreEqual(1, Rows, 'Exactly one row per posted receipt line.');
    end;

    [Test]
    procedure ExcludesDropShipmentLines()
    var
        PurchReceiptLT: Query "Purchase Receipt LT";
        ItemNo: Code[20];
        ReceiptNo: Code[20];
        Rows: Integer;
    begin
        // GIVEN a drop-shipment receipt line — Sales Order No. is filled
        // when the PO line was flagged Drop Shipment and points at the
        // originating sales line. ADR 0006 excludes these from LTD samples
        // because they're item-specific demand, not replenishment lead time.
        ItemNo := UniqueItemNo();
        ReceiptNo := UniqueReceiptNo();
        InsertPurchRcptHeader(ReceiptNo, '', 'V-001', WorkDate());
        InsertDropShipmentReceiptLine(ReceiptNo, 10000, ItemNo, 'BLUE', WorkDate(), 5, 'SO-DROP');

        // WHEN we read the query
        PurchReceiptLT.SetFilter(itemNo, ItemNo);
        PurchReceiptLT.Open();
        while PurchReceiptLT.Read() do
            Rows += 1;
        PurchReceiptLT.Close();

        // THEN no rows — server-side filter must drop drop-shipment lines.
        Assert.AreEqual(0, Rows, 'Drop-shipment lines must be excluded server-side.');
    end;

    [Test]
    procedure ExcludesSpecialOrderLines()
    var
        PurchReceiptLT: Query "Purchase Receipt LT";
        ItemNo: Code[20];
        ReceiptNo: Code[20];
        Rows: Integer;
    begin
        // Same exclusion rationale as drop-shipment: special-order receipts
        // are item-specific, not replenishment lead time.
        ItemNo := UniqueItemNo();
        ReceiptNo := UniqueReceiptNo();
        InsertPurchRcptHeader(ReceiptNo, '', 'V-001', WorkDate());
        InsertSpecialOrderReceiptLine(ReceiptNo, 10000, ItemNo, 'BLUE', WorkDate(), 5, 'SO-SPECIAL');

        PurchReceiptLT.SetFilter(itemNo, ItemNo);
        PurchReceiptLT.Open();
        while PurchReceiptLT.Read() do
            Rows += 1;
        PurchReceiptLT.Close();

        Assert.AreEqual(0, Rows, 'Special-order lines must be excluded server-side.');
    end;

    [Test]
    procedure EmitsRowEvenWhenPurchaseHeaderIsMissing()
    var
        PurchReceiptLT: Query "Purchase Receipt LT";
        ItemNo: Code[20];
        ReceiptNo: Code[20];
        Rows: Integer;
        ExpectedDateField: Date;
    begin
        // GIVEN a receipt whose source Purchase Header has been deleted —
        // realistic when the PO has been fully invoiced and archived. The
        // join must left-outer so the row survives, but the Expected Receipt
        // Date column comes back null. Acceptance criteria: row still
        // emitted, plan_to_receipt nulls, order_to_receipt still derivable.
        ItemNo := UniqueItemNo();
        ReceiptNo := UniqueReceiptNo();
        InsertPurchRcptHeader(ReceiptNo, 'PO-GONE', 'V-001', WorkDate());
        InsertReceiptLine(ReceiptNo, 10000, ItemNo, '', 'BLUE', WorkDate(), 3);

        PurchReceiptLT.SetFilter(itemNo, ItemNo);
        PurchReceiptLT.Open();
        while PurchReceiptLT.Read() do begin
            Rows += 1;
            ExpectedDateField := PurchReceiptLT.expectedReceiptDate;
            Assert.AreEqual(WorkDate(), PurchReceiptLT.poOrderDate, 'poOrderDate is captured on the receipt header — must survive a missing PO.');
        end;
        PurchReceiptLT.Close();

        Assert.AreEqual(1, Rows, 'Row must still be emitted via left-outer join when the Purchase Header is gone.');
        Assert.AreEqual(0D, ExpectedDateField, 'expectedReceiptDate must be null (0D) when Purchase Header is missing.');
    end;

    local procedure InsertPurchaseHeader(No: Code[20]; OrderDate: Date; ExpectedReceiptDate: Date)
    var
        PurchaseHeader: Record "Purchase Header";
    begin
        PurchaseHeader.Init();
        PurchaseHeader."Document Type" := PurchaseHeader."Document Type"::Order;
        PurchaseHeader."No." := No;
        PurchaseHeader."Order Date" := OrderDate;
        PurchaseHeader."Expected Receipt Date" := ExpectedReceiptDate;
        PurchaseHeader.Insert(false);
    end;

    local procedure InsertPurchRcptHeader(No: Code[20]; OrderNo: Code[20]; VendorNo: Code[20]; OrderDate: Date)
    var
        PurchRcptHeader: Record "Purch. Rcpt. Header";
    begin
        PurchRcptHeader.Init();
        PurchRcptHeader."No." := No;
        PurchRcptHeader."Order No." := OrderNo;
        PurchRcptHeader."Buy-from Vendor No." := VendorNo;
        PurchRcptHeader."Order Date" := OrderDate;
        PurchRcptHeader.Insert(false);
    end;

    local procedure InsertReceiptLine(DocumentNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; PostingDate: Date; Qty: Decimal)
    begin
        InsertReceiptLineRaw(DocumentNo, LineNo, ItemNo, VariantCode, LocationCode, PostingDate, Qty, '', '');
    end;

    local procedure InsertDropShipmentReceiptLine(DocumentNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; LocationCode: Code[10]; PostingDate: Date; Qty: Decimal; SalesOrderNo: Code[20])
    begin
        InsertReceiptLineRaw(DocumentNo, LineNo, ItemNo, '', LocationCode, PostingDate, Qty, SalesOrderNo, '');
    end;

    local procedure InsertSpecialOrderReceiptLine(DocumentNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; LocationCode: Code[10]; PostingDate: Date; Qty: Decimal; SpecialOrderSalesNo: Code[20])
    begin
        InsertReceiptLineRaw(DocumentNo, LineNo, ItemNo, '', LocationCode, PostingDate, Qty, '', SpecialOrderSalesNo);
    end;

    local procedure InsertReceiptLineRaw(DocumentNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; PostingDate: Date; Qty: Decimal; SalesOrderNo: Code[20]; SpecialOrderSalesNo: Code[20])
    var
        PurchRcptLine: Record "Purch. Rcpt. Line";
    begin
        PurchRcptLine.Init();
        PurchRcptLine."Document No." := DocumentNo;
        PurchRcptLine."Line No." := LineNo;
        PurchRcptLine.Type := PurchRcptLine.Type::Item;
        PurchRcptLine."No." := ItemNo;
        PurchRcptLine."Variant Code" := VariantCode;
        PurchRcptLine."Location Code" := LocationCode;
        PurchRcptLine.Quantity := Qty;
        PurchRcptLine."Posting Date" := PostingDate;
        PurchRcptLine."Sales Order No." := SalesOrderNo;
        PurchRcptLine."Special Order Sales No." := SpecialOrderSalesNo;
        PurchRcptLine.Insert(false);
    end;

    local procedure UniqueItemNo(): Code[20]
    begin
        exit(CopyStr('PRL' + UniqueSuffix(), 1, 20));
    end;

    local procedure UniquePoNo(): Code[20]
    begin
        exit(CopyStr('PO' + UniqueSuffix(), 1, 20));
    end;

    local procedure UniqueReceiptNo(): Code[20]
    begin
        exit(CopyStr('RCP' + UniqueSuffix(), 1, 20));
    end;

    local procedure UniqueSuffix(): Text
    begin
        exit(Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(99999)));
    end;
}
