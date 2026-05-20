namespace FBakkensen.BcLinuxSmoke.Seed;

codeunit 50200 "PO Seed Companies"
{
    // Per-company orchestrator. Runs IN the target company's session — the
    // OData caller routes us to that session via the URL path
    // (/companies({CO-A-id})/...). All cohort codeunits below operate on the
    // current company's data via the normal AL record API; no cross-company
    // ChangeCompany() is needed.
    //
    // Invocation flow from scripts/seed-company.sh:
    //   1. POST {Cronus}/poSeedEndpoints/CreateCompanies   → Bootstrap.CreateCompanies
    //   2. POST {CO-A}/poSeedEndpoints/SeedSingleCompany   → this codeunit's SeedAll
    //   3. POST {CO-B}/poSeedEndpoints/SeedSingleCompany   → this codeunit's SeedAll
    //
    // Per ADR 0013: SEED_TODAY is captured by the caller (the script) and
    // passed in. All cohorts derive their date math from this single anchor.
    Access = Public;

    procedure SeedAll(SeedTodayParam: Date)
    var
        Bootstrap: Codeunit "PO Seed Bootstrap";
        Items: Codeunit "PO Seed Items";
        DemandHistory: Codeunit "PO Seed Demand History";
        LTSamples: Codeunit "PO Seed LT Samples";
        OpenDocuments: Codeunit "PO Seed Open Documents";
        RegimeChange: Codeunit "PO Seed Regime Change";
        StockoutHistory: Codeunit "PO Seed Stockout History";
    begin
        // Align WORKDATE with SEED_TODAY for the duration of this session so
        // BC's default-fill logic (Expected Receipt Date copies WORKDATE,
        // posting-date validation, etc.) sees the same "today" the seed code
        // does. WORKDATE is per-session so this is scoped to the OData call.
        WorkDate(SeedTodayParam);
        Bootstrap.BootstrapWithinCompany();
        Items.SeedItems();
        DemandHistory.SeedDemandHistory(SeedTodayParam);
        LTSamples.SeedLTSamples(SeedTodayParam);
        OpenDocuments.SeedOpenDocuments(SeedTodayParam);
        RegimeChange.ApplyRegimeChange(SeedTodayParam);
        StockoutHistory.ApplyStockoutHistory(SeedTodayParam);
    end;

    procedure Teardown()
    var
        TeardownImpl: Codeunit "PO Seed Teardown";
    begin
        TeardownImpl.TeardownCompanies();
    end;
}
