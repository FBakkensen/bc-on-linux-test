namespace FBakkensen.BcLinuxSmoke.Seed;

page 50211 "PO Seed Endpoints"
{
    // OData invocation surface for scripts/seed-company.sh. Three unbound
    // actions, each callable as:
    //
    //   POST {base}/api/fbakkensen/planningSeed/v1.0/companies({id})/poSeedEndpoints({rec-id})/Microsoft.NAV.<action>
    //
    // CreateCompanies and TeardownCompanies are global (operate on the Company
    // table); SeedSingleCompany is per-company and runs in the OData call's
    // company context — the caller controls which company that is via the URL.
    //
    // The PO Seed Trigger table is a single-record stub that exists only so
    // the API page has a real SourceTable with SystemId / SystemModifiedAt
    // (BC's API pages cannot use the Integer virtual table; PC0026 / PC0025).
    PageType = API;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningSeed';
    APIVersion = 'v1.0';
    EntityName = 'poSeedEndpoint';
    EntitySetName = 'poSeedEndpoints';
    SourceTable = "PO Seed Trigger";
    DelayedInsert = true;
    Caption = 'PO Seed Endpoints';
    Editable = false;
    ODataKeyFields = SystemId;

    layout
    {
        area(Content)
        {
            field(id; Rec.SystemId)
            {
                Caption = 'id';
                Editable = false;
            }
            field(lastModifiedDateTime; Rec.SystemModifiedAt)
            {
                Caption = 'lastModifiedDateTime';
                Editable = false;
            }
        }
    }

    [ServiceEnabled]
    procedure CreateCompanies(): Text
    var
        Bootstrap: Codeunit "PO Seed Bootstrap";
    begin
        Bootstrap.CreateCompanies();
        exit('OK');
    end;

    [ServiceEnabled]
    procedure SeedSingleCompany(seedToday: Date): Text
    var
        Companies: Codeunit "PO Seed Companies";
    begin
        Companies.SeedAll(seedToday);
        exit('OK');
    end;

    [ServiceEnabled]
    procedure TeardownCompanies(): Text
    var
        Teardown: Codeunit "PO Seed Teardown";
    begin
        Teardown.TeardownCompanies();
        exit('OK');
    end;
}
