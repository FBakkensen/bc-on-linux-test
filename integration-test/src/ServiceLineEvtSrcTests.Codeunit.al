namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Sales.Document;
using Microsoft.Service.Document;
using System.TestLibraries.Utilities;

codeunit 50154 "Service Line Evt Src Tests"
{
    Subtype = Test;
    Access = Internal;
    Permissions = tabledata Item = I,
                  tabledata "Item Ledger Entry" = RI,
                  tabledata "Service Line" = I;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure ServiceOrderLineLowersMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        DocNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertServiceLine("Service Document Type"::Order, DocNo, 10000, ItemNo, '', '', WorkDate() + 2, 35);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(65, Result, 'Service Order line must lower Max Sellable on Needed by Date.');
    end;

    [Test]
    procedure ServiceQuoteAndInvoiceLinesDoNotAffectMaxSellable()
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
        InsertServiceLine("Service Document Type"::Quote, QuoteDocNo, 10000, ItemNo, '', '', WorkDate() + 2, 999);
        InsertServiceLine("Service Document Type"::Invoice, InvoiceDocNo, 10000, ItemNo, '', '', WorkDate() + 2, 999);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(100, Result, 'Service Quote and Service Invoice lines must not affect Max Sellable.');
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
        exit(CopyStr('SV-' + Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20));
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

    local procedure InsertServiceLine(DocType: Enum "Service Document Type"; DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; NeededByDate: Date; OutstandingQtyBase: Decimal)
    var
        ServiceLine: Record "Service Line";
    begin
        ServiceLine.Init();
        ServiceLine."Document Type" := DocType;
        ServiceLine."Document No." := DocNo;
        ServiceLine."Line No." := LineNo;
        ServiceLine.Type := ServiceLine.Type::Item;
        ServiceLine."No." := ItemNo;
        ServiceLine."Variant Code" := VariantCode;
        ServiceLine."Location Code" := LocationCode;
        ServiceLine."Needed by Date" := NeededByDate;
        ServiceLine.Quantity := OutstandingQtyBase;
        ServiceLine."Quantity (Base)" := OutstandingQtyBase;
        ServiceLine."Outstanding Quantity" := OutstandingQtyBase;
        ServiceLine."Outstanding Qty. (Base)" := OutstandingQtyBase;
        ServiceLine."Qty. per Unit of Measure" := 1;
        ServiceLine.Insert(false);
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
