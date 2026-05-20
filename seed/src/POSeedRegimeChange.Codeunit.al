namespace FBakkensen.BcLinuxSmoke.Seed;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Posting;

codeunit 50208 "PO Seed Regime Change"
{
    Access = Public;
    Permissions = tabledata Item = R,
                  tabledata "Item Journal Line" = RIMD,
                  tabledata "Item Ledger Entry" = RIM,
                  tabledata "Value Entry" = RIM;

    var
        RegimeOffsetFmtLbl: Label '<-%1M>', Comment = '%1 = months back from SEED_TODAY', Locked = true;
        DocNoRXFmtLbl: Label 'RX-%1', Comment = '%1 = posting date YYYYMMDD', Locked = true;
        DateAsYYYYMMDDFmtLbl: Label '<Year4><Month,2><Day,2>', Locked = true;

    procedure ApplyRegimeChange(SeedTodayParam: Date)
    var
        Constants: Codeunit "PO Seed Constants";
        Item: Record Item;
        Rng: Codeunit "PO Seed Rng";
        ItemIndex: Integer;
    begin
        Rng.Init(Constants.RngSeedForCompany(CompanyName()) + 3);
        ItemIndex := 0;
        if Item.FindSet() then
            repeat
                ItemIndex += 1;
                if InRegimeChangeCohort(Item."No.", ItemIndex) then
                    OverlayRegimeChange(Item, SeedTodayParam, Rng);
            until Item.Next() = 0;
    end;

    local procedure InRegimeChangeCohort(ItemNo: Code[20]; ItemIndex: Integer): Boolean
    begin
        if CopyStr(ItemNo, 1, 5) <> 'POS-I' then
            exit(false);
        exit(ItemIndex mod 11 = 0);
    end;

    local procedure OverlayRegimeChange(Item: Record Item; SeedTodayParam: Date; var Rng: Codeunit "PO Seed Rng")
    var
        Constants: Codeunit "PO Seed Constants";
        RegimeStart: Date;
        DaysInRegime: Integer;
        ExtraEvents: Integer;
        Idx: Integer;
        EventDate: Date;
        Quantity: Decimal;
    begin
        RegimeStart := CalcDate(StrSubstNo(RegimeOffsetFmtLbl, Constants.RegimeChangeOffsetMonths()), SeedTodayParam);
        DaysInRegime := SeedTodayParam - RegimeStart;
        if DaysInRegime <= 0 then
            exit;
        ExtraEvents := 30;
        for Idx := 1 to ExtraEvents do begin
            EventDate := RegimeStart + ((Idx - 1) * DaysInRegime) div ExtraEvents;
            Quantity := Rng.NextIntInRange(5, 25);
            PostExtraSale(Item."No.", EventDate, Quantity, Constants.LocationBlueCode());
        end;
    end;

    local procedure PostExtraSale(ItemNo: Code[20]; PostingDate: Date; Quantity: Decimal; LocationCode: Code[10])
    var
        ItemJournalLine: Record "Item Journal Line";
        ItemJnlPostLine: Codeunit "Item Jnl.-Post Line";
        Constants: Codeunit "PO Seed Constants";
        DocNo: Code[20];
    begin
        DocNo := CopyStr(StrSubstNo(DocNoRXFmtLbl, Format(PostingDate, 0, DateAsYYYYMMDDFmtLbl)), 1, 20);
        ItemJournalLine.Init();
        ItemJournalLine."Entry Type" := "Item Ledger Entry Type"::Sale;
        ItemJournalLine."Posting Date" := PostingDate;
        ItemJournalLine."Document Date" := PostingDate;
        ItemJournalLine."Document No." := DocNo;
        ItemJournalLine.Validate("Item No.", ItemNo);
        ItemJournalLine.Validate("Location Code", LocationCode);
        ItemJournalLine.Validate(Quantity, Quantity);
        ItemJournalLine."Source Code" := Constants.SourceCodeTok();
        ItemJnlPostLine.RunWithCheck(ItemJournalLine);
    end;
}
