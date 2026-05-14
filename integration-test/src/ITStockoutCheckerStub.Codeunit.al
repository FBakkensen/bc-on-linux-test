codeunit 50198 "IT Stockout Checker Stub" implements "IStockoutChecker"
{
    procedure SalesLineWouldStockOut(var SalesLine: Record "Sales Line"): Boolean
    begin
        exit(false);
    end;
}
