namespace FBakkensen.BcLinuxSmoke.Seed;

using Microsoft.Assembly.Document;
using Microsoft.Assembly.History;
using Microsoft.Assembly.Posting;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Posting;
using Microsoft.Inventory.Transfer;
using Microsoft.Manufacturing.Document;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.History;
using Microsoft.Purchases.Posting;
using Microsoft.Purchases.Vendor;

codeunit 50206 "PO Seed LT Samples"
{
    // Creates posted Purchase Receipts so the Purchase Receipt LT Query
    // (app/src/seams/PurchaseReceiptLT.Query.al) has rows to return. That
    // Query reads from Purch. Rcpt. Header / Purch. Rcpt. Line / Purchase
    // Header — populated only by posting a Purchase Order with "Receive".
    //
    // For each seed item:
    //   1. Create a Purchase Header (PO) with Buy-from Vendor, Order Date,
    //      Posting Date (= ReceiptDate), Expected Receipt Date, Location.
    //      OrderDate varies across samples so the Order → Receipt
    //      elapsed-days distribution has spread.
    //   2. Create a Purchase Line for the item with Quantity to receive.
    //   3. Call Purch.-Post with Receive=true, Invoice=false.
    //
    // Result: a Posted Purch. Rcpt. Header / Lines row per sample,
    // discoverable by the LT Query. Source PO survives so the
    // LeftOuterJoin to Expected Receipt Date works.
    Access = Public;
    Permissions = tabledata Item = R,
                  tabledata Vendor = R,
                  tabledata "Purchase Header" = RIMD,
                  tabledata "Purchase Line" = RIMD,
                  tabledata "Purch. Rcpt. Header" = R,
                  tabledata "Assembly Header" = RIMD,
                  tabledata "Assembly Line" = RIMD,
                  tabledata "Posted Assembly Header" = RI,
                  tabledata "Transfer Header" = RIMD,
                  tabledata "Transfer Line" = RIMD,
                  tabledata "Production Order" = RIMD,
                  tabledata "Prod. Order Line" = RIMD,
                  tabledata "Prod. Order Routing Line" = RIMD,
                  tabledata "Prod. Order Component" = RIMD,
                  tabledata "Prod. Order Capacity Need" = RIMD,
                  tabledata "Item Journal Line" = RIMD,
                  tabledata "Item Ledger Entry" = RIM;

    var
        SeedPurchaseNoFmtLbl: Label 'PO-SEED-%1', Comment = '%1 = sequential index padded to 5 digits', Locked = true;
        SeedReceiptNoFmtLbl: Label 'PR-SEED-%1', Comment = '%1 = sequential index padded to 5 digits', Locked = true;
        SeedAssemblyNoFmtLbl: Label 'AO-SEED-%1', Comment = '%1 = sequential index padded to 5 digits', Locked = true;
        SeedAssemblyPostNoFmtLbl: Label 'PA-SEED-%1', Comment = '%1 = sequential index padded to 5 digits', Locked = true;
        SeedTransferNoFmtLbl: Label 'TO-SEED-%1', Comment = '%1 = sequential index padded to 5 digits', Locked = true;
        SeedTransferShipNoFmtLbl: Label 'TS-SEED-%1', Comment = '%1 = sequential index padded to 5 digits', Locked = true;
        SeedTransferRcptNoFmtLbl: Label 'TR-SEED-%1', Comment = '%1 = sequential index padded to 5 digits', Locked = true;
        SeedProdOrderNoFmtLbl: Label 'PRD-SEED-%1', Comment = '%1 = sequential index padded to 5 digits', Locked = true;
        SeedPurchaseNoIdxFmtLbl: Label '<Integer,5><Filler Character,0>', Locked = true;
        SeedVendorFilterTok: Label 'POS-VEND-*', Locked = true;
        HistoryOffsetFmtLbl: Label '<-%1M>', Comment = '%1 = months back', Locked = true;

    procedure SeedLTSamples(SeedTodayParam: Date)
    var
        Constants: Codeunit "PO Seed Constants";
        Item: Record Item;
        Rng: Codeunit "PO Seed Rng";
        ItemIndex: Integer;
        PurchaseSequence: Integer;
        AssemblySequence: Integer;
        TransferSequence: Integer;
        ProductionSequence: Integer;
    begin
        Rng.Init(Constants.RngSeedForCompany(CompanyName()) + 1);
        ItemIndex := 0;
        PurchaseSequence := 0;
        AssemblySequence := 0;
        TransferSequence := 0;
        ProductionSequence := 0;
        if Item.FindSet() then
            repeat
                ItemIndex += 1;
                if IsSeedItem(Item."No.") then begin
                    SeedItemLTSamples(Item, ItemIndex, SeedTodayParam, Rng, PurchaseSequence);
                    SeedItemAssemblyLT(Item, ItemIndex, SeedTodayParam, Rng, AssemblySequence);
                    SeedItemTransferLT(Item, ItemIndex, SeedTodayParam, Rng, TransferSequence);
                    SeedItemProductionLT(Item, ItemIndex, SeedTodayParam, Rng, ProductionSequence);
                end;
            until Item.Next() = 0;
    end;

    local procedure IsSeedItem(ItemNo: Code[20]): Boolean
    begin
        exit(CopyStr(ItemNo, 1, 5) = 'POS-I');
    end;

    local procedure SeedItemLTSamples(Item: Record Item; ItemIndex: Integer; SeedTodayParam: Date; var Rng: Codeunit "PO Seed Rng"; var SequenceCounter: Integer)
    var
        Constants: Codeunit "PO Seed Constants";
        VendorNo: Code[20];
        HistoryStart: Date;
        SamplesNeeded: Integer;
        SampleIdx: Integer;
        OrderDate: Date;
        ReceiptDate: Date;
        LeadTimeDays: Integer;
        Quantity: Decimal;
    begin
        VendorNo := PickVendor();
        if VendorNo = '' then
            exit;
        HistoryStart := CalcDate(StrSubstNo(HistoryOffsetFmtLbl, Constants.HistoryMonths()), SeedTodayParam);
        SamplesNeeded := SamplesForItem(ItemIndex);
        for SampleIdx := 1 to SamplesNeeded do begin
            ReceiptDate := PickReceiptDate(HistoryStart, SeedTodayParam, SampleIdx, SamplesNeeded, Rng);
            LeadTimeDays := Rng.NextIntInRange(5, 30);
            OrderDate := ReceiptDate - LeadTimeDays;
            if OrderDate < HistoryStart then
                OrderDate := HistoryStart;
            Quantity := Rng.NextIntInRange(20, 80);
            SequenceCounter += 1;
            CreateAndPostReceipt(SequenceCounter, Item."No.", VendorNo, OrderDate, ReceiptDate, Quantity, Constants.LocationBlueCode());
        end;
    end;

    local procedure SamplesForItem(ItemIndex: Integer): Integer
    begin
        // Class A: monthly; B: bi-monthly; C: quarterly; data-poor: under
        // threshold. Smaller per-class than the previous Item-Journal
        // approach because each posted receipt goes through full Purch.-Post.
        case ItemIndex mod 4 of
            0:
                exit(18);
            1:
                exit(9);
            2:
                exit(6);
        end;
        exit(3);
    end;

    local procedure PickVendor(): Code[20]
    var
        Vendor: Record Vendor;
    begin
        Vendor.SetLoadFields("No.");
        Vendor.SetFilter("No.", SeedVendorFilterTok);
        if Vendor.FindFirst() then
            exit(Vendor."No.");
        exit('');
    end;

    local procedure PickReceiptDate(HistoryStart: Date; SeedTodayParam: Date; SampleIdx: Integer; SamplesTotal: Integer; var Rng: Codeunit "PO Seed Rng"): Date
    var
        DaysInWindow: Integer;
        DayOffset: Integer;
    begin
        DaysInWindow := SeedTodayParam - HistoryStart;
        if DaysInWindow <= 0 then
            exit(HistoryStart);
        DayOffset := ((SampleIdx - 1) * DaysInWindow) div SamplesTotal;
        DayOffset := DayOffset + Rng.NextIntInRange(-3, 3);
        if DayOffset < 0 then
            DayOffset := 0;
        if DayOffset >= DaysInWindow then
            DayOffset := DaysInWindow - 1;
        exit(HistoryStart + DayOffset);
    end;

    local procedure PostedReceiptExists(SequenceCounter: Integer): Boolean
    var
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        ReceiptNo: Code[20];
    begin
        ReceiptNo := CopyStr(StrSubstNo(SeedReceiptNoFmtLbl, Format(SequenceCounter, 5, SeedPurchaseNoIdxFmtLbl)), 1, 20);
        PurchRcptHeader.SetLoadFields("No.");
        exit(PurchRcptHeader.Get(ReceiptNo));
    end;

    local procedure CreateAndPostReceipt(SequenceCounter: Integer; ItemNo: Code[20]; VendorNo: Code[20]; OrderDate: Date; ReceiptDate: Date; Quantity: Decimal; LocationCode: Code[10])
    var
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        PurchPost: Codeunit "Purch.-Post";
        DocNo: Code[20];
    begin
        DocNo := CopyStr(StrSubstNo(SeedPurchaseNoFmtLbl, Format(SequenceCounter, 5, SeedPurchaseNoIdxFmtLbl)), 1, 20);
        // Idempotency: skip if this PO already exists (re-install left an
        // orphan from a prior failure, or a successful prior run already
        // posted it).
        if PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, DocNo) then
            exit;
        // Also skip if the receipt was already posted previously.
        if PostedReceiptExists(SequenceCounter) then
            exit;

        PurchaseHeader.Init();
        PurchaseHeader."Document Type" := PurchaseHeader."Document Type"::Order;
        PurchaseHeader."No." := DocNo;
        PurchaseHeader.Insert(false);
        PurchaseHeader.Validate("Buy-from Vendor No.", VendorNo);
        PurchaseHeader.Validate("Posting Date", ReceiptDate);
        PurchaseHeader."Order Date" := OrderDate;
        PurchaseHeader."Document Date" := OrderDate;
        PurchaseHeader.Validate("Expected Receipt Date", ReceiptDate);
        PurchaseHeader.Validate("Location Code", LocationCode);
        // Direct-assign Receiving No. to bypass the Purchases & Payables
        // Setup's "Receiving Nos." No. Series requirement — Purch.-Post
        // accepts a pre-populated number and skips the series allocation.
        PurchaseHeader."Receiving No." := CopyStr(StrSubstNo(SeedReceiptNoFmtLbl, Format(SequenceCounter, 5, SeedPurchaseNoIdxFmtLbl)), 1, 20);
        PurchaseHeader.Modify(false);

        PurchaseLine.Init();
        PurchaseLine."Document Type" := PurchaseHeader."Document Type";
        PurchaseLine."Document No." := PurchaseHeader."No.";
        PurchaseLine."Line No." := 10000;
        PurchaseLine.Validate(Type, PurchaseLine.Type::Item);
        PurchaseLine.Validate("No.", ItemNo);
        PurchaseLine.Validate("Location Code", LocationCode);
        PurchaseLine.Validate(Quantity, Quantity);
        PurchaseLine.Validate("Direct Unit Cost", 1);
        PurchaseLine."Expected Receipt Date" := ReceiptDate;
        PurchaseLine.Insert(false);

        PurchaseHeader.Receive := true;
        PurchaseHeader.Invoice := false;
        PurchPost.Run(PurchaseHeader);
    end;

    // ─── Assembly LT ─────────────────────────────────────────────────────────

    local procedure SeedItemAssemblyLT(Item: Record Item; ItemIndex: Integer; SeedTodayParam: Date; var Rng: Codeunit "PO Seed Rng"; var SequenceCounter: Integer)
    var
        Constants: Codeunit "PO Seed Constants";
        HistoryStart: Date;
        Samples: Integer;
        SampleIdx: Integer;
        StartDate: Date;
        PostingDate: Date;
        LeadTimeDays: Integer;
        Quantity: Decimal;
    begin
        // Only items configured as Assembly replenishment make sense here.
        if Item."Replenishment System" <> Item."Replenishment System"::Assembly then
            exit;
        HistoryStart := CalcDate(StrSubstNo(HistoryOffsetFmtLbl, Constants.HistoryMonths()), SeedTodayParam);
        Samples := AssemblySamplesForItem(ItemIndex);
        for SampleIdx := 1 to Samples do begin
            PostingDate := PickReceiptDate(HistoryStart, SeedTodayParam, SampleIdx, Samples, Rng);
            LeadTimeDays := Rng.NextIntInRange(2, 10);
            StartDate := PostingDate - LeadTimeDays;
            if StartDate < HistoryStart then
                StartDate := HistoryStart;
            Quantity := Rng.NextIntInRange(5, 30);
            SequenceCounter += 1;
            CreateAndPostAssembly(SequenceCounter, Item."No.", StartDate, PostingDate, Quantity, Constants.LocationBlueCode());
        end;
    end;

    local procedure AssemblySamplesForItem(ItemIndex: Integer): Integer
    begin
        case ItemIndex mod 4 of
            0:
                exit(12);
            1:
                exit(6);
            2:
                exit(4);
        end;
        exit(2);
    end;

    local procedure PostedAssemblyExists(SequenceCounter: Integer): Boolean
    var
        PostedAsmHeader: Record "Posted Assembly Header";
        PostNo: Code[20];
    begin
        PostNo := CopyStr(StrSubstNo(SeedAssemblyPostNoFmtLbl, Format(SequenceCounter, 5, SeedPurchaseNoIdxFmtLbl)), 1, 20);
        PostedAsmHeader.SetLoadFields("No.");
        exit(PostedAsmHeader.Get(PostNo));
    end;

    local procedure CreateAndPostAssembly(SequenceCounter: Integer; ItemNo: Code[20]; StartDate: Date; PostingDate: Date; Quantity: Decimal; LocationCode: Code[10])
    var
        AssemblyHeader: Record "Assembly Header";
        AssemblyPost: Codeunit "Assembly-Post";
        DocNo: Code[20];
        PostNo: Code[20];
    begin
        DocNo := CopyStr(StrSubstNo(SeedAssemblyNoFmtLbl, Format(SequenceCounter, 5, SeedPurchaseNoIdxFmtLbl)), 1, 20);
        PostNo := CopyStr(StrSubstNo(SeedAssemblyPostNoFmtLbl, Format(SequenceCounter, 5, SeedPurchaseNoIdxFmtLbl)), 1, 20);
        if AssemblyHeader.Get(AssemblyHeader."Document Type"::Order, DocNo) then
            exit;
        if PostedAssemblyExists(SequenceCounter) then
            exit;

        AssemblyHeader.Init();
        AssemblyHeader."Document Type" := AssemblyHeader."Document Type"::Order;
        AssemblyHeader."No." := DocNo;
        // Dates BEFORE Validate("Item No.") — Assembly Header's
        // OnValidate("Item No.") cascades into Record900.ValidateDates
        // which throws if Due Date is 0D at validation time.
        AssemblyHeader."Posting Date" := PostingDate;
        AssemblyHeader."Starting Date" := StartDate;
        AssemblyHeader."Ending Date" := PostingDate;
        AssemblyHeader."Due Date" := PostingDate + 1;
        AssemblyHeader.Insert(false);
        AssemblyHeader.Validate("Item No.", ItemNo);
        AssemblyHeader.Validate("Location Code", LocationCode);
        AssemblyHeader.Validate(Quantity, Quantity);
        AssemblyHeader.Validate("Quantity to Assemble", Quantity);
        // Pre-assign Posting No. to skip Assembly Setup's No. Series requirement.
        AssemblyHeader."Posting No." := PostNo;
        AssemblyHeader.Modify(false);

        // Assembly-Post requires at least one Assembly Line with Type=Item
        // and Quantity to Consume > 0 — otherwise "Nothing to post". We use
        // POS-I0001 as a generic component; it always has stock at BLUE
        // from the demand-history bootstrap's 100k positive adjustment.
        EnsureAssemblyComponentLine(AssemblyHeader, 'POS-I0001');

        AssemblyPost.Run(AssemblyHeader);
    end;

    local procedure EnsureAssemblyComponentLine(AssemblyHeader: Record "Assembly Header"; ComponentItemNo: Code[20])
    var
        AssemblyLine: Record "Assembly Line";
    begin
        // Match LibraryAssembly.CreateAssemblyLine — Insert(true) before
        // Validate(Type/No.), set "Quantity per" before Validate(Quantity)
        // so the OnValidate hook computes Qty to Consume correctly.
        AssemblyLine.Init();
        AssemblyLine."Document Type" := AssemblyHeader."Document Type";
        AssemblyLine."Document No." := AssemblyHeader."No.";
        AssemblyLine.Validate("Line No.", 10000);
        AssemblyLine.Insert(true);
        AssemblyLine.Validate(Type, AssemblyLine.Type::Item);
        AssemblyLine.Validate("No.", ComponentItemNo);
        AssemblyLine."Quantity per" := 1;
        AssemblyLine.Validate(Quantity, 1);
        AssemblyLine.Validate("Unit of Measure Code", 'PCS');
        AssemblyLine.Modify(true);
    end;

    // ─── Transfer LT ─────────────────────────────────────────────────────────

    local procedure SeedItemTransferLT(Item: Record Item; ItemIndex: Integer; SeedTodayParam: Date; var Rng: Codeunit "PO Seed Rng"; var SequenceCounter: Integer)
    var
        Constants: Codeunit "PO Seed Constants";
        HistoryStart: Date;
        Samples: Integer;
        SampleIdx: Integer;
        ShipDate: Date;
        ReceiptDate: Date;
        TransitDays: Integer;
        Quantity: Decimal;
    begin
        if not IsSeedItem(Item."No.") then
            exit;
        HistoryStart := CalcDate(StrSubstNo(HistoryOffsetFmtLbl, Constants.HistoryMonths()), SeedTodayParam);
        Samples := TransferSamplesForItem(ItemIndex);
        for SampleIdx := 1 to Samples do begin
            ShipDate := PickReceiptDate(HistoryStart, SeedTodayParam, SampleIdx, Samples, Rng);
            TransitDays := Rng.NextIntInRange(1, 7);
            ReceiptDate := ShipDate + TransitDays;
            if ReceiptDate > SeedTodayParam then
                ReceiptDate := SeedTodayParam;
            Quantity := Rng.NextIntInRange(5, 25);
            SequenceCounter += 1;
            CreateAndPostTransfer(SequenceCounter, Item."No.", ShipDate, ReceiptDate, Quantity, Constants.LocationBlueCode(), Constants.LocationRedCode(), Constants.LocationInTransitCode());
        end;
    end;

    local procedure TransferSamplesForItem(ItemIndex: Integer): Integer
    begin
        // Less per item than purchase / production; only the items that we
        // expect to actually move between locations.
        case ItemIndex mod 4 of
            0:
                exit(8);
            1:
                exit(4);
        end;
        exit(2);
    end;

    local procedure CreateAndPostTransfer(SequenceCounter: Integer; ItemNo: Code[20]; ShipDate: Date; ReceiptDate: Date; Quantity: Decimal; FromLocation: Code[10]; ToLocation: Code[10]; InTransitLocation: Code[10])
    var
        TransferHeader: Record "Transfer Header";
        TransferLine: Record "Transfer Line";
        TransferShipPost: Codeunit "TransferOrder-Post Shipment";
        TransferRcptPost: Codeunit "TransferOrder-Post Receipt";
        DocNo: Code[20];
        ShipNo: Code[20];
        RcptNo: Code[20];
    begin
        DocNo := CopyStr(StrSubstNo(SeedTransferNoFmtLbl, Format(SequenceCounter, 5, SeedPurchaseNoIdxFmtLbl)), 1, 20);
        ShipNo := CopyStr(StrSubstNo(SeedTransferShipNoFmtLbl, Format(SequenceCounter, 5, SeedPurchaseNoIdxFmtLbl)), 1, 20);
        RcptNo := CopyStr(StrSubstNo(SeedTransferRcptNoFmtLbl, Format(SequenceCounter, 5, SeedPurchaseNoIdxFmtLbl)), 1, 20);
        if TransferHeader.Get(DocNo) then
            exit;

        // Pattern mirrors BaseApp's LibraryInventory.CreateTransferHeader /
        // .CreateTransferLine / .PostTransferHeader — but with Insert(false)
        // + explicit Document No. to bypass Inventory Setup's "Transfer Order
        // Nos." No. Series requirement.
        TransferHeader.Init();
        TransferHeader."No." := DocNo;
        TransferHeader.Insert(false);
        TransferHeader.Validate("Transfer-from Code", FromLocation);
        TransferHeader.Validate("Transfer-to Code", ToLocation);
        TransferHeader.Validate("In-Transit Code", InTransitLocation);
        TransferHeader.Validate("Posting Date", ShipDate);
        TransferHeader.Validate("Shipment Date", ShipDate);
        TransferHeader.Validate("Receipt Date", ReceiptDate);
        // Pre-assign posting No. Series numbers so Inventory Setup's
        // Shipment / Receipt No. Series aren't required.
        TransferHeader."Last Shipment No." := ShipNo;
        TransferHeader."Last Receipt No." := RcptNo;
        TransferHeader.Modify(false);

        TransferLine.Init();
        TransferLine.Validate("Document No.", TransferHeader."No.");
        TransferLine."Line No." := 10000;
        TransferLine.Insert(false);
        TransferLine.Validate("Item No.", ItemNo);
        TransferLine.Validate(Quantity, Quantity);
        TransferLine."Shipment Date" := ShipDate;
        TransferLine."Receipt Date" := ReceiptDate;
        TransferLine.Modify(false);

        // Two-step post: Shipment (From → InTransit) then Receipt (InTransit → To).
        // TransferOrder-Post Transfer is for direct (one-step, no in-transit)
        // transfers — wrong codeunit for our flow.
        TransferShipPost.SetHideValidationDialog(true);
        TransferShipPost.Run(TransferHeader);
        TransferRcptPost.SetHideValidationDialog(true);
        TransferRcptPost.Run(TransferHeader);
    end;

    // ─── Production LT ───────────────────────────────────────────────────────

    local procedure SeedItemProductionLT(Item: Record Item; ItemIndex: Integer; SeedTodayParam: Date; var Rng: Codeunit "PO Seed Rng"; var SequenceCounter: Integer)
    var
        Constants: Codeunit "PO Seed Constants";
        HistoryStart: Date;
        Samples: Integer;
        SampleIdx: Integer;
        StartingDate: Date;
        FinishedDate: Date;
        LeadTimeDays: Integer;
        Quantity: Decimal;
    begin
        if Item."Replenishment System" <> Item."Replenishment System"::"Prod. Order" then
            exit;
        HistoryStart := CalcDate(StrSubstNo(HistoryOffsetFmtLbl, Constants.HistoryMonths()), SeedTodayParam);
        Samples := ProductionSamplesForItem(ItemIndex);
        for SampleIdx := 1 to Samples do begin
            FinishedDate := PickReceiptDate(HistoryStart, SeedTodayParam, SampleIdx, Samples, Rng);
            LeadTimeDays := Rng.NextIntInRange(3, 14);
            StartingDate := FinishedDate - LeadTimeDays;
            if StartingDate < HistoryStart then
                StartingDate := HistoryStart;
            Quantity := Rng.NextIntInRange(10, 50);
            SequenceCounter += 1;
            CreateAndFinishProdOrder(SequenceCounter, Item."No.", StartingDate, FinishedDate, Quantity, Constants.LocationBlueCode());
        end;
    end;

    local procedure ProductionSamplesForItem(ItemIndex: Integer): Integer
    begin
        case ItemIndex mod 4 of
            0:
                exit(10);
            1:
                exit(5);
            2:
                exit(3);
        end;
        exit(2);
    end;

    local procedure CreateAndFinishProdOrder(SequenceCounter: Integer; ItemNo: Code[20]; StartingDate: Date; FinishedDate: Date; Quantity: Decimal; LocationCode: Code[10])
    var
        ProductionOrder: Record "Production Order";
        ProdOrderStatusMgt: Codeunit "Prod. Order Status Management";
        DocNo: Code[20];
    begin
        DocNo := CopyStr(StrSubstNo(SeedProdOrderNoFmtLbl, Format(SequenceCounter, 5, SeedPurchaseNoIdxFmtLbl)), 1, 20);
        if ProductionOrder.Get(ProductionOrder.Status::Finished, DocNo) then
            exit;
        if ProductionOrder.Get(ProductionOrder.Status::Released, DocNo) then
            exit;

        // Manual Production Order assembly — skip the Refresh report
        // (which fails inside the OData transaction and can't compute
        // dates/times without a Routing). We Insert the Released header,
        // Insert one Prod. Order Line manually with all dates + times +
        // date-times pre-set, post Output via Item Journal, and call
        // ChangeProdOrderStatus to promote to Finished. The Production LT
        // Query reads (Production Order.Status=Finished JOIN ILE on
        // Order Type=Production); both records appear with correct shape.
        ProductionOrder.Init();
        ProductionOrder.Validate(Status, ProductionOrder.Status::Released);
        ProductionOrder."No." := DocNo;
        ProductionOrder."Source Type" := ProductionOrder."Source Type"::Item;
        ProductionOrder."Source No." := ItemNo;
        ProductionOrder.Description := ItemNo;
        ProductionOrder.Quantity := Quantity;
        ProductionOrder."Location Code" := LocationCode;
        ProductionOrder."Starting Date" := StartingDate;
        ProductionOrder."Starting Time" := 080000T;
        ProductionOrder."Starting Date-Time" := CreateDateTime(StartingDate, 080000T);
        ProductionOrder."Ending Date" := FinishedDate;
        ProductionOrder."Ending Time" := 170000T;
        ProductionOrder."Ending Date-Time" := CreateDateTime(FinishedDate, 170000T);
        ProductionOrder."Due Date" := FinishedDate;
        ProductionOrder.Insert(false);

        InsertProdOrderLine(ProductionOrder, ItemNo, Quantity, LocationCode, StartingDate, FinishedDate);
        Commit();  // persist header+line before posting output (Item Jnl uses fresh read)

        PostProductionOutput(ProductionOrder."No.", ItemNo, Quantity, LocationCode, FinishedDate);
        ProdOrderStatusMgt.ChangeProdOrderStatus(ProductionOrder, ProductionOrder.Status::Finished, FinishedDate, false);
    end;

    local procedure InsertProdOrderLine(ProductionOrder: Record "Production Order"; ItemNo: Code[20]; Quantity: Decimal; LocationCode: Code[10]; StartingDate: Date; FinishedDate: Date)
    var
        ProdOrderLine: Record "Prod. Order Line";
    begin
        ProdOrderLine.Init();
        ProdOrderLine.Status := ProductionOrder.Status;
        ProdOrderLine."Prod. Order No." := ProductionOrder."No.";
        ProdOrderLine."Line No." := 10000;
        ProdOrderLine."Item No." := ItemNo;
        ProdOrderLine.Description := ItemNo;
        ProdOrderLine."Location Code" := LocationCode;
        ProdOrderLine."Quantity" := Quantity;
        ProdOrderLine."Remaining Quantity" := Quantity;
        ProdOrderLine."Unit of Measure Code" := 'PCS';
        ProdOrderLine."Qty. per Unit of Measure" := 1;
        ProdOrderLine."Starting Date" := StartingDate;
        ProdOrderLine."Starting Time" := 080000T;
        ProdOrderLine."Starting Date-Time" := CreateDateTime(StartingDate, 080000T);
        ProdOrderLine."Ending Date" := FinishedDate;
        ProdOrderLine."Ending Time" := 170000T;
        ProdOrderLine."Ending Date-Time" := CreateDateTime(FinishedDate, 170000T);
        ProdOrderLine."Due Date" := FinishedDate;
        ProdOrderLine.Insert(false);
    end;



    local procedure PostProductionOutput(ProdOrderNo: Code[20]; ItemNo: Code[20]; Quantity: Decimal; LocationCode: Code[10]; PostingDate: Date)
    var
        ItemJournalLine: Record "Item Journal Line";
        ItemJnlPostLine: Codeunit "Item Jnl.-Post Line";
        DocNoFmtLbl: Label 'PO-OUT-%1', Comment = '%1 = prod order no', Locked = true;
    begin
        ItemJournalLine.Init();
        ItemJournalLine."Entry Type" := "Item Ledger Entry Type"::Output;
        ItemJournalLine."Order Type" := ItemJournalLine."Order Type"::Production;
        ItemJournalLine."Order No." := ProdOrderNo;
        ItemJournalLine."Posting Date" := PostingDate;
        ItemJournalLine."Document Date" := PostingDate;
        ItemJournalLine."Document No." := CopyStr(StrSubstNo(DocNoFmtLbl, ProdOrderNo), 1, 20);
        ItemJournalLine.Validate("Item No.", ItemNo);
        ItemJournalLine.Validate("Location Code", LocationCode);
        ItemJournalLine.Validate("Output Quantity", Quantity);
        ItemJnlPostLine.RunWithCheck(ItemJournalLine);
    end;
}
