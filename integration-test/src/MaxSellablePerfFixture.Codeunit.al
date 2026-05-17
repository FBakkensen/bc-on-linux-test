namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Assembly.Document;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Transfer;
using Microsoft.Manufacturing.Document;
using Microsoft.Projects.Project.Planning;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Sales.Setup;
using Microsoft.Service.Document;

codeunit 50162 "Max Sellable Perf Fixture"
{
    Access = Internal;
    Permissions = tabledata "Assembly Header" = I,
                  tabledata "Assembly Line" = I,
                  tabledata Item = I,
                  tabledata "Item Ledger Entry" = RI,
                  tabledata "Job Planning Line" = I,
                  tabledata "Prod. Order Component" = I,
                  tabledata "Prod. Order Line" = I,
                  tabledata "Purchase Line" = I,
                  tabledata "Sales & Receivables Setup" = RIM,
                  tabledata "Sales Line" = I,
                  tabledata "Service Line" = I,
                  tabledata "Transfer Line" = I;
    var
        FixtureItemNo: Code[20];

    procedure MeasureRunGatedFlow(EventCount: Integer; BudgetMs: BigInteger)
    var
        SalesLineUnderTest: Record "Sales Line";
        Handler: Codeunit "Max Sellable Validate Handler";
        BCEventSource: Codeunit "BC Event Source";
        BCStockoutChecker: Codeunit "BC Stockout Checker";
        BCNotifDispatcher: Codeunit "BC Notification Dispatcher";
        EventSource: Interface "IEventSource";
        StockoutChecker: Interface "IStockoutChecker";
        NotificationDispatcher: Interface "INotificationDispatcher";
        StartTime: DateTime;
        ElapsedMs: BigInteger;
        Samples: array[5] of BigInteger;
        MaxMs: BigInteger;
        i: Integer;
        BudgetExceededErr: Label 'RunGatedFlow max %1 ms exceeded budget %2 ms over %3 events. Samples (ms): [%4, %5, %6, %7, %8].', Comment = '%1 = Max ms, %2 = Budget ms, %3 = Event count, %4 = Sample 1 ms, %5 = Sample 2 ms, %6 = Sample 3 ms, %7 = Sample 4 ms, %8 = Sample 5 ms';
    begin
        SeedFixture(EventCount, SalesLineUnderTest);

        EventSource := BCEventSource;
        StockoutChecker := BCStockoutChecker;
        NotificationDispatcher := BCNotifDispatcher;

        // Warm-up — first call hits cold caches, discard the result.
        Handler.RunGatedFlow(SalesLineUnderTest, EventSource, StockoutChecker, NotificationDispatcher);

        MaxMs := 0;
        for i := 1 to 5 do begin
            StartTime := CurrentDateTime();
            Handler.RunGatedFlow(SalesLineUnderTest, EventSource, StockoutChecker, NotificationDispatcher);
            ElapsedMs := CurrentDateTime() - StartTime;
            Samples[i] := ElapsedMs;
            if ElapsedMs > MaxMs then
                MaxMs := ElapsedMs;
        end;

        if MaxMs > BudgetMs then
            Error(BudgetExceededErr,
                MaxMs, BudgetMs, EventCount,
                Samples[1], Samples[2], Samples[3], Samples[4], Samples[5]);
    end;

    local procedure SeedFixture(EventCount: Integer; var SalesLineUnderTest: Record "Sales Line")
    var
        Item: Record Item;
        SalesN: Integer;
        PurchN: Integer;
        TransferN: Integer;
        ProdLineN: Integer;
        ProdCompN: Integer;
        AsmHeaderN: Integer;
        AsmLineN: Integer;
        ServiceN: Integer;
        JobN: Integer;
    begin
        FixtureItemNo := CopyStr('PERF' + Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, MaxStrLen(FixtureItemNo));
        Item.Init();
        Item."No." := FixtureItemNo;
        Item.Insert(false);

        // On-hand high enough that CU 311's inventory check does not fire — the fast path
        // through the gate runs end to end into Calculate.
        SeedOnHand(100000);

        SalesN := (EventCount * 50) div 100;
        PurchN := (EventCount * 20) div 100;
        TransferN := (EventCount * 10) div 100;
        ProdLineN := (EventCount * 6) div 100;
        ProdCompN := (EventCount * 4) div 100;
        AsmHeaderN := (EventCount * 25) div 1000;
        AsmLineN := (EventCount * 25) div 1000;
        ServiceN := (EventCount * 25) div 1000;
        JobN := EventCount - (SalesN + PurchN + TransferN + ProdLineN + ProdCompN + AsmHeaderN + AsmLineN + ServiceN);

        SeedSalesLines(SalesN);
        SeedPurchaseLines(PurchN);
        SeedTransferLines(TransferN);
        SeedProdOrderLines(ProdLineN);
        SeedProdOrderComponents(ProdCompN);
        SeedAssemblyHeaders(AsmHeaderN);
        SeedAssemblyLines(AsmLineN);
        SeedServiceLines(ServiceN);
        SeedJobPlanningLines(JobN);

        BuildSalesLineUnderTest(SalesLineUnderTest);
        ConfigureSetup();
    end;

    local procedure BuildSalesLineUnderTest(var SalesLineUnderTest: Record "Sales Line")
    begin
        SalesLineUnderTest."Document Type" := SalesLineUnderTest."Document Type"::Order;
        SalesLineUnderTest."Document No." := 'PERF-EDIT';
        SalesLineUnderTest."Line No." := 99990000;
        SalesLineUnderTest.Type := SalesLineUnderTest.Type::Item;
        SalesLineUnderTest."No." := FixtureItemNo;
        SalesLineUnderTest."Variant Code" := '';
        SalesLineUnderTest."Location Code" := '';
        SalesLineUnderTest."Shipment Date" := WorkDate();
        SalesLineUnderTest.Quantity := 1;
        SalesLineUnderTest."Quantity (Base)" := 1;
        SalesLineUnderTest."Outstanding Quantity" := 1;
        SalesLineUnderTest."Outstanding Qty. (Base)" := 1;
        SalesLineUnderTest."Qty. per Unit of Measure" := 1;
        SalesLineUnderTest.Insert(false);
    end;

    local procedure ConfigureSetup()
    var
        SalesSetup: Record "Sales & Receivables Setup";
    begin
        if not SalesSetup.Get() then begin
            SalesSetup.Init();
            SalesSetup.Insert(false);
        end;
        SalesSetup."Stockout Warning" := true;
        SalesSetup."Max Sellable Warning" := true;
        SalesSetup.Modify(false);
    end;

    local procedure SeedOnHand(Qty: Decimal)
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
        ILE."Item No." := FixtureItemNo;
        ILE."Posting Date" := WorkDate() - 10;
        ILE.Quantity := Qty;
        ILE."Remaining Quantity" := Qty;
        ILE.Open := true;
        ILE.Positive := true;
        ILE.Insert(false);
    end;

    local procedure SeedSalesLines(N: Integer)
    var
        SalesLine: Record "Sales Line";
        i: Integer;
    begin
        for i := 1 to N do begin
            SalesLine.Init();
            SalesLine."Document Type" := SalesLine."Document Type"::Order;
            SalesLine."Document No." := 'PERF-SO';
            SalesLine."Line No." := i * 10000;
            SalesLine.Type := SalesLine.Type::Item;
            SalesLine."No." := FixtureItemNo;
            SalesLine."Shipment Date" := WorkDate() + (i mod 90);
            SalesLine.Quantity := 1;
            SalesLine."Quantity (Base)" := 1;
            SalesLine."Outstanding Quantity" := 1;
            SalesLine."Outstanding Qty. (Base)" := 1;
            SalesLine."Qty. per Unit of Measure" := 1;
            SalesLine.Insert(false);
        end;
    end;

    local procedure SeedPurchaseLines(N: Integer)
    var
        PurchLine: Record "Purchase Line";
        i: Integer;
    begin
        for i := 1 to N do begin
            PurchLine.Init();
            PurchLine."Document Type" := PurchLine."Document Type"::Order;
            PurchLine."Document No." := 'PERF-PO';
            PurchLine."Line No." := i * 10000;
            PurchLine.Type := PurchLine.Type::Item;
            PurchLine."No." := FixtureItemNo;
            PurchLine."Expected Receipt Date" := WorkDate() + (i mod 90);
            PurchLine.Quantity := 1;
            PurchLine."Quantity (Base)" := 1;
            PurchLine."Outstanding Quantity" := 1;
            PurchLine."Outstanding Qty. (Base)" := 1;
            PurchLine."Qty. per Unit of Measure" := 1;
            PurchLine.Insert(false);
        end;
    end;

    local procedure SeedTransferLines(N: Integer)
    var
        TransferLine: Record "Transfer Line";
        i: Integer;
    begin
        for i := 1 to N do begin
            TransferLine.Init();
            TransferLine."Document No." := 'PERF-TO';
            TransferLine."Line No." := i * 10000;
            TransferLine."Item No." := FixtureItemNo;
            TransferLine."Transfer-from Code" := '';
            TransferLine."Transfer-to Code" := '';
            TransferLine."Shipment Date" := WorkDate() + (i mod 90);
            TransferLine."Receipt Date" := WorkDate() + (i mod 90) + 2;
            TransferLine.Quantity := 1;
            TransferLine."Quantity (Base)" := 1;
            TransferLine."Outstanding Quantity" := 1;
            TransferLine."Outstanding Qty. (Base)" := 1;
            TransferLine."Derived From Line No." := 0;
            TransferLine."Qty. per Unit of Measure" := 1;
            TransferLine.Insert(false);
        end;
    end;

    local procedure SeedProdOrderLines(N: Integer)
    var
        ProdOrderLine: Record "Prod. Order Line";
        i: Integer;
    begin
        for i := 1 to N do begin
            ProdOrderLine.Init();
            ProdOrderLine.Status := ProdOrderLine.Status::Released;
            ProdOrderLine."Prod. Order No." := 'PERF-PROD';
            ProdOrderLine."Line No." := i * 10000;
            ProdOrderLine."Item No." := FixtureItemNo;
            ProdOrderLine."Due Date" := WorkDate() + (i mod 90);
            ProdOrderLine.Quantity := 1;
            ProdOrderLine."Quantity (Base)" := 1;
            ProdOrderLine."Remaining Quantity" := 1;
            ProdOrderLine."Remaining Qty. (Base)" := 1;
            ProdOrderLine."Qty. per Unit of Measure" := 1;
            ProdOrderLine.Insert(false);
        end;
    end;

    local procedure SeedProdOrderComponents(N: Integer)
    var
        ProdOrderComp: Record "Prod. Order Component";
        i: Integer;
    begin
        for i := 1 to N do begin
            ProdOrderComp.Init();
            ProdOrderComp.Status := ProdOrderComp.Status::Released;
            ProdOrderComp."Prod. Order No." := 'PERF-PROD';
            ProdOrderComp."Prod. Order Line No." := 10000;
            ProdOrderComp."Line No." := i * 10000;
            ProdOrderComp."Item No." := FixtureItemNo;
            ProdOrderComp."Due Date" := WorkDate() + (i mod 90);
            ProdOrderComp."Quantity (Base)" := 1;
            ProdOrderComp."Remaining Quantity" := 1;
            ProdOrderComp."Remaining Qty. (Base)" := 1;
            ProdOrderComp."Qty. per Unit of Measure" := 1;
            ProdOrderComp.Insert(false);
        end;
    end;

    local procedure SeedAssemblyHeaders(N: Integer)
    var
        AsmHeader: Record "Assembly Header";
        i: Integer;
    begin
        for i := 1 to N do begin
            AsmHeader.Init();
            AsmHeader."Document Type" := AsmHeader."Document Type"::Order;
            AsmHeader."No." := CopyStr('PERF-ASMH-' + Format(i), 1, MaxStrLen(AsmHeader."No."));
            AsmHeader."Item No." := FixtureItemNo;
            AsmHeader."Due Date" := WorkDate() + (i mod 90);
            AsmHeader.Quantity := 1;
            AsmHeader."Quantity (Base)" := 1;
            AsmHeader."Remaining Quantity" := 1;
            AsmHeader."Remaining Quantity (Base)" := 1;
            AsmHeader."Qty. per Unit of Measure" := 1;
            AsmHeader.Insert(false);
        end;
    end;

    local procedure SeedAssemblyLines(N: Integer)
    var
        AsmLine: Record "Assembly Line";
        i: Integer;
    begin
        for i := 1 to N do begin
            AsmLine.Init();
            AsmLine."Document Type" := AsmLine."Document Type"::Order;
            AsmLine."Document No." := 'PERF-ASML';
            AsmLine."Line No." := i * 10000;
            AsmLine.Type := AsmLine.Type::Item;
            AsmLine."No." := FixtureItemNo;
            AsmLine."Due Date" := WorkDate() + (i mod 90);
            AsmLine.Quantity := 1;
            AsmLine."Quantity (Base)" := 1;
            AsmLine."Remaining Quantity" := 1;
            AsmLine."Remaining Quantity (Base)" := 1;
            AsmLine."Qty. per Unit of Measure" := 1;
            AsmLine.Insert(false);
        end;
    end;

    local procedure SeedServiceLines(N: Integer)
    var
        ServiceLine: Record "Service Line";
        i: Integer;
    begin
        for i := 1 to N do begin
            ServiceLine.Init();
            ServiceLine."Document Type" := ServiceLine."Document Type"::Order;
            ServiceLine."Document No." := 'PERF-SVC';
            ServiceLine."Line No." := i * 10000;
            ServiceLine.Type := ServiceLine.Type::Item;
            ServiceLine."No." := FixtureItemNo;
            ServiceLine."Needed by Date" := WorkDate() + (i mod 90);
            ServiceLine.Quantity := 1;
            ServiceLine."Quantity (Base)" := 1;
            ServiceLine."Outstanding Quantity" := 1;
            ServiceLine."Outstanding Qty. (Base)" := 1;
            ServiceLine."Qty. per Unit of Measure" := 1;
            ServiceLine.Insert(false);
        end;
    end;

    local procedure SeedJobPlanningLines(N: Integer)
    var
        JPL: Record "Job Planning Line";
        i: Integer;
        LineType: Enum "Job Planning Line Line Type";
    begin
        for i := 1 to N do begin
            case i mod 3 of
                0:
                    LineType := LineType::Budget;
                1:
                    LineType := LineType::Billable;
                2:
                    LineType := LineType::"Both Budget and Billable";
            end;
            JPL.Init();
            JPL.Status := JPL.Status::Order;
            JPL."Job No." := 'PERF-JOB';
            JPL."Job Task No." := 'T1';
            JPL."Line No." := i * 10000;
            JPL.Type := JPL.Type::Item;
            JPL."Line Type" := LineType;
            JPL."No." := FixtureItemNo;
            JPL."Planning Date" := WorkDate() + (i mod 90);
            JPL.Quantity := 1;
            JPL."Quantity (Base)" := 1;
            JPL."Remaining Qty." := 1;
            JPL."Remaining Qty. (Base)" := 1;
            JPL."Qty. per Unit of Measure" := 1;
            JPL.Insert(false);
        end;
    end;
}
