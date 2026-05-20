namespace FBakkensen.BcLinuxSmoke.Seed;

using System.Environment;
using Microsoft.Foundation.Company;
using Microsoft.Utilities;

codeunit 50212 "PO Seed Install"
{
    Subtype = Install;
    Access = Internal;
    InherentEntitlements = X;
    InherentPermissions = X;
    Permissions = tabledata "PO Seed Trigger" = RIM,
                  tabledata Company = RI;

    trigger OnInstallAppPerDatabase()
    var
        Constants: Codeunit "PO Seed Constants";
    begin
        // Create the two planning seed companies via AssistedCompanySetup
        // (BC UI's "Create New Company" wizard). Works because:
        //   1. scripts/fix-tenantid.sh patched $ndo$tenantproperty.tenantid
        //      to 'default' — without it Company.Insert fails with
        //      "Tenant numeric id must be set"
        //   2. bc-linux/sql-fts.Dockerfile bakes mssql-server-fts into the
        //      SQL image — without it Company.Insert fails with "Text
        //      optimized index cannot be created" on the per-company table
        //      schema creation
        //
        // Each company gets an empty per-company table set + standard No.
        // Series defaults. We layer setup (Posting Groups, etc.) explicitly
        // in BootstrapWithinCompany. CopyCompany from Cronus was tried but
        // exceeds publish-app.sh's 3min HTTP timeout (Cronus is too big).
        //
        // Runs ONCE per first-install of this extension version. Idempotent.
        EnsureCompanyExists(Constants.CompanyA());
        EnsureCompanyExists(Constants.CompanyB());
    end;

    trigger OnInstallAppPerCompany()
    begin
        EnsureTriggerRow();
    end;

    local procedure EnsureCompanyExists(CompanyNameToCreate: Text[30])
    var
        Company: Record Company;
        AssistedCompanySetup: Codeunit "Assisted Company Setup";
    begin
        Company.SetLoadFields(Name);
        if Company.Get(CompanyNameToCreate) then begin
            EnsureTriggerRowInCompany(CompanyNameToCreate);
            exit;
        end;
        AssistedCompanySetup.CreateNewCompany(CompanyNameToCreate);
        // OnInstallAppPerCompany only fires in companies that existed
        // BEFORE the extension's install transaction. Newly-created
        // companies need the trigger row inserted explicitly via
        // ChangeCompany. Without this, the API page's unbound actions
        // have no record to bind to and scripts/seed-company.sh can't
        // invoke SeedSingleCompany.
        EnsureTriggerRowInCompany(CompanyNameToCreate);
    end;

    local procedure EnsureTriggerRowInCompany(CompanyNameToTarget: Text[30])
    var
        SeedTrigger: Record "PO Seed Trigger";
        TriggerPrimaryKeyTok: Label 'TRIGGER', Locked = true;
    begin
        SeedTrigger.ChangeCompany(CompanyNameToTarget);
        if SeedTrigger.Get(TriggerPrimaryKeyTok) then
            exit;
        SeedTrigger.Init();
        SeedTrigger."Primary Key" := TriggerPrimaryKeyTok;
        SeedTrigger.Insert(false);
    end;

    local procedure EnsureTriggerRow()
    var
        SeedTrigger: Record "PO Seed Trigger";
        TriggerPrimaryKeyTok: Label 'TRIGGER', Locked = true;
    begin
        // Inserts the single PO Seed Trigger record on first install in each
        // company so the API page's unbound actions have a record to bind to
        // (BC's OData action URL is per-entity, not per-entity-set). Runs in
        // every company the extension lives in — Cronus, PLANOPT-CO-A, and
        // PLANOPT-CO-B all get a trigger row.
        if SeedTrigger.Get(TriggerPrimaryKeyTok) then
            exit;
        SeedTrigger.Init();
        SeedTrigger."Primary Key" := TriggerPrimaryKeyTok;
        SeedTrigger.Insert(false);
    end;
}
