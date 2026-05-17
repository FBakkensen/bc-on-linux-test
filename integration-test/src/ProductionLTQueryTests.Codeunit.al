namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Foundation.Enums;
using Microsoft.Inventory.Ledger;
using Microsoft.Manufacturing.Document;
using System.TestLibraries.Utilities;

codeunit 50165 "Production LT Query Tests"
{
    Subtype = Test;
    Access = Internal;
    Permissions = tabledata "Production Order" = I,
                  tabledata "Item Ledger Entry" = RI;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure JoinsHeaderToILEAndExposesEntryKindAndDates()
    var
        ProductionLT: Query "Production LT";
        ProdOrderNo: Code[20];
        ItemNo: Code[20];
        ConsumptionItemNo: Code[20];
        Rows: Integer;
        SawConsumption: Boolean;
        SawOutput: Boolean;
    begin
        // GIVEN a Finished prod order with one Consumption ILE (raw item)
        // and one Output ILE (finished item) — the canonical shape the
        // Python parser collapses into a single (LT, source=ile) sample.
        ProdOrderNo := UniqueProdOrderNo();
        ItemNo := UniqueItemNo();
        ConsumptionItemNo := UniqueItemNo();
        InsertProdOrderHeader(
            ProdOrderNo, "Production Order Status"::Finished,
            20260301D, 20260315D, 20260314D);
        InsertProdOrderILE(
            ProdOrderNo, ConsumptionItemNo, '', 'BLUE',
            "Item Ledger Entry Type"::Consumption, 20260305D, -50);
        InsertProdOrderILE(
            ProdOrderNo, ItemNo, '', 'BLUE',
            "Item Ledger Entry Type"::Output, 20260314D, 10);

        // WHEN we read the query filtered to our test prod order
        ProductionLT.SetFilter(prodOrderNo, ProdOrderNo);
        ProductionLT.Open();
        while ProductionLT.Read() do begin
            Rows += 1;
            // THEN both header dates and ILE columns flow through unchanged
            Assert.AreEqual(ProdOrderNo, ProductionLT.prodOrderNo, 'prodOrderNo from prod order header.');
            Assert.AreEqual(20260301D, ProductionLT.prodOrderStartingDate, 'prodOrderStartingDate joined from prod order header.');
            Assert.AreEqual(20260315D, ProductionLT.prodOrderFinishingDate, 'prodOrderFinishingDate is BC Finished Date.');
            Assert.AreEqual(20260314D, ProductionLT.prodOrderEndingDate, 'prodOrderEndingDate is BC Ending Date.');
            Assert.AreEqual('BLUE', ProductionLT.locationCode, 'locationCode from ILE.');
            if ProductionLT.entryKind = "Item Ledger Entry Type"::Consumption then begin
                SawConsumption := true;
                Assert.AreEqual(20260305D, ProductionLT.postingDate, 'Consumption posting date passes through.');
            end;
            if ProductionLT.entryKind = "Item Ledger Entry Type"::Output then begin
                SawOutput := true;
                Assert.AreEqual(20260314D, ProductionLT.postingDate, 'Output posting date passes through.');
            end;
        end;
        ProductionLT.Close();

        Assert.AreEqual(2, Rows, 'Exactly one row per ILE entry — both Output and Consumption are emitted.');
        Assert.IsTrue(SawConsumption, 'Consumption ILE must be present in the result set.');
        Assert.IsTrue(SawOutput, 'Output ILE must be present in the result set.');
    end;

    [Test]
    procedure ExcludesNonFinishedProdOrders()
    var
        ProductionLT: Query "Production LT";
        ProdOrderNo: Code[20];
        ItemNo: Code[20];
        Rows: Integer;
    begin
        // ADR 0006: only Finished prod orders carry historical truth —
        // cancelled / scrapped (i.e. anything but Finished) must be
        // excluded server-side.
        ProdOrderNo := UniqueProdOrderNo();
        ItemNo := UniqueItemNo();
        InsertProdOrderHeader(
            ProdOrderNo, "Production Order Status"::Released,
            20260301D, 20260315D, 0D);
        InsertProdOrderILE(
            ProdOrderNo, ItemNo, '', 'BLUE',
            "Item Ledger Entry Type"::Output, 20260314D, 10);

        ProductionLT.SetFilter(prodOrderNo, ProdOrderNo);
        ProductionLT.Open();
        while ProductionLT.Read() do
            Rows += 1;
        ProductionLT.Close();

        Assert.AreEqual(0, Rows, 'Released prod orders must be excluded — Status filter is server-side.');
    end;

    [Test]
    procedure ExcludesIleFromOtherOrderTypesSharingAnOrderNo()
    var
        ProductionLT: Query "Production LT";
        ProdOrderNo: Code[20];
        ItemNo: Code[20];
        Rows: Integer;
    begin
        // GIVEN a Finished prod order with one production ILE and one
        // Transfer ILE row carrying the same Order No. Without an Order
        // Type filter, the Transfer ILE would leak in — the filter
        // `"Order Type" = const(Production)` is what keeps the result
        // scoped to actual production activity.
        ProdOrderNo := UniqueProdOrderNo();
        ItemNo := UniqueItemNo();
        InsertProdOrderHeader(
            ProdOrderNo, "Production Order Status"::Finished,
            20260301D, 20260315D, 20260314D);
        InsertProdOrderILE(
            ProdOrderNo, ItemNo, '', 'BLUE',
            "Item Ledger Entry Type"::Output, 20260314D, 10);
        InsertILEWithOrderType(
            ProdOrderNo, ItemNo, '', 'BLUE',
            "Item Ledger Entry Type"::Transfer, "Inventory Order Type"::Transfer,
            20260314D, -3);

        ProductionLT.SetFilter(prodOrderNo, ProdOrderNo);
        ProductionLT.Open();
        while ProductionLT.Read() do
            Rows += 1;
        ProductionLT.Close();

        Assert.AreEqual(1, Rows, 'Transfer-typed ILE sharing an Order No. must not leak into Production LT.');
    end;

    local procedure InsertProdOrderHeader(No: Code[20]; Status: Enum "Production Order Status"; StartingDate: Date; FinishedDate: Date; EndingDate: Date)
    var
        ProdOrder: Record "Production Order";
    begin
        ProdOrder.Init();
        ProdOrder.Status := Status;
        ProdOrder."No." := No;
        ProdOrder."Starting Date" := StartingDate;
        ProdOrder."Finished Date" := FinishedDate;
        ProdOrder."Ending Date" := EndingDate;
        ProdOrder.Insert(false);
    end;

    local procedure InsertProdOrderILE(OrderNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; EntryType: Enum "Item Ledger Entry Type"; PostingDate: Date; Qty: Decimal)
    begin
        InsertILEWithOrderType(
            OrderNo, ItemNo, VariantCode, LocationCode, EntryType,
            "Inventory Order Type"::Production, PostingDate, Qty);
    end;

    local procedure InsertILEWithOrderType(OrderNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; EntryType: Enum "Item Ledger Entry Type"; OrderType: Enum "Inventory Order Type"; PostingDate: Date; Qty: Decimal)
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
        ILE."Order Type" := OrderType;
        ILE."Order No." := OrderNo;
        ILE."Posting Date" := PostingDate;
        ILE.Quantity := Qty;
        ILE."Remaining Quantity" := Qty;
        ILE.Open := Qty > 0;
        ILE.Positive := Qty > 0;
        ILE.Insert(false);
    end;

    local procedure UniqueProdOrderNo(): Code[20]
    begin
        exit(CopyStr('PO' + UniqueSuffix(), 1, 20));
    end;

    local procedure UniqueItemNo(): Code[20]
    begin
        exit(CopyStr('PRD' + UniqueSuffix(), 1, 20));
    end;

    local procedure UniqueSuffix(): Text
    begin
        exit(Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(99999)));
    end;
}
