namespace FBakkensen.BcLinuxSmoke.Seed;

using System.Environment;
using Microsoft.Foundation.Company;

codeunit 50210 "PO Seed Teardown"
{
    // Deletes both PLANOPT-CO-A and PLANOPT-CO-B via Company.Delete(true) —
    // BC's standard cascading-delete path that walks every CompanyName-filtered
    // table. Slow on large datasets (~30–60s per company at ~25k ILE rows) but
    // the only invariant-preserving path.
    //
    // Cross-company concern: Company.Delete operates on the Company table
    // (a global table, no CompanyName scope), so this can be invoked from any
    // session — typically the original Cronus context that the agent
    // bootstrapped from.
    Access = Public;

    procedure TeardownCompanies()
    var
        Constants: Codeunit "PO Seed Constants";
    begin
        DeleteCompany(Constants.CompanyA());
        DeleteCompany(Constants.CompanyB());
    end;

    local procedure DeleteCompany(CompanyName: Text[30])
    var
        Company: Record Company;
    begin
        if not Company.Get(CompanyName) then
            exit;
        Company.Delete(true);
    end;
}
