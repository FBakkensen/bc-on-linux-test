codeunit 50163 "ILE Summary Query Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure GroupsAndSumsSignedQuantityByItemVariantLocationPostingDate()
    var
        ILESummary: Query "Item Ledger Summary";
        BucketQty: Dictionary of [Text, Decimal];
        ItemNo: Code[20];
        Day1: Date;
        Day2: Date;
    begin
        // GIVEN ILE rows across 2 days × 2 locations for one item, mixed signs
        ItemNo := UniqueItemNo();
        Day1 := WorkDate();
        Day2 := WorkDate() + 1;

        InsertILE(ItemNo, '', 'BLUE', Day1, -10);
        InsertILE(ItemNo, '', 'BLUE', Day1, -20); // same bucket → must sum
        InsertILE(ItemNo, '', 'BLUE', Day1, 5);   // return → nets against demand
        InsertILE(ItemNo, '', 'RED', Day1, -40);  // different location → different row
        InsertILE(ItemNo, '', 'BLUE', Day2, -50); // different day → different row

        // WHEN we read the Item Ledger Summary query, filtered to our test item
        ILESummary.SetFilter(itemNo, ItemNo);
        ILESummary.Open();
        while ILESummary.Read() do
            // Dictionary.Add throws on duplicate keys → also asserts uniqueness per bucket.
            BucketQty.Add(
                BucketKey(ILESummary.variantCode, ILESummary.locationCode, ILESummary.postingDate),
                ILESummary.quantity);
        ILESummary.Close();

        // THEN exactly 3 rows, one per (variant, location, date) bucket for our item
        Assert.AreEqual(3, BucketQty.Count, 'Query must produce one row per (item, variant, location, posting_date) bucket.');
        Assert.AreEqual(-25, BucketQty.Get(BucketKey('', 'BLUE', Day1)), 'Day1/BLUE: sum(-10, -20, +5) = -25 (returns net against demand).');
        Assert.AreEqual(-40, BucketQty.Get(BucketKey('', 'RED', Day1)), 'Day1/RED: sum(-40) = -40.');
        Assert.AreEqual(-50, BucketQty.Get(BucketKey('', 'BLUE', Day2)), 'Day2/BLUE: sum(-50) = -50.');
    end;

    local procedure BucketKey(VariantCode: Code[10]; LocationCode: Code[10]; PostingDate: Date): Text
    begin
        exit(StrSubstNo('%1|%2|%3', VariantCode, LocationCode, Format(PostingDate, 0, 9)));
    end;

    local procedure UniqueItemNo(): Code[20]
    begin
        exit(CopyStr('ILS' + Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20));
    end;

    local procedure InsertILE(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; PostingDate: Date; Qty: Decimal)
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
        ILE.Insert(false);
    end;
}
