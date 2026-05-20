namespace FBakkensen.BcLinuxSmoke.Seed;

codeunit 50201 "PO Seed Constants"
{
    Access = Public;

    procedure CompanyA(): Text[30]
    begin
        // CRONUS prefix required: the Cronus demo license caps non-demo
        // companies at 2 (Cronus + My Company already occupy that). Companies
        // whose name starts with "CRONUS" are treated as demo by BC and
        // bypass the limit — see the explicit error message text:
        //   "you can create a demonstration company because there is no
        //    limit on these. The demonstration company name must start with
        //    'CRONUS*'."
        exit('CRONUS-PLANOPT-A');
    end;

    procedure CompanyB(): Text[30]
    begin
        exit('CRONUS-PLANOPT-B');
    end;

    procedure RngSeedForCompany(CompanyNameValue: Text): Integer
    begin
        // Deterministic per-company seeds — each company's data is reproducible
        // independently. Different seeds across companies yield different
        // posting patterns even when Item Nos collide (the 80% item-master
        // overlap from ADR 0013).
        if CompanyNameValue = CompanyA() then
            exit(11111);
        if CompanyNameValue = CompanyB() then
            exit(22222);
        exit(33333);
    end;

    procedure HistoryMonths(): Integer
    begin
        exit(36);
    end;

    procedure RegimeChangeOffsetMonths(): Integer
    begin
        // Offset back from SEED_TODAY. T₀ = SEED_TODAY - 12 months per issue #27.
        exit(12);
    end;

    procedure StalenessDays(): Integer
    begin
        exit(14);
    end;

    procedure ItemsPerCompany(): Integer
    begin
        // ADR 0013 target is ~100. Smaller during initial bring-up so the
        // seeder completes in seconds rather than minutes. Bump as cohort
        // coverage expands.
        exit(20);
    end;

    procedure LocationBlueCode(): Code[10]
    begin
        exit('BLUE');
    end;

    procedure LocationRedCode(): Code[10]
    begin
        exit('RED');
    end;

    procedure LocationGreenCode(): Code[10]
    begin
        exit('GREEN');
    end;

    procedure LocationInTransitCode(): Code[10]
    begin
        exit('POS-XIT');
    end;

    procedure VendorCount(): Integer
    begin
        exit(5);
    end;

    procedure CustomerCount(): Integer
    begin
        exit(10);
    end;

    procedure SourceCodeTok(): Code[10]
    begin
        exit('PO-SEED');
    end;
}
