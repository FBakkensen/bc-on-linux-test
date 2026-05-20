namespace FBakkensen.BcLinuxSmoke.Seed;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Posting;

codeunit 50209 "PO Seed Stockout History"
{
    Access = Public;
    Permissions = tabledata Item = R,
                  tabledata "Item Journal Line" = RIMD,
                  tabledata "Item Ledger Entry" = RIM,
                  tabledata "Value Entry" = RIM;

    var
        SixMonthsBackTok: Label '<-6M>', Locked = true;
        DocNoFmtLbl: Label '%1-%2', Comment = '%1 = prefix; %2 = date YYYYMMDD', Locked = true;
        DateAsYYYYMMDDFmtLbl: Label '<Year4><Month,2><Day,2>', Locked = true;
        StockoutPrefixTok: Label 'SO-DOWN', Locked = true;
        RestockPrefixTok: Label 'SO-UP', Locked = true;

    procedure ApplyStockoutHistory(SeedTodayParam: Date)
    var
        Constants: Codeunit "PO Seed Constants";
        Item: Record Item;
        Rng: Codeunit "PO Seed Rng";
        ItemIndex: Integer;
    begin
        Rng.Init(Constants.RngSeedForCompany(CompanyName()) + 4);
        ItemIndex := 0;
        if Item.FindSet() then
            repeat
                ItemIndex += 1;
                if InStockoutCohort(Item."No.", ItemIndex) then
                    OverlayStockout(Item, SeedTodayParam, Rng);
            until Item.Next() = 0;
    end;

    local procedure InStockoutCohort(ItemNo: Code[20]; ItemIndex: Integer): Boolean
    begin
        if CopyStr(ItemNo, 1, 5) <> 'POS-I' then
            exit(false);
        exit(ItemIndex mod 13 = 0);
    end;

    local procedure OverlayStockout(Item: Record Item; SeedTodayParam: Date; var Rng: Codeunit "PO Seed Rng")
    var
        Constants: Codeunit "PO Seed Constants";
        StockoutDate: Date;
        RecoveryDate: Date;
        DraindownQty: Decimal;
        RestockQty: Decimal;
    begin
        StockoutDate := CalcDate(SixMonthsBackTok, SeedTodayParam);
        RecoveryDate := StockoutDate + Rng.NextIntInRange(7, 14);
        DraindownQty := 99500;
        RestockQty := 1000;
        PostNegativeAdjmt(Item."No.", StockoutDate, DraindownQty, Constants.LocationBlueCode());
        PostPositiveAdjmt(Item."No.", RecoveryDate, RestockQty, Constants.LocationBlueCode());
    end;

    local procedure PostNegativeAdjmt(ItemNo: Code[20]; PostingDate: Date; Quantity: Decimal; LocationCode: Code[10])
    var
        ItemJournalLine: Record "Item Journal Line";
    begin
        InitLine(ItemJournalLine, "Item Ledger Entry Type"::"Negative Adjmt.", ItemNo, PostingDate, LocationCode, Quantity, StockoutPrefixTok);
        PostJournalLine(ItemJournalLine);
    end;

    local procedure PostPositiveAdjmt(ItemNo: Code[20]; PostingDate: Date; Quantity: Decimal; LocationCode: Code[10])
    var
        ItemJournalLine: Record "Item Journal Line";
    begin
        InitLine(ItemJournalLine, "Item Ledger Entry Type"::"Positive Adjmt.", ItemNo, PostingDate, LocationCode, Quantity, RestockPrefixTok);
        PostJournalLine(ItemJournalLine);
    end;

    local procedure InitLine(var ItemJournalLine: Record "Item Journal Line"; EntryType: Enum "Item Ledger Entry Type"; ItemNo: Code[20]; PostingDate: Date; LocationCode: Code[10]; Quantity: Decimal; DocPrefix: Text[10])
    var
        Constants: Codeunit "PO Seed Constants";
        DocNo: Code[20];
    begin
        DocNo := CopyStr(StrSubstNo(DocNoFmtLbl, DocPrefix, Format(PostingDate, 0, DateAsYYYYMMDDFmtLbl)), 1, 20);
        ItemJournalLine.Init();
        ItemJournalLine."Entry Type" := EntryType;
        ItemJournalLine."Posting Date" := PostingDate;
        ItemJournalLine."Document Date" := PostingDate;
        ItemJournalLine."Document No." := DocNo;
        ItemJournalLine.Validate("Item No.", ItemNo);
        ItemJournalLine.Validate("Location Code", LocationCode);
        ItemJournalLine.Validate(Quantity, Quantity);
        ItemJournalLine."Source Code" := Constants.SourceCodeTok();
    end;

    local procedure PostJournalLine(var ItemJournalLine: Record "Item Journal Line")
    var
        ItemJnlPostLine: Codeunit "Item Jnl.-Post Line";
    begin
        ItemJnlPostLine.RunWithCheck(ItemJournalLine);
    end;
}
