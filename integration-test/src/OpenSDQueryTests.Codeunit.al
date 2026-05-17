namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Assembly.Document;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Transfer;
using Microsoft.Manufacturing.Document;
using Microsoft.Projects.Project.Job;
using Microsoft.Projects.Project.Planning;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Service.Document;
using System.TestLibraries.Utilities;

codeunit 50161 "Open SD Query Tests"
{
    Subtype = Test;
    Access = Internal;
    Permissions = tabledata Item = I,
                  tabledata "Sales Line" = I,
                  tabledata "Purchase Line" = I,
                  tabledata "Transfer Line" = I,
                  tabledata "Service Line" = I,
                  tabledata "Prod. Order Line" = I,
                  tabledata "Prod. Order Component" = I,
                  tabledata "Assembly Header" = I,
                  tabledata "Assembly Line" = I,
                  tabledata Job = I,
                  tabledata "Job Planning Line" = I;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure SalesOrderRowSurfacesWithDocumentType()
    var
        Item: Record Item;
        OpenSDSales: Query "Open SD Sales";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        ItemNo := MakeItem(Item);
        InsertSalesLine("Sales Document Type"::Order, UniqueDocNo('SO'), 10000, ItemNo, '', 'BLUE', WorkDate() + 5, 12);

        OpenSDSales.SetFilter(itemNo, ItemNo);
        OpenSDSales.Open();
        while OpenSDSales.Read() do begin
            Rows += 1;
            Assert.AreEqual(ItemNo, OpenSDSales.itemNo, 'itemNo pass-through.');
            Assert.AreEqual('BLUE', OpenSDSales.locationCode, 'locationCode pass-through.');
            Assert.AreEqual(WorkDate() + 5, OpenSDSales.shipmentDate, 'shipmentDate pass-through.');
            Assert.AreEqual(12, OpenSDSales.outstandingQtyBase, 'outstandingQtyBase pass-through.');
            Assert.AreEqual(OpenSDSales.documentType::Order, OpenSDSales.documentType, 'documentType must let Python split Order vs Return Order.');
        end;
        OpenSDSales.Close();

        Assert.AreEqual(1, Rows, 'Exactly the seeded sales order row must surface.');
    end;

    [Test]
    procedure SalesReturnOrderRowSurfacesSeparatelyFromOrder()
    var
        Item: Record Item;
        OpenSDSales: Query "Open SD Sales";
        ItemNo: Code[20];
        SeenReturn: Boolean;
    begin
        ItemNo := MakeItem(Item);
        InsertSalesLine("Sales Document Type"::"Return Order", UniqueDocNo('SR'), 10000, ItemNo, '', 'BLUE', WorkDate() + 5, 4);

        OpenSDSales.SetFilter(itemNo, ItemNo);
        OpenSDSales.Open();
        while OpenSDSales.Read() do
            if OpenSDSales.documentType = OpenSDSales.documentType::"Return Order" then
                SeenReturn := true;
        OpenSDSales.Close();

        Assert.IsTrue(SeenReturn, 'Sales Return Order must surface with documentType = Return Order.');
    end;

    [Test]
    procedure SalesQuoteAndInvoiceAreExcludedServerSide()
    var
        Item: Record Item;
        OpenSDSales: Query "Open SD Sales";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        // ADR 0001 inclusion list: Quotes and Invoices must NOT surface.
        // Drift on this filter silently widens what the simulator treats
        // as committed; pin it here.
        ItemNo := MakeItem(Item);
        InsertSalesLine("Sales Document Type"::Quote, UniqueDocNo('SQ'), 10000, ItemNo, '', 'BLUE', WorkDate() + 5, 999);
        InsertSalesLine("Sales Document Type"::Invoice, UniqueDocNo('SI'), 10000, ItemNo, '', 'BLUE', WorkDate() + 5, 999);

        OpenSDSales.SetFilter(itemNo, ItemNo);
        OpenSDSales.Open();
        while OpenSDSales.Read() do
            Rows += 1;
        OpenSDSales.Close();

        Assert.AreEqual(0, Rows, 'Sales Quote and Sales Invoice must not surface in Open SD Sales.');
    end;

    [Test]
    procedure PurchaseOrderRowSurfacesWithExpectedReceiptDate()
    var
        Item: Record Item;
        OpenSDPurchase: Query "Open SD Purchase";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        ItemNo := MakeItem(Item);
        InsertPurchaseLine("Purchase Document Type"::Order, UniqueDocNo('PO'), 10000, ItemNo, 'BLUE', WorkDate() + 7, 50);

        OpenSDPurchase.SetFilter(itemNo, ItemNo);
        OpenSDPurchase.Open();
        while OpenSDPurchase.Read() do begin
            Rows += 1;
            Assert.AreEqual(50, OpenSDPurchase.outstandingQtyBase, 'qty pass-through.');
            Assert.AreEqual(WorkDate() + 7, OpenSDPurchase.expectedReceiptDate, 'expectedReceiptDate pass-through.');
            Assert.AreEqual(OpenSDPurchase.documentType::Order, OpenSDPurchase.documentType, 'documentType must split Order vs Return Order.');
        end;
        OpenSDPurchase.Close();

        Assert.AreEqual(1, Rows, 'Exactly the seeded purchase order row must surface.');
    end;

    [Test]
    procedure TransferInUsesDestinationLocationAndReceiptDate()
    var
        Item: Record Item;
        OpenSDTransferIn: Query "Open SD Transfer In";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        ItemNo := MakeItem(Item);
        InsertTransferLine(UniqueDocNo('TF'), 10000, ItemNo, 'SRC', 'DEST', WorkDate() + 3, WorkDate() + 6, 8);

        OpenSDTransferIn.SetFilter(itemNo, ItemNo);
        OpenSDTransferIn.Open();
        while OpenSDTransferIn.Read() do begin
            Rows += 1;
            Assert.AreEqual('DEST', OpenSDTransferIn.locationCode, 'Transfer In uses Transfer-to Code.');
            Assert.AreEqual(WorkDate() + 6, OpenSDTransferIn.receiptDate, 'Transfer In uses Receipt Date.');
            Assert.AreEqual(8, OpenSDTransferIn.outstandingQtyBase, 'qty pass-through.');
        end;
        OpenSDTransferIn.Close();

        Assert.AreEqual(1, Rows, 'Exactly one Transfer In row per open transfer line.');
    end;

    [Test]
    procedure TransferOutUsesSourceLocationAndShipmentDate()
    var
        Item: Record Item;
        OpenSDTransferOut: Query "Open SD Transfer Out";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        ItemNo := MakeItem(Item);
        InsertTransferLine(UniqueDocNo('TF'), 10000, ItemNo, 'SRC', 'DEST', WorkDate() + 3, WorkDate() + 6, 8);

        OpenSDTransferOut.SetFilter(itemNo, ItemNo);
        OpenSDTransferOut.Open();
        while OpenSDTransferOut.Read() do begin
            Rows += 1;
            Assert.AreEqual('SRC', OpenSDTransferOut.locationCode, 'Transfer Out uses Transfer-from Code.');
            Assert.AreEqual(WorkDate() + 3, OpenSDTransferOut.shipmentDate, 'Transfer Out uses Shipment Date.');
            Assert.AreEqual(8, OpenSDTransferOut.outstandingQtyBase, 'qty pass-through.');
        end;
        OpenSDTransferOut.Close();

        Assert.AreEqual(1, Rows, 'Exactly one Transfer Out row per open transfer line.');
    end;

    [Test]
    procedure ServiceOrderLineSurfaces()
    var
        Item: Record Item;
        OpenSDService: Query "Open SD Service";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        ItemNo := MakeItem(Item);
        InsertServiceLine("Service Document Type"::Order, UniqueDocNo('SV'), 10000, ItemNo, 'BLUE', WorkDate() + 4, 6);

        OpenSDService.SetFilter(itemNo, ItemNo);
        OpenSDService.Open();
        while OpenSDService.Read() do begin
            Rows += 1;
            Assert.AreEqual(6, OpenSDService.outstandingQtyBase, 'qty pass-through.');
            Assert.AreEqual(WorkDate() + 4, OpenSDService.neededByDate, 'neededByDate pass-through.');
        end;
        OpenSDService.Close();

        Assert.AreEqual(1, Rows, 'Exactly one Service line row per open order.');
    end;

    [Test]
    procedure ProdOrderLineSurfacesForPlannedFirmPlannedReleased()
    var
        Item: Record Item;
        OpenSDProdOrderLine: Query "Open SD Prod Order Line";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        // ADR 0001 deviation #1: include Planned + Firm Planned + Released,
        // exclude Simulated + Finished. Status isn't a column on the Query
        // (Python projector doesn't need it), so we seed all five statuses
        // and count: 3 in, 2 out.
        ItemNo := MakeItem(Item);
        InsertProdOrderLine("Production Order Status"::Simulated, UniqueDocNo('POSIM'), 10000, ItemNo, 'BLUE', WorkDate() + 10, 1);
        InsertProdOrderLine("Production Order Status"::Planned, UniqueDocNo('POPLN'), 10000, ItemNo, 'BLUE', WorkDate() + 10, 1);
        InsertProdOrderLine("Production Order Status"::"Firm Planned", UniqueDocNo('POFPL'), 10000, ItemNo, 'BLUE', WorkDate() + 10, 1);
        InsertProdOrderLine("Production Order Status"::Released, UniqueDocNo('POREL'), 10000, ItemNo, 'BLUE', WorkDate() + 10, 1);
        InsertProdOrderLine("Production Order Status"::Finished, UniqueDocNo('POFIN'), 10000, ItemNo, 'BLUE', WorkDate() + 10, 1);

        OpenSDProdOrderLine.SetFilter(itemNo, ItemNo);
        OpenSDProdOrderLine.Open();
        while OpenSDProdOrderLine.Read() do
            Rows += 1;
        OpenSDProdOrderLine.Close();

        Assert.AreEqual(3, Rows, 'ADR 0001 deviation #1: only Planned + Firm Planned + Released must surface.');
    end;

    [Test]
    procedure ProdOrderLineExcludesSimulatedAndFinished()
    var
        Item: Record Item;
        OpenSDProdOrderLine: Query "Open SD Prod Order Line";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        ItemNo := MakeItem(Item);
        InsertProdOrderLine("Production Order Status"::Simulated, UniqueDocNo('POSIM'), 10000, ItemNo, 'BLUE', WorkDate() + 10, 5);
        InsertProdOrderLine("Production Order Status"::Finished, UniqueDocNo('POFIN'), 10000, ItemNo, 'BLUE', WorkDate() + 10, 5);

        OpenSDProdOrderLine.SetFilter(itemNo, ItemNo);
        OpenSDProdOrderLine.Open();
        while OpenSDProdOrderLine.Read() do
            Rows += 1;
        OpenSDProdOrderLine.Close();

        Assert.AreEqual(0, Rows, 'ADR 0001 deviation #1: Simulated and Finished prod orders must NOT surface.');
    end;

    [Test]
    procedure ProdOrderComponentSurfacesForReleased()
    var
        Item: Record Item;
        OpenSDProdOrderComp: Query "Open SD Prod Order Comp";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        ItemNo := MakeItem(Item);
        InsertProdOrderComponent("Production Order Status"::Released, UniqueDocNo('POREL'), 10000, 1, ItemNo, 'BLUE', WorkDate() + 10, 3);

        OpenSDProdOrderComp.SetFilter(itemNo, ItemNo);
        OpenSDProdOrderComp.Open();
        while OpenSDProdOrderComp.Read() do begin
            Rows += 1;
            Assert.AreEqual(3, OpenSDProdOrderComp.remainingQtyBase, 'qty pass-through.');
        end;
        OpenSDProdOrderComp.Close();

        Assert.AreEqual(1, Rows, 'Released Prod Order Component must surface.');
    end;

    [Test]
    procedure AssemblyHeaderOrderSurfaces()
    var
        Item: Record Item;
        OpenSDAssemblyHeader: Query "Open SD Assembly Header";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        ItemNo := MakeItem(Item);
        InsertAssemblyHeader("Assembly Document Type"::Order, UniqueDocNo('ASM'), ItemNo, 'BLUE', WorkDate() + 8, 9);

        OpenSDAssemblyHeader.SetFilter(itemNo, ItemNo);
        OpenSDAssemblyHeader.Open();
        while OpenSDAssemblyHeader.Read() do begin
            Rows += 1;
            Assert.AreEqual(9, OpenSDAssemblyHeader.remainingQtyBase, 'qty pass-through.');
            Assert.AreEqual(WorkDate() + 8, OpenSDAssemblyHeader.dueDate, 'dueDate pass-through.');
        end;
        OpenSDAssemblyHeader.Close();

        Assert.AreEqual(1, Rows, 'Assembly Order header must surface.');
    end;

    [Test]
    procedure AssemblyHeaderBlanketIsExcluded()
    var
        Item: Record Item;
        OpenSDAssemblyHeader: Query "Open SD Assembly Header";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        // ADR 0001 deviation #2: blanket Assembly headers are NOT real
        // near-term commitments — exclude them. This test guards the
        // const(Order) filter against a future "include Blanket" tweak.
        ItemNo := MakeItem(Item);
        InsertAssemblyHeader("Assembly Document Type"::"Blanket Order", UniqueDocNo('ASB'), ItemNo, 'BLUE', WorkDate() + 8, 99);

        OpenSDAssemblyHeader.SetFilter(itemNo, ItemNo);
        OpenSDAssemblyHeader.Open();
        while OpenSDAssemblyHeader.Read() do
            Rows += 1;
        OpenSDAssemblyHeader.Close();

        Assert.AreEqual(0, Rows, 'ADR 0001 deviation #2: blanket Assembly headers must NOT surface.');
    end;

    [Test]
    procedure AssemblyLineOrderSurfaces()
    var
        Item: Record Item;
        OpenSDAssemblyLine: Query "Open SD Assembly Line";
        ItemNo: Code[20];
        Rows: Integer;
    begin
        ItemNo := MakeItem(Item);
        InsertAssemblyLine("Assembly Document Type"::Order, UniqueDocNo('ASM'), 10000, ItemNo, 'BLUE', WorkDate() + 8, 2);

        OpenSDAssemblyLine.SetFilter(itemNo, ItemNo);
        OpenSDAssemblyLine.Open();
        while OpenSDAssemblyLine.Read() do begin
            Rows += 1;
            Assert.AreEqual(2, OpenSDAssemblyLine.remainingQtyBase, 'qty pass-through.');
        end;
        OpenSDAssemblyLine.Close();

        Assert.AreEqual(1, Rows, 'Assembly Order line must surface.');
    end;

    [Test]
    procedure JobPlanningLineSurfacesWithLineType()
    var
        Item: Record Item;
        OpenSDJobPlanning: Query "Open SD Job Planning";
        ItemNo: Code[20];
        JobNo: Code[20];
        Rows: Integer;
    begin
        ItemNo := MakeItem(Item);
        JobNo := UniqueDocNo('JOB');
        InsertJob(JobNo);
        InsertJobPlanningLine("Job Planning Line Status"::Order, JobNo, 10000, ItemNo, 'BLUE', WorkDate() + 9, 7, "Job Planning Line Line Type"::"Both Budget and Billable");

        OpenSDJobPlanning.SetFilter(itemNo, ItemNo);
        OpenSDJobPlanning.Open();
        while OpenSDJobPlanning.Read() do begin
            Rows += 1;
            Assert.AreEqual(OpenSDJobPlanning.lineType::"Both Budget and Billable", OpenSDJobPlanning.lineType, 'lineType pass-through enables ADR 0001 deviation #3 doubling.');
        end;
        OpenSDJobPlanning.Close();

        Assert.AreEqual(1, Rows, 'Exactly one row per Job Planning Line (Python doubles for Both type).');
    end;

    // ----- helpers -----

    local procedure MakeItem(var Item: Record Item): Code[20]
    var
        ItemNo: Code[20];
    begin
        ItemNo := CopyStr('OSD-' + UniqueSuffix(), 1, MaxStrLen(ItemNo));
        Item.Init();
        Item."No." := ItemNo;
        Item.Insert(false);
        exit(ItemNo);
    end;

    local procedure UniqueDocNo(Prefix: Text): Code[20]
    begin
        exit(CopyStr(Prefix + '-' + UniqueSuffix(), 1, 20));
    end;

    local procedure UniqueSuffix(): Text
    begin
        exit(Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(99999)));
    end;

    local procedure InsertSalesLine(DocType: Enum "Sales Document Type"; DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; ShipmentDate: Date; OutstandingQtyBase: Decimal)
    var
        SalesLine: Record "Sales Line";
    begin
        SalesLine.Init();
        SalesLine."Document Type" := DocType;
        SalesLine."Document No." := DocNo;
        SalesLine."Line No." := LineNo;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine."No." := ItemNo;
        SalesLine."Variant Code" := VariantCode;
        SalesLine."Location Code" := LocationCode;
        SalesLine."Shipment Date" := ShipmentDate;
        SalesLine.Quantity := OutstandingQtyBase;
        SalesLine."Quantity (Base)" := OutstandingQtyBase;
        SalesLine."Outstanding Quantity" := OutstandingQtyBase;
        SalesLine."Outstanding Qty. (Base)" := OutstandingQtyBase;
        SalesLine."Qty. per Unit of Measure" := 1;
        SalesLine.Insert(false);
    end;

    local procedure InsertPurchaseLine(DocType: Enum "Purchase Document Type"; DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; LocationCode: Code[10]; ExpectedReceiptDate: Date; OutstandingQtyBase: Decimal)
    var
        PurchaseLine: Record "Purchase Line";
    begin
        PurchaseLine.Init();
        PurchaseLine."Document Type" := DocType;
        PurchaseLine."Document No." := DocNo;
        PurchaseLine."Line No." := LineNo;
        PurchaseLine.Type := PurchaseLine.Type::Item;
        PurchaseLine."No." := ItemNo;
        PurchaseLine."Location Code" := LocationCode;
        PurchaseLine."Expected Receipt Date" := ExpectedReceiptDate;
        PurchaseLine.Quantity := OutstandingQtyBase;
        PurchaseLine."Quantity (Base)" := OutstandingQtyBase;
        PurchaseLine."Outstanding Quantity" := OutstandingQtyBase;
        PurchaseLine."Outstanding Qty. (Base)" := OutstandingQtyBase;
        PurchaseLine."Qty. per Unit of Measure" := 1;
        PurchaseLine.Insert(false);
    end;

    local procedure InsertTransferLine(DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; FromCode: Code[10]; ToCode: Code[10]; ShipmentDate: Date; ReceiptDate: Date; OutstandingQtyBase: Decimal)
    var
        TransferLine: Record "Transfer Line";
    begin
        TransferLine.Init();
        TransferLine."Document No." := DocNo;
        TransferLine."Line No." := LineNo;
        TransferLine."Item No." := ItemNo;
        TransferLine."Transfer-from Code" := FromCode;
        TransferLine."Transfer-to Code" := ToCode;
        TransferLine."Shipment Date" := ShipmentDate;
        TransferLine."Receipt Date" := ReceiptDate;
        TransferLine.Quantity := OutstandingQtyBase;
        TransferLine."Quantity (Base)" := OutstandingQtyBase;
        TransferLine."Outstanding Quantity" := OutstandingQtyBase;
        TransferLine."Outstanding Qty. (Base)" := OutstandingQtyBase;
        TransferLine."Qty. per Unit of Measure" := 1;
        TransferLine.Insert(false);
    end;

    local procedure InsertServiceLine(DocType: Enum "Service Document Type"; DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; LocationCode: Code[10]; NeededByDate: Date; OutstandingQtyBase: Decimal)
    var
        ServiceLine: Record "Service Line";
    begin
        ServiceLine.Init();
        ServiceLine."Document Type" := DocType;
        ServiceLine."Document No." := DocNo;
        ServiceLine."Line No." := LineNo;
        ServiceLine.Type := ServiceLine.Type::Item;
        ServiceLine."No." := ItemNo;
        ServiceLine."Location Code" := LocationCode;
        ServiceLine."Needed by Date" := NeededByDate;
        ServiceLine.Quantity := OutstandingQtyBase;
        ServiceLine."Quantity (Base)" := OutstandingQtyBase;
        ServiceLine."Outstanding Quantity" := OutstandingQtyBase;
        ServiceLine."Outstanding Qty. (Base)" := OutstandingQtyBase;
        ServiceLine."Qty. per Unit of Measure" := 1;
        ServiceLine.Insert(false);
    end;

    local procedure InsertProdOrderLine(Status: Enum "Production Order Status"; DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; LocationCode: Code[10]; DueDate: Date; RemainingQtyBase: Decimal)
    var
        ProdOrderLine: Record "Prod. Order Line";
    begin
        ProdOrderLine.Init();
        ProdOrderLine.Status := Status;
        ProdOrderLine."Prod. Order No." := DocNo;
        ProdOrderLine."Line No." := LineNo;
        ProdOrderLine."Item No." := ItemNo;
        ProdOrderLine."Location Code" := LocationCode;
        ProdOrderLine."Due Date" := DueDate;
        ProdOrderLine.Quantity := RemainingQtyBase;
        ProdOrderLine."Quantity (Base)" := RemainingQtyBase;
        ProdOrderLine."Remaining Quantity" := RemainingQtyBase;
        ProdOrderLine."Remaining Qty. (Base)" := RemainingQtyBase;
        ProdOrderLine."Qty. per Unit of Measure" := 1;
        ProdOrderLine.Insert(false);
    end;

    local procedure InsertProdOrderComponent(Status: Enum "Production Order Status"; DocNo: Code[20]; ProdOrderLineNo: Integer; LineNo: Integer; ItemNo: Code[20]; LocationCode: Code[10]; DueDate: Date; RemainingQtyBase: Decimal)
    var
        ProdOrderComp: Record "Prod. Order Component";
    begin
        ProdOrderComp.Init();
        ProdOrderComp.Status := Status;
        ProdOrderComp."Prod. Order No." := DocNo;
        ProdOrderComp."Prod. Order Line No." := ProdOrderLineNo;
        ProdOrderComp."Line No." := LineNo;
        ProdOrderComp."Item No." := ItemNo;
        ProdOrderComp."Location Code" := LocationCode;
        ProdOrderComp."Due Date" := DueDate;
        ProdOrderComp."Quantity (Base)" := RemainingQtyBase;
        ProdOrderComp."Remaining Quantity" := RemainingQtyBase;
        ProdOrderComp."Remaining Qty. (Base)" := RemainingQtyBase;
        ProdOrderComp."Qty. per Unit of Measure" := 1;
        ProdOrderComp.Insert(false);
    end;

    local procedure InsertAssemblyHeader(DocType: Enum "Assembly Document Type"; DocNo: Code[20]; ItemNo: Code[20]; LocationCode: Code[10]; DueDate: Date; RemainingQtyBase: Decimal)
    var
        AsmHeader: Record "Assembly Header";
    begin
        AsmHeader.Init();
        AsmHeader."Document Type" := DocType;
        AsmHeader."No." := DocNo;
        AsmHeader."Item No." := ItemNo;
        AsmHeader."Location Code" := LocationCode;
        AsmHeader."Due Date" := DueDate;
        AsmHeader.Quantity := RemainingQtyBase;
        AsmHeader."Quantity (Base)" := RemainingQtyBase;
        AsmHeader."Remaining Quantity" := RemainingQtyBase;
        AsmHeader."Remaining Quantity (Base)" := RemainingQtyBase;
        AsmHeader."Qty. per Unit of Measure" := 1;
        AsmHeader.Insert(false);
    end;

    local procedure InsertAssemblyLine(DocType: Enum "Assembly Document Type"; DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; LocationCode: Code[10]; DueDate: Date; RemainingQtyBase: Decimal)
    var
        AsmLine: Record "Assembly Line";
    begin
        AsmLine.Init();
        AsmLine."Document Type" := DocType;
        AsmLine."Document No." := DocNo;
        AsmLine."Line No." := LineNo;
        AsmLine.Type := AsmLine.Type::Item;
        AsmLine."No." := ItemNo;
        AsmLine."Location Code" := LocationCode;
        AsmLine."Due Date" := DueDate;
        AsmLine.Quantity := RemainingQtyBase;
        AsmLine."Quantity (Base)" := RemainingQtyBase;
        AsmLine."Remaining Quantity" := RemainingQtyBase;
        AsmLine."Remaining Quantity (Base)" := RemainingQtyBase;
        AsmLine."Qty. per Unit of Measure" := 1;
        AsmLine.Insert(false);
    end;

    local procedure InsertJob(JobNo: Code[20])
    var
        Job: Record Job;
    begin
        Job.Init();
        Job."No." := JobNo;
        Job.Insert(false);
    end;

    local procedure InsertJobPlanningLine(Status: Enum "Job Planning Line Status"; JobNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; LocationCode: Code[10]; PlanningDate: Date; RemainingQtyBase: Decimal; LineType: Enum "Job Planning Line Line Type")
    var
        JobPlanningLine: Record "Job Planning Line";
    begin
        JobPlanningLine.Init();
        JobPlanningLine.Status := Status;
        JobPlanningLine."Job No." := JobNo;
        JobPlanningLine."Line No." := LineNo;
        JobPlanningLine."Line Type" := LineType;
        JobPlanningLine.Type := JobPlanningLine.Type::Item;
        JobPlanningLine."No." := ItemNo;
        JobPlanningLine."Location Code" := LocationCode;
        JobPlanningLine."Planning Date" := PlanningDate;
        JobPlanningLine.Quantity := RemainingQtyBase;
        JobPlanningLine."Quantity (Base)" := RemainingQtyBase;
        JobPlanningLine."Remaining Qty." := RemainingQtyBase;
        JobPlanningLine."Remaining Qty. (Base)" := RemainingQtyBase;
        JobPlanningLine."Qty. per Unit of Measure" := 1;
        JobPlanningLine.Insert(false);
    end;
}
