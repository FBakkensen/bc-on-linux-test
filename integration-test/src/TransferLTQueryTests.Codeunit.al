namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Inventory.Ledger;
using System.TestLibraries.Utilities;

codeunit 50167 "Transfer LT Query Tests"
{
    Subtype = Test;
    Access = Internal;
    Permissions = tabledata "Item Ledger Entry" = RI;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure EmitsBothSourceAndDestinationTransferILEsForDocument()
    var
        TransferLT: Query "Transfer LT";
        DocNo: Code[20];
        ItemNo: Code[20];
        Rows: Integer;
        SawSource: Boolean;
        SawDest: Boolean;
    begin
        // GIVEN a transfer with both source (-) and destination (+) ILE
        // rows. ADR 0006: the AL Query exposes both; the Python parser
        // pairs them by Document No. + Item + Variant.
        DocNo := UniqueDocNo();
        ItemNo := UniqueItemNo();
        InsertTransferILE(DocNo, ItemNo, '', 'BLUE', 20260401D, -5);
        InsertTransferILE(DocNo, ItemNo, '', 'GREEN', 20260404D, 5);

        TransferLT.SetFilter(itemNo, ItemNo);
        TransferLT.Open();
        while TransferLT.Read() do begin
            Rows += 1;
            Assert.AreEqual(DocNo, TransferLT.documentNo, 'documentNo passes through.');
            if TransferLT.quantity < 0 then begin
                SawSource := true;
                Assert.AreEqual('BLUE', TransferLT.locationCode, 'Source row carries source location.');
                Assert.AreEqual(20260401D, TransferLT.postingDate, 'Source posting date passes through.');
            end;
            if TransferLT.quantity > 0 then begin
                SawDest := true;
                Assert.AreEqual('GREEN', TransferLT.locationCode, 'Destination row carries dest location.');
                Assert.AreEqual(20260404D, TransferLT.postingDate, 'Destination posting date passes through.');
            end;
        end;
        TransferLT.Close();

        Assert.AreEqual(2, Rows, 'Both source and destination ILE rows must be emitted.');
        Assert.IsTrue(SawSource, 'Source row (qty < 0) must appear in the result.');
        Assert.IsTrue(SawDest, 'Destination row (qty > 0) must appear in the result.');
    end;

    [Test]
    procedure ExcludesNonTransferEntryTypes()
    var
        TransferLT: Query "Transfer LT";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        // GIVEN a Sale ILE row for an item that does NOT have any transfer
        // entries — only the Sale ILE should be visible to BC; the query
        // must filter it out server-side.
        ItemNo := UniqueItemNo();
        InsertILEWithEntryType(
            'NOT-A-TRANSFER', ItemNo, '', 'BLUE',
            "Item Ledger Entry Type"::Sale, 20260401D, -3);

        TransferLT.SetFilter(itemNo, ItemNo);
        TransferLT.Open();
        while TransferLT.Read() do
            Rows += 1;
        TransferLT.Close();

        Assert.AreEqual(0, Rows, 'Non-Transfer Entry Types must be excluded server-side.');
    end;

    local procedure InsertTransferILE(DocumentNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; PostingDate: Date; Qty: Decimal)
    begin
        InsertILEWithEntryType(
            DocumentNo, ItemNo, VariantCode, LocationCode,
            "Item Ledger Entry Type"::Transfer, PostingDate, Qty);
    end;

    local procedure InsertILEWithEntryType(DocumentNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; EntryType: Enum "Item Ledger Entry Type"; PostingDate: Date; Qty: Decimal)
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
        ILE."Entry Type" := EntryType;
        ILE."Document No." := DocumentNo;
        ILE."Posting Date" := PostingDate;
        ILE.Quantity := Qty;
        ILE."Remaining Quantity" := Qty;
        ILE.Open := Qty > 0;
        ILE.Positive := Qty > 0;
        ILE.Insert(false);
    end;

    local procedure UniqueDocNo(): Code[20]
    begin
        exit(CopyStr('TR' + UniqueSuffix(), 1, 20));
    end;

    local procedure UniqueItemNo(): Code[20]
    begin
        exit(CopyStr('TRI' + UniqueSuffix(), 1, 20));
    end;

    local procedure UniqueSuffix(): Text
    begin
        exit(Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(99999)));
    end;
}
