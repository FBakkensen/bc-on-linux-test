namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Sales.Document;
using System.TestLibraries.Utilities;

codeunit 50151 "Sales Line Evt Src Tests"
{
    Subtype = Test;
    Access = Internal;
    Permissions = tabledata Item = I,
                  tabledata "Item Ledger Entry" = RI,
                  tabledata "Sales Line" = I;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure FutureSalesOrderLineLowersMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        DocNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertSalesLine("Sales Document Type"::Order, DocNo, 10000, ItemNo, '', '', WorkDate() + 2, 30);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(70, Result, 'Sales Order line must lower Max Sellable by Outstanding Qty. (Base).');
    end;

    [Test]
    procedure FutureSalesReturnOrderLineRaisesMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        DocNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertSalesLine("Sales Document Type"::"Return Order", DocNo, 10000, ItemNo, '', '', WorkDate() + 2, 20);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(120, Result, 'Sales Return Order line must raise Max Sellable by Outstanding Qty. (Base).');
    end;

    [Test]
    procedure SalesQuoteAndInvoiceLinesDoNotAffectMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        QuoteDocNo: Code[20];
        InvoiceDocNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        QuoteDocNo := UniqueDocNo();
        InvoiceDocNo := UniqueDocNo();
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertSalesLine("Sales Document Type"::Quote, QuoteDocNo, 10000, ItemNo, '', '', WorkDate() + 2, 999);
        InsertSalesLine("Sales Document Type"::Invoice, InvoiceDocNo, 10000, ItemNo, '', '', WorkDate() + 2, 999);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(100, Result, 'Sales Quote and Sales Invoice lines must not affect Max Sellable.');
    end;

    [Test]
    procedure EditingSalesLineIsExcludedFromAggregate()
    var
        Item: Record Item;
        ExcludingSalesLine: Record "Sales Line";
        ItemNo: Code[20];
        DocNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertSalesLine("Sales Document Type"::Order, DocNo, 10000, ItemNo, '', '', WorkDate() + 2, 30);
        InsertSalesLine("Sales Document Type"::Order, DocNo, 20000, ItemNo, '', '', WorkDate() + 2, 20);

        ExcludingSalesLine."Document Type" := "Sales Document Type"::Order;
        ExcludingSalesLine."Document No." := DocNo;
        ExcludingSalesLine."Line No." := 10000;

        Result := RunCalculateWithExclusion(ItemNo, '', '', WorkDate(), ExcludingSalesLine);

        Assert.AreEqual(80, Result, 'Editing Sales Line (-30) must be excluded; only the other line (-20) counts.');
    end;

    [Test]
    procedure VariantAndLocationFilterTheIteration()
    var
        Item: Record Item;
        ItemNo: Code[20];
        DocNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();

        // GIVEN on-hand split across two (Variant, Location) buckets
        SeedOnHand(ItemNo, 'V1', 'L1', WorkDate() - 5, 100);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 999);

        // AND a demand on each bucket
        InsertSalesLine("Sales Document Type"::Order, DocNo, 10000, ItemNo, 'V1', 'L1', WorkDate() + 2, 30);
        InsertSalesLine("Sales Document Type"::Order, DocNo, 20000, ItemNo, '', '', WorkDate() + 2, 999);

        // WHEN we Calculate for the V1/L1 bucket
        Result := RunCalculate(ItemNo, 'V1', 'L1', WorkDate());

        // THEN only the V1/L1 ILE and the V1/L1 sales line contribute: 100 - 30 = 70
        Assert.AreEqual(70, Result, 'Variant and Location must filter the event iteration; blank-variant lines must not leak in.');
    end;

    local procedure MakeItem(var Item: Record Item) ItemNo: Code[20]
    begin
        ItemNo := CopyStr('MST' + Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20);
        Item.Init();
        Item."No." := ItemNo;
        Item.Insert(false);
    end;

    local procedure UniqueDocNo(): Code[20]
    begin
        exit(CopyStr('SO-' + Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20));
    end;

    local procedure SeedOnHand(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; PostingDate: Date; Qty: Decimal)
    var
        ILE: Record "Item Ledger Entry";
        Last: Record "Item Ledger Entry";
        NextEntryNo: Integer;
    begin
        Last.SetLoadFields("Entry No.");
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
        ILE.Insert(false);
    end;

    local procedure InsertSalesLine(DocType: Enum "Sales Document Type"; DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; ShipmentDate: Date; OutstandingQtyBase: Decimal)
    var
        SalesLine: Record "Sales Line";
    begin
        SalesLine.Init();
        SalesLine."Document Type" := DocType;
        SalesLine."Document No." := DocNo;
        SalesLine."Line No." := LineNo;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine."No." := ItemNo;
        SalesLine."Variant Code" := VariantCode;
        SalesLine."Location Code" := LocationCode;
        SalesLine."Shipment Date" := ShipmentDate;
        SalesLine.Quantity := OutstandingQtyBase;
        SalesLine."Quantity (Base)" := OutstandingQtyBase;
        SalesLine."Outstanding Quantity" := OutstandingQtyBase;
        SalesLine."Outstanding Qty. (Base)" := OutstandingQtyBase;
        SalesLine."Qty. per Unit of Measure" := 1;
        SalesLine.Insert(false);
    end;

    local procedure RunCalculate(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; ShipmentDate: Date): Decimal
    var
        ExcludingSalesLine: Record "Sales Line";
    begin
        exit(RunCalculateWithExclusion(ItemNo, VariantCode, LocationCode, ShipmentDate, ExcludingSalesLine));
    end;

    local procedure RunCalculateWithExclusion(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; ShipmentDate: Date; var ExcludingSalesLine: Record "Sales Line"): Decimal
    var
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        BCEventSource: Codeunit "BC Event Source";
        EventSource: Interface "IEventSource";
    begin
        EventSource := BCEventSource;
        exit(MaxSellableCalc.Calculate(
            ItemNo, VariantCode, LocationCode, ShipmentDate, ExcludingSalesLine,
            EventSource));
    end;
}
