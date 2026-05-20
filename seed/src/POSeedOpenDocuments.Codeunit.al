namespace FBakkensen.BcLinuxSmoke.Seed;

using Microsoft.Inventory.Item;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.Vendor;

codeunit 50207 "PO Seed Open Documents"
{
    Access = Public;
    Permissions = tabledata Item = R,
                  tabledata Customer = R,
                  tabledata Vendor = R,
                  tabledata "Sales Header" = RI,
                  tabledata "Sales Line" = RI,
                  tabledata "Purchase Header" = RI,
                  tabledata "Purchase Line" = RI;

    var
        SalesOrderNoFmtLbl: Label 'POS-SO-%1', Comment = '%1 = order index padded to 4', Locked = true;
        PurchaseOrderNoFmtLbl: Label 'POS-PO-%1', Comment = '%1 = order index padded to 4', Locked = true;
        OrderIdxFmtLbl: Label '<Integer,4><Filler Character,0>', Locked = true;
        SeedCustomerFilterTok: Label 'POS-CUST-*', Locked = true;
        SeedVendorFilterTok: Label 'POS-VEND-*', Locked = true;
        SeedItemFilterTok: Label 'POS-I*', Locked = true;

    procedure SeedOpenDocuments(SeedTodayParam: Date)
    var
        Rng: Codeunit "PO Seed Rng";
        Constants: Codeunit "PO Seed Constants";
    begin
        Rng.Init(Constants.RngSeedForCompany(CompanyName()) + 2);
        SeedSalesOrders(SeedTodayParam, Rng);
        SeedPurchaseOrders(SeedTodayParam, Rng);
    end;

    local procedure SeedSalesOrders(SeedTodayParam: Date; var Rng: Codeunit "PO Seed Rng")
    var
        SalesOrderCount: Integer;
        Idx: Integer;
    begin
        SalesOrderCount := 10;
        for Idx := 1 to SalesOrderCount do
            CreateSalesOrder(Idx, SeedTodayParam, Rng);
    end;

    local procedure SeedPurchaseOrders(SeedTodayParam: Date; var Rng: Codeunit "PO Seed Rng")
    var
        PurchaseOrderCount: Integer;
        Idx: Integer;
    begin
        PurchaseOrderCount := 5;
        for Idx := 1 to PurchaseOrderCount do
            CreatePurchaseOrder(Idx, SeedTodayParam, Rng);
    end;

    local procedure CreateSalesOrder(Idx: Integer; SeedTodayParam: Date; var Rng: Codeunit "PO Seed Rng")
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        Customer: Record Customer;
        Item: Record Item;
        ShipmentDate: Date;
        DocNo: Code[20];
    begin
        if not FindFirstCustomer(Customer) then
            exit;
        if not FindRandomSeedItem(Item, Rng) then
            exit;

        DocNo := CopyStr(StrSubstNo(SalesOrderNoFmtLbl, Format(Idx, 4, OrderIdxFmtLbl)), 1, 20);
        if SalesHeader.Get(SalesHeader."Document Type"::Order, DocNo) then
            exit;
        SalesHeader.Init();
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := DocNo;
        SalesHeader.Validate("Sell-to Customer No.", Customer."No.");
        SalesHeader."Posting Date" := SeedTodayParam;
        SalesHeader."Order Date" := SeedTodayParam;
        ShipmentDate := SeedTodayParam + Rng.NextIntInRange(7, 60);
        SalesHeader."Shipment Date" := ShipmentDate;
        SalesHeader.Insert(true);

        SalesLine.Init();
        SalesLine."Document Type" := SalesHeader."Document Type";
        SalesLine."Document No." := SalesHeader."No.";
        SalesLine."Line No." := 10000;
        SalesLine.Validate(Type, SalesLine.Type::Item);
        SalesLine.Validate("No.", Item."No.");
        SalesLine.Validate(Quantity, Rng.NextIntInRange(1, 20));
        SalesLine."Shipment Date" := ShipmentDate;
        SalesLine.Insert(true);
    end;

    local procedure CreatePurchaseOrder(Idx: Integer; SeedTodayParam: Date; var Rng: Codeunit "PO Seed Rng")
    var
        PurchaseHeader: Record "Purchase Header";
        PurchaseLine: Record "Purchase Line";
        Vendor: Record Vendor;
        Item: Record Item;
        ExpectedDate: Date;
        DocNo: Code[20];
    begin
        if not FindFirstVendor(Vendor) then
            exit;
        if not FindRandomSeedItem(Item, Rng) then
            exit;

        DocNo := CopyStr(StrSubstNo(PurchaseOrderNoFmtLbl, Format(Idx, 4, OrderIdxFmtLbl)), 1, 20);
        if PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, DocNo) then
            exit;
        PurchaseHeader.Init();
        PurchaseHeader."Document Type" := PurchaseHeader."Document Type"::Order;
        PurchaseHeader."No." := DocNo;
        PurchaseHeader.Validate("Buy-from Vendor No.", Vendor."No.");
        PurchaseHeader."Posting Date" := SeedTodayParam;
        PurchaseHeader."Order Date" := SeedTodayParam;
        ExpectedDate := SeedTodayParam + Rng.NextIntInRange(7, 30);
        PurchaseHeader."Expected Receipt Date" := ExpectedDate;
        PurchaseHeader.Insert(true);

        PurchaseLine.Init();
        PurchaseLine."Document Type" := PurchaseHeader."Document Type";
        PurchaseLine."Document No." := PurchaseHeader."No.";
        PurchaseLine."Line No." := 10000;
        PurchaseLine.Validate(Type, PurchaseLine.Type::Item);
        PurchaseLine.Validate("No.", Item."No.");
        PurchaseLine.Validate(Quantity, Rng.NextIntInRange(10, 100));
        PurchaseLine."Expected Receipt Date" := ExpectedDate;
        PurchaseLine.Insert(true);
    end;

    local procedure FindFirstCustomer(var Customer: Record Customer): Boolean
    begin
        Customer.SetFilter("No.", SeedCustomerFilterTok);
        exit(Customer.FindFirst());
    end;

    local procedure FindFirstVendor(var Vendor: Record Vendor): Boolean
    begin
        Vendor.SetFilter("No.", SeedVendorFilterTok);
        exit(Vendor.FindFirst());
    end;

    local procedure FindRandomSeedItem(var Item: Record Item; var Rng: Codeunit "PO Seed Rng"): Boolean
    var
        Constants: Codeunit "PO Seed Constants";
        TargetIdx: Integer;
        Counter: Integer;
    begin
        Item.SetFilter("No.", SeedItemFilterTok);
        if not Item.FindSet() then
            exit(false);
        TargetIdx := Rng.NextIntInRange(1, Constants.ItemsPerCompany());
        Counter := 1;
        repeat
            if Counter = TargetIdx then
                exit(true);
            Counter += 1;
        until Item.Next() = 0;
        exit(true);
    end;
}
