namespace FBakkensen.BcLinuxSmoke.Seed;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Posting;

codeunit 50205 "PO Seed Demand History"
{
    Access = Public;
    Permissions = tabledata Item = R,
                  tabledata "Item Journal Line" = RIMD,
                  tabledata "Item Ledger Entry" = RIM,
                  tabledata "Value Entry" = RIM;

    var
        Rng: Codeunit "PO Seed Rng";
        SeedToday: Date;
        HistoryOffsetFmtLbl: Label '<-%1M>', Comment = '%1 = months back', Locked = true;
        DocNoSeedFmtLbl: Label 'SEED-%1', Comment = '%1 = posting date as YYYYMMDD', Locked = true;
        DateAsYYYYMMDDFmtLbl: Label '<Year4><Month,2><Day,2>', Locked = true;

    procedure SeedDemandHistory(SeedTodayParam: Date)
    var
        Constants: Codeunit "PO Seed Constants";
        Item: Record Item;
        ItemIndex: Integer;
    begin
        SeedToday := SeedTodayParam;
        Rng.Init(Constants.RngSeedForCompany(CompanyName()));
        ItemIndex := 0;
        if Item.FindSet() then
            repeat
                ItemIndex += 1;
                if IsSeedItem(Item."No.") then
                    SeedItemHistory(Item, ItemIndex);
            until Item.Next() = 0;
    end;

    local procedure IsSeedItem(ItemNo: Code[20]): Boolean
    begin
        exit(CopyStr(ItemNo, 1, 5) = 'POS-I');
    end;

    local procedure SeedItemHistory(Item: Record Item; ItemIndex: Integer)
    var
        Constants: Codeunit "PO Seed Constants";
        HistoryStart: Date;
        EventsPerYear: Integer;
        EventsTotal: Integer;
        EventIndex: Integer;
        EventDate: Date;
        Quantity: Decimal;
    begin
        HistoryStart := CalcDate(StrSubstNo(HistoryOffsetFmtLbl, Constants.HistoryMonths()), SeedToday);
        PostPositiveAdjmt(Item."No.", HistoryStart, 100000, Constants.LocationBlueCode());
        EventsPerYear := EventsPerYearForItem(ItemIndex);
        EventsTotal := (EventsPerYear * Constants.HistoryMonths()) div 12;
        for EventIndex := 1 to EventsTotal do begin
            EventDate := PickEventDate(HistoryStart, EventIndex, EventsTotal);
            Quantity := PickQuantityForItem(ItemIndex);
            PostSale(Item."No.", EventDate, Quantity, PickLocation(EventIndex));
        end;
    end;

    local procedure EventsPerYearForItem(ItemIndex: Integer): Integer
    begin
        case ItemIndex mod 4 of
            0:
                exit(80);
            1:
                exit(30);
            2:
                exit(10);
        end;
        exit(4);
    end;

    local procedure PickEventDate(HistoryStart: Date; EventIndex: Integer; EventsTotal: Integer): Date
    var
        DaysInWindow: Integer;
        DayOffset: Integer;
    begin
        DaysInWindow := SeedToday - HistoryStart;
        if DaysInWindow <= 0 then
            exit(HistoryStart);
        DayOffset := ((EventIndex - 1) * DaysInWindow) div EventsTotal;
        DayOffset := DayOffset + Rng.NextIntInRange(-2, 2);
        if DayOffset < 0 then
            DayOffset := 0;
        if DayOffset >= DaysInWindow then
            DayOffset := DaysInWindow - 1;
        exit(HistoryStart + DayOffset);
    end;

    local procedure PickQuantityForItem(ItemIndex: Integer): Decimal
    begin
        case ItemIndex mod 4 of
            0:
                exit(Rng.NextIntInRange(5, 20));
            1:
                exit(Rng.NextIntInRange(2, 10));
            2:
                exit(Rng.NextIntInRange(1, 5));
        end;
        exit(Rng.NextIntInRange(1, 3));
    end;

    local procedure PickLocation(EventIndex: Integer): Code[10]
    var
        Constants: Codeunit "PO Seed Constants";
    begin
        case EventIndex mod 3 of
            0:
                exit(Constants.LocationBlueCode());
            1:
                exit(Constants.LocationRedCode());
        end;
        exit(Constants.LocationGreenCode());
    end;

    local procedure PostPositiveAdjmt(ItemNo: Code[20]; PostingDate: Date; Quantity: Decimal; LocationCode: Code[10])
    var
        ItemJournalLine: Record "Item Journal Line";
    begin
        InitItemJournalLine(ItemJournalLine, "Item Ledger Entry Type"::"Positive Adjmt.", ItemNo, PostingDate, LocationCode, Quantity);
        PostJournalLine(ItemJournalLine);
    end;

    local procedure PostSale(ItemNo: Code[20]; PostingDate: Date; Quantity: Decimal; LocationCode: Code[10])
    var
        ItemJournalLine: Record "Item Journal Line";
    begin
        InitItemJournalLine(ItemJournalLine, "Item Ledger Entry Type"::Sale, ItemNo, PostingDate, LocationCode, Quantity);
        PostJournalLine(ItemJournalLine);
    end;

    local procedure InitItemJournalLine(var ItemJournalLine: Record "Item Journal Line"; EntryType: Enum "Item Ledger Entry Type"; ItemNo: Code[20]; PostingDate: Date; LocationCode: Code[10]; Quantity: Decimal)
    var
        Constants: Codeunit "PO Seed Constants";
        DocNo: Code[20];
    begin
        DocNo := CopyStr(StrSubstNo(DocNoSeedFmtLbl, Format(PostingDate, 0, DateAsYYYYMMDDFmtLbl)), 1, 20);
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
