namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using System.TestLibraries.Utilities;

codeunit 50152 "Purch Line Evt Src Tests"
{
    Subtype = Test;
    Access = Internal;
    Permissions = tabledata Item = I,
                  tabledata "Item Ledger Entry" = RI,
                  tabledata "Purchase Line" = I;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure FuturePurchaseOrderLineRaisesMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        DocNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertPurchaseLine("Purchase Document Type"::Order, DocNo, 10000, ItemNo, '', '', WorkDate() + 2, 25);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(125, Result, 'Purchase Order line must raise Max Sellable by Outstanding Qty. (Base) on Expected Receipt Date.');
    end;

    [Test]
    procedure FuturePurchaseReturnOrderLineLowersMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        DocNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertPurchaseLine("Purchase Document Type"::"Return Order", DocNo, 10000, ItemNo, '', '', WorkDate() + 2, 15);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(85, Result, 'Purchase Return Order line must lower Max Sellable.');
    end;

    [Test]
    procedure PurchaseQuoteAndInvoiceLinesDoNotAffectMaxSellable()
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
        InsertPurchaseLine("Purchase Document Type"::Quote, QuoteDocNo, 10000, ItemNo, '', '', WorkDate() + 2, 999);
        InsertPurchaseLine("Purchase Document Type"::Invoice, InvoiceDocNo, 10000, ItemNo, '', '', WorkDate() + 2, 999);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(100, Result, 'Purchase Quote and Purchase Invoice lines must not affect Max Sellable.');
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
        exit(CopyStr('PO-' + Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20));
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

    local procedure InsertPurchaseLine(DocType: Enum "Purchase Document Type"; DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; ExpectedReceiptDate: Date; OutstandingQtyBase: Decimal)
    var
        PurchLine: Record "Purchase Line";
    begin
        PurchLine.Init();
        PurchLine."Document Type" := DocType;
        PurchLine."Document No." := DocNo;
        PurchLine."Line No." := LineNo;
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
        PurchLine.Insert(false);
    end;

    local procedure RunCalculate(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; ShipmentDate: Date): Decimal
    var
        ExcludingSalesLine: Record "Sales Line";
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
