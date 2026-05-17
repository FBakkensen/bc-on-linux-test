namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Transfer;
using Microsoft.Sales.Document;
using System.TestLibraries.Utilities;

codeunit 50153 "Transfer Line Evt Src Tests"
{
    Subtype = Test;
    Access = Internal;
    Permissions = tabledata Item = I,
                  tabledata "Item Ledger Entry" = RI,
                  tabledata "Transfer Line" = I;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure TransferReceiptLegRaisesAtDestinationOnReceiptDate()
    var
        Item: Record Item;
        ItemNo: Code[20];
        DocNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();
        // GIVEN starting on-hand at the destination L-DEST
        SeedOnHand(ItemNo, '', 'L-DEST', WorkDate() - 5, 100);
        // AND a transfer in flight: 40 from L-SRC to L-DEST
        InsertTransferLine(DocNo, 10000, ItemNo, '', 'L-SRC', 'L-DEST', WorkDate() + 1, WorkDate() + 3, 40);

        Result := RunCalculate(ItemNo, '', 'L-DEST', WorkDate());

        Assert.AreEqual(140, Result, 'Transfer receipt leg must raise Max Sellable at destination on Receipt Date.');
    end;

    [Test]
    procedure TransferShipmentLegLowersAtSourceOnShipmentDate()
    var
        Item: Record Item;
        ItemNo: Code[20];
        DocNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();
        // GIVEN starting on-hand at the source L-SRC
        SeedOnHand(ItemNo, '', 'L-SRC', WorkDate() - 5, 100);
        // AND a transfer outbound: 40 from L-SRC to L-DEST
        InsertTransferLine(DocNo, 10000, ItemNo, '', 'L-SRC', 'L-DEST', WorkDate() + 1, WorkDate() + 3, 40);

        Result := RunCalculate(ItemNo, '', 'L-SRC', WorkDate());

        Assert.AreEqual(60, Result, 'Transfer shipment leg must lower Max Sellable at source on Shipment Date.');
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
        exit(CopyStr('TO-' + Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20));
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

    local procedure InsertTransferLine(DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; FromLoc: Code[10]; ToLoc: Code[10]; ShipmentDate: Date; ReceiptDate: Date; OutstandingQtyBase: Decimal)
    var
        TransferLine: Record "Transfer Line";
    begin
        TransferLine.Init();
        TransferLine."Document No." := DocNo;
        TransferLine."Line No." := LineNo;
        TransferLine."Item No." := ItemNo;
        TransferLine."Variant Code" := VariantCode;
        TransferLine."Transfer-from Code" := FromLoc;
        TransferLine."Transfer-to Code" := ToLoc;
        TransferLine."Shipment Date" := ShipmentDate;
        TransferLine."Receipt Date" := ReceiptDate;
        TransferLine.Quantity := OutstandingQtyBase;
        TransferLine."Quantity (Base)" := OutstandingQtyBase;
        TransferLine."Outstanding Quantity" := OutstandingQtyBase;
        TransferLine."Outstanding Qty. (Base)" := OutstandingQtyBase;
        TransferLine."Derived From Line No." := 0;
        TransferLine."Qty. per Unit of Measure" := 1;
        TransferLine.Insert(false);
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
