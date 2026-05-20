namespace FBakkensen.BcLinuxSmoke.Seed;

using System.Environment;
using Microsoft.Finance.GeneralLedger.Account;
using Microsoft.Finance.GeneralLedger.Posting;
using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Finance.VAT.Setup;
using Microsoft.Assembly.Setup;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Setup;
using Microsoft.Foundation.AuditCodes;
using Microsoft.Foundation.NoSeries;
using Microsoft.Foundation.Company;
using Microsoft.Foundation.UOM;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Vendor;
using Microsoft.Sales.Customer;

codeunit 50203 "PO Seed Bootstrap"
{
    Access = Public;
    Permissions = tabledata Company = RIM,
                  tabledata "Source Code" = RI,
                  tabledata "Source Code Setup" = RI,
                  tabledata Location = RI,
                  tabledata Vendor = RI,
                  tabledata "Vendor Posting Group" = RI,
                  tabledata Customer = RI,
                  tabledata "Customer Posting Group" = RI,
                  tabledata "Unit of Measure" = RI,
                  tabledata "Gen. Product Posting Group" = RI,
                  tabledata "Gen. Business Posting Group" = RI,
                  tabledata "General Posting Setup" = RI,
                  tabledata "VAT Product Posting Group" = RI,
                  tabledata "VAT Business Posting Group" = RI,
                  tabledata "VAT Posting Setup" = RI,
                  tabledata "G/L Account" = RI,
                  tabledata "Inventory Posting Setup" = RIM,
                  tabledata "Inventory Setup" = RIM,
                  tabledata "Assembly Setup" = RIM,
                  tabledata "No. Series" = RI,
                  tabledata "No. Series Line" = RI;

    var
        VendorNoFmtLbl: Label 'POS-VEND-%1', Comment = '%1 = vendor index padded to 3 digits', Locked = true;
        VendorNameFmtLbl: Label 'Seed Vendor %1', Comment = '%1 = vendor index';
        CustomerNoFmtLbl: Label 'POS-CUST-%1', Comment = '%1 = customer index padded to 3 digits', Locked = true;
        CustomerNameFmtLbl: Label 'Seed Customer %1', Comment = '%1 = customer index';
        SeedSourceDescriptionLbl: Label 'Planning Optimizer Seed';
        BlueWarehouseLbl: Label 'Blue Warehouse';
        RedWarehouseLbl: Label 'Red Warehouse';
        GreenWarehouseLbl: Label 'Green Warehouse';
        SeedIndexFmtLbl: Label '<Integer,3><Filler Character,0>', Locked = true;

    procedure CreateCompanies()
    begin
        // No-op since the OData-session pivot — companies CRONUS and My
        // Company are pre-created by the BC container's .bak restore.
        // Kept as a public entrypoint so seed-company.sh's API contract
        // stays stable if a future BC version unblocks OData-driven
        // company creation.
    end;

    procedure BootstrapWithinCompany()
    var
        Constants: Codeunit "PO Seed Constants";
        CompanyInitialize: Codeunit "Company-Initialize";
    begin
        // The two PLANOPT companies were created by POSeedInstall's
        // OnInstallAppPerDatabase trigger via Assisted Company Setup, which
        // does Company.Insert() without running Company-Initialize. Run it
        // explicitly here so the company has its No. Series, posting groups,
        // G/L accounts, and source codes before any items / journals fire.
        // Idempotent — re-running on an initialized company no-ops on most
        // setup tables.
        CompanyInitialize.Run();
        EnsureSeedSourceCode();
        EnsureBaseUnitOfMeasure();
        EnsurePostingGroups();
        EnsureInventorySetupNoSeries();
        EnsureLocations();
        EnsureVendors(Constants.VendorCount());
        EnsureCustomers(Constants.CustomerCount());
    end;

    local procedure EnsureInventorySetupNoSeries()
    var
        NoSeries: Record "No. Series";
        NoSeriesLine: Record "No. Series Line";
        InvtSetup: Record "Inventory Setup";
        NoSeriesCodeTok: Label 'POS-INVT', Locked = true;
    begin
        // BC's Transfer + Inventory posting routines validate that Inventory
        // Setup's Transfer / Posted Transfer No. Series fields are non-empty
        // before they'll post (even when we pre-populate Last Shipment No.
        // / Last Receipt No. on the Transfer Header). Create a catch-all
        // No. Series and wire it into every relevant Inventory Setup slot.
        if not NoSeries.Get(NoSeriesCodeTok) then begin
            NoSeries.Init();
            NoSeries.Code := NoSeriesCodeTok;
            NoSeries.Description := 'Planning Seed No. Series';
            NoSeries."Default Nos." := true;
            NoSeries."Manual Nos." := true;
            NoSeries.Insert(false);
        end;
        NoSeriesLine.SetRange("Series Code", NoSeriesCodeTok);
        if NoSeriesLine.IsEmpty() then begin
            NoSeriesLine.Init();
            NoSeriesLine."Series Code" := NoSeriesCodeTok;
            NoSeriesLine."Line No." := 10000;
            NoSeriesLine."Starting No." := 'POS-AUTO-00001';
            NoSeriesLine."Ending No." := 'POS-AUTO-99999';
            NoSeriesLine."Increment-by No." := 1;
            NoSeriesLine.Insert(false);
        end;

        if not InvtSetup.Get() then begin
            InvtSetup.Init();
            InvtSetup.Insert(false);
        end;
        InvtSetup."Transfer Order Nos." := NoSeriesCodeTok;
        InvtSetup."Posted Transfer Shpt. Nos." := NoSeriesCodeTok;
        InvtSetup."Posted Transfer Rcpt. Nos." := NoSeriesCodeTok;
        InvtSetup."Posted Direct Trans. Nos." := NoSeriesCodeTok;
        InvtSetup."Posted Invt. Receipt Nos." := NoSeriesCodeTok;
        InvtSetup."Posted Invt. Shipment Nos." := NoSeriesCodeTok;
        InvtSetup.Modify(false);

        EnsureAssemblySetupNoSeries(NoSeriesCodeTok);
    end;

    local procedure EnsureAssemblySetupNoSeries(NoSeriesCode: Code[20])
    var
        AsmSetup: Record "Assembly Setup";
    begin
        if not AsmSetup.Get() then begin
            AsmSetup.Init();
            AsmSetup.Insert(false);
        end;
        AsmSetup."Assembly Order Nos." := NoSeriesCode;
        AsmSetup."Posted Assembly Order Nos." := NoSeriesCode;
        AsmSetup.Modify(false);
    end;

    local procedure EnsurePostingGroups()
    var
        GenProdGroup: Record "Gen. Product Posting Group";
        GenBusGroup: Record "Gen. Business Posting Group";
        VatProdGroup: Record "VAT Product Posting Group";
        VatBusGroup: Record "VAT Business Posting Group";
        GenPostingSetup: Record "General Posting Setup";
        VatPostingSetup: Record "VAT Posting Setup";
    begin
        EnsureCatchAllGLAccount();
        AssignCatchAllToInvtSetup();
        // Minimum posting-group skeleton for Item Journal posting on items
        // created by POSeedItems. All-zero GL accounts mean the posting
        // routines compute Value Entries without GL impact — good enough
        // for the planning-optimizer's ILE reads which are the only
        // downstream consumer of this data.
        EnsureGenProductGroup(GenProdGroup, 'POS-PROD', 'Planning Seed Product');
        EnsureGenBusinessGroup(GenBusGroup, 'POS-BUS', 'Planning Seed Business');
        EnsureVatProductGroup(VatProdGroup, 'POS-PROD', 'Planning Seed Product VAT');
        EnsureVatBusinessGroup(VatBusGroup, 'POS-BUS', 'Planning Seed Business VAT');
        EnsureGenPostingSetup(GenPostingSetup, 'POS-BUS', 'POS-PROD');
        EnsureVatPostingSetup(VatPostingSetup, 'POS-BUS', 'POS-PROD');
        // Empty-Gen-Bus row too: Item Journal lines (Positive Adjmt / Sale)
        // have no customer/vendor and default Gen. Bus. Posting Group to ''.
        // BC's posting routine looks up General Posting Setup by both keys.
        EnsureGenPostingSetup(GenPostingSetup, '', 'POS-PROD');
        EnsureVatPostingSetup(VatPostingSetup, '', 'POS-PROD');
    end;

    local procedure EnsureCatchAllGLAccount()
    var
        GLAccount: Record "G/L Account";
    begin
        // Single catch-all G/L Account for every Inventory Posting Setup
        // slot. The planning-optimizer's BC reads (ILE only) ignore GL,
        // so the actual account category/posting flow doesn't matter —
        // it just has to exist so Item Jnl.-Post Line's Value Entry
        // creation doesn't complain.
        if GLAccount.Get('POS-CATCHALL') then exit;
        GLAccount.Init();
        GLAccount."No." := 'POS-CATCHALL';
        GLAccount.Name := 'Planning Seed Catch-All';
        GLAccount."Account Type" := GLAccount."Account Type"::Posting;
        GLAccount."Direct Posting" := true;
        GLAccount."Gen. Posting Type" := GLAccount."Gen. Posting Type"::" ";
        GLAccount.Insert(false);
    end;

    local procedure AssignCatchAllToInvtSetup()
    var
        InvtSetup: Record "Inventory Posting Setup";
        Constants: Codeunit "PO Seed Constants";
    begin
        // In-Transit InvtSetup row — Transfer shipment routes ILE through
        // here. Created here so it exists even on re-publish (items don't
        // re-run their EnsureInventoryPostingSetupFor when already present).
        EnsureInTransitInvtSetupRow(InvtSetup, Constants.LocationInTransitCode());

        // Every Inventory Posting Setup row needs an Inventory Account.
        // We populate all rows with our catch-all G/L account.
        if not InvtSetup.FindSet(true) then exit;
        repeat
            InvtSetup."Inventory Account" := 'POS-CATCHALL';
            InvtSetup."Inventory Account (Interim)" := 'POS-CATCHALL';
            InvtSetup."WIP Account" := 'POS-CATCHALL';
            InvtSetup."Material Variance Account" := 'POS-CATCHALL';
            InvtSetup."Capacity Variance Account" := 'POS-CATCHALL';
            InvtSetup."Mfg. Overhead Variance Account" := 'POS-CATCHALL';
            InvtSetup."Cap. Overhead Variance Account" := 'POS-CATCHALL';
            InvtSetup."Subcontracted Variance Account" := 'POS-CATCHALL';
            InvtSetup.Modify(false);
        until InvtSetup.Next() = 0;
    end;

    local procedure EnsureInTransitInvtSetupRow(var InvtSetup: Record "Inventory Posting Setup"; InTransitCode: Code[10])
    begin
        if InvtSetup.Get(InTransitCode, 'POS-INV') then exit;
        InvtSetup.Init();
        InvtSetup."Location Code" := InTransitCode;
        InvtSetup."Invt. Posting Group Code" := 'POS-INV';
        InvtSetup."Inventory Account" := 'POS-CATCHALL';
        InvtSetup."Inventory Account (Interim)" := 'POS-CATCHALL';
        InvtSetup.Insert(false);
    end;

    local procedure EnsureGenProductGroup(var Rec: Record "Gen. Product Posting Group"; CodeValue: Code[20]; DescValue: Text[100])
    begin
        if Rec.Get(CodeValue) then exit;
        Rec.Init();
        Rec.Code := CodeValue;
        Rec.Description := CopyStr(DescValue, 1, MaxStrLen(Rec.Description));
        Rec.Insert(false);
    end;

    local procedure EnsureGenBusinessGroup(var Rec: Record "Gen. Business Posting Group"; CodeValue: Code[20]; DescValue: Text[100])
    begin
        if Rec.Get(CodeValue) then exit;
        Rec.Init();
        Rec.Code := CodeValue;
        Rec.Description := CopyStr(DescValue, 1, MaxStrLen(Rec.Description));
        Rec.Insert(false);
    end;

    local procedure EnsureVatProductGroup(var Rec: Record "VAT Product Posting Group"; CodeValue: Code[20]; DescValue: Text[100])
    begin
        if Rec.Get(CodeValue) then exit;
        Rec.Init();
        Rec.Code := CodeValue;
        Rec.Description := CopyStr(DescValue, 1, MaxStrLen(Rec.Description));
        Rec.Insert(false);
    end;

    local procedure EnsureVatBusinessGroup(var Rec: Record "VAT Business Posting Group"; CodeValue: Code[20]; DescValue: Text[100])
    begin
        if Rec.Get(CodeValue) then exit;
        Rec.Init();
        Rec.Code := CodeValue;
        Rec.Description := CopyStr(DescValue, 1, MaxStrLen(Rec.Description));
        Rec.Insert(false);
    end;

    local procedure EnsureGenPostingSetup(var Rec: Record "General Posting Setup"; BusCode: Code[20]; ProdCode: Code[20])
    begin
        if Rec.Get(BusCode, ProdCode) then exit;
        Rec.Init();
        Rec."Gen. Bus. Posting Group" := BusCode;
        Rec."Gen. Prod. Posting Group" := ProdCode;
        // Item Jnl.-Post Line writes Value Entries which need every GL
        // account here populated. POS-CATCHALL absorbs all of them.
        Rec."Sales Account" := 'POS-CATCHALL';
        Rec."Sales Credit Memo Account" := 'POS-CATCHALL';
        Rec."Sales Line Disc. Account" := 'POS-CATCHALL';
        Rec."Sales Inv. Disc. Account" := 'POS-CATCHALL';
        Rec."Sales Pmt. Disc. Debit Acc." := 'POS-CATCHALL';
        Rec."Sales Pmt. Disc. Credit Acc." := 'POS-CATCHALL';
        Rec."Sales Pmt. Tol. Debit Acc." := 'POS-CATCHALL';
        Rec."Sales Pmt. Tol. Credit Acc." := 'POS-CATCHALL';
        Rec."Purch. Account" := 'POS-CATCHALL';
        Rec."Purch. Credit Memo Account" := 'POS-CATCHALL';
        Rec."Purch. Line Disc. Account" := 'POS-CATCHALL';
        Rec."Purch. Inv. Disc. Account" := 'POS-CATCHALL';
        Rec."Purch. Pmt. Disc. Debit Acc." := 'POS-CATCHALL';
        Rec."Purch. Pmt. Disc. Credit Acc." := 'POS-CATCHALL';
        Rec."Purch. Pmt. Tol. Debit Acc." := 'POS-CATCHALL';
        Rec."Purch. Pmt. Tol. Credit Acc." := 'POS-CATCHALL';
        Rec."COGS Account" := 'POS-CATCHALL';
        Rec."COGS Account (Interim)" := 'POS-CATCHALL';
        Rec."Inventory Adjmt. Account" := 'POS-CATCHALL';
        Rec."Invt. Accrual Acc. (Interim)" := 'POS-CATCHALL';
        Rec."Direct Cost Applied Account" := 'POS-CATCHALL';
        Rec."Overhead Applied Account" := 'POS-CATCHALL';
        Rec."Purchase Variance Account" := 'POS-CATCHALL';
        Rec.Insert(false);
    end;

    local procedure EnsureVatPostingSetup(var Rec: Record "VAT Posting Setup"; BusCode: Code[20]; ProdCode: Code[20])
    begin
        if Rec.Get(BusCode, ProdCode) then exit;
        Rec.Init();
        Rec."VAT Bus. Posting Group" := BusCode;
        Rec."VAT Prod. Posting Group" := ProdCode;
        Rec."VAT %" := 0;
        Rec.Insert(false);
    end;

    local procedure EnsureBaseUnitOfMeasure()
    var
        UnitOfMeasure: Record "Unit of Measure";
    begin
        // Company-Initialize doesn't create Units of Measure. Items need
        // PCS as a Base UoM before any posting works.
        if UnitOfMeasure.Get('PCS') then
            exit;
        UnitOfMeasure.Init();
        UnitOfMeasure.Code := 'PCS';
        UnitOfMeasure.Description := 'Pieces';
        UnitOfMeasure.Insert(true);
    end;

    local procedure EnsureSeedSourceCode()
    var
        SourceCode: Record "Source Code";
        SourceCodeSetup: Record "Source Code Setup";
        Constants: Codeunit "PO Seed Constants";
    begin
        if not SourceCode.Get(Constants.SourceCodeTok()) then begin
            SourceCode.Init();
            SourceCode.Code := Constants.SourceCodeTok();
            SourceCode.Description := CopyStr(SeedSourceDescriptionLbl, 1, MaxStrLen(SourceCode.Description));
            SourceCode.Insert(true);
        end;
        if not SourceCodeSetup.Get() then begin
            SourceCodeSetup.Init();
            SourceCodeSetup.Insert(true);
        end;
    end;

    local procedure EnsureLocations()
    var
        Constants: Codeunit "PO Seed Constants";
    begin
        EnsureLocation(Constants.LocationBlueCode(), BlueWarehouseLbl, false);
        EnsureLocation(Constants.LocationRedCode(), RedWarehouseLbl, false);
        EnsureLocation(Constants.LocationGreenCode(), GreenWarehouseLbl, false);
        // In-Transit location required by Transfer Order shipment posting —
        // BC routes ILE Transfer entries through this location between
        // ship and receive.
        EnsureLocation(Constants.LocationInTransitCode(), 'Planning Seed In-Transit', true);
    end;

    local procedure EnsureLocation(LocationCode: Code[10]; LocationName: Text; AsInTransit: Boolean)
    var
        Location: Record Location;
    begin
        if Location.Get(LocationCode) then
            exit;
        Location.Init();
        Location.Code := LocationCode;
        Location.Name := CopyStr(LocationName, 1, MaxStrLen(Location.Name));
        Location."Use As In-Transit" := AsInTransit;
        Location.Insert(true);
    end;

    local procedure EnsureVendors(Count: Integer)
    var
        Idx: Integer;
        VendorNo: Code[20];
        VendorName: Text[100];
    begin
        for Idx := 1 to Count do begin
            VendorNo := CopyStr(StrSubstNo(VendorNoFmtLbl, Format(Idx, 3, SeedIndexFmtLbl)), 1, 20);
            VendorName := CopyStr(StrSubstNo(VendorNameFmtLbl, Idx), 1, 100);
            EnsureVendor(VendorNo, VendorName);
        end;
    end;

    local procedure EnsureVendor(VendorNo: Code[20]; VendorName: Text[100])
    var
        Vendor: Record Vendor;
    begin
        if Vendor.Get(VendorNo) then
            exit;
        EnsureVendorPostingGroup();
        Vendor.Init();
        Vendor."No." := VendorNo;
        Vendor.Name := VendorName;
        Vendor."Gen. Bus. Posting Group" := 'POS-BUS';
        Vendor."VAT Bus. Posting Group" := 'POS-BUS';
        Vendor."Vendor Posting Group" := 'POS-VEND';
        Vendor.Insert(true);
    end;

    local procedure EnsureVendorPostingGroup()
    var
        VendorPostingGroup: Record "Vendor Posting Group";
    begin
        if VendorPostingGroup.Get('POS-VEND') then exit;
        VendorPostingGroup.Init();
        VendorPostingGroup.Code := 'POS-VEND';
        VendorPostingGroup."Payables Account" := 'POS-CATCHALL';
        VendorPostingGroup.Insert(false);
    end;

    local procedure EnsureCustomers(Count: Integer)
    var
        Idx: Integer;
        CustomerNo: Code[20];
        CustomerName: Text[100];
    begin
        for Idx := 1 to Count do begin
            CustomerNo := CopyStr(StrSubstNo(CustomerNoFmtLbl, Format(Idx, 3, SeedIndexFmtLbl)), 1, 20);
            CustomerName := CopyStr(StrSubstNo(CustomerNameFmtLbl, Idx), 1, 100);
            EnsureCustomer(CustomerNo, CustomerName);
        end;
    end;

    local procedure EnsureCustomer(CustomerNo: Code[20]; CustomerName: Text[100])
    var
        Customer: Record Customer;
    begin
        if Customer.Get(CustomerNo) then
            exit;
        EnsureCustomerPostingGroup();
        Customer.Init();
        Customer."No." := CustomerNo;
        Customer.Name := CustomerName;
        Customer."Gen. Bus. Posting Group" := 'POS-BUS';
        Customer."VAT Bus. Posting Group" := 'POS-BUS';
        Customer."Customer Posting Group" := 'POS-CUST';
        Customer.Insert(true);
    end;

    local procedure EnsureCustomerPostingGroup()
    var
        CustomerPostingGroup: Record "Customer Posting Group";
    begin
        if CustomerPostingGroup.Get('POS-CUST') then exit;
        CustomerPostingGroup.Init();
        CustomerPostingGroup.Code := 'POS-CUST';
        CustomerPostingGroup."Receivables Account" := 'POS-CATCHALL';
        CustomerPostingGroup.Insert(false);
    end;
}
