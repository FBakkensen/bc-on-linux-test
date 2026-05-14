codeunit 50102 "Stockout Checker Stub" implements "IStockoutChecker"
{
    procedure SalesLineWouldStockOut(var SalesLine: Record "Sales Line"): Boolean
    begin
        // Default stub: CU 311 reports no stockout. Future tests will set the pass/fail.
        exit(false);
    end;
}
