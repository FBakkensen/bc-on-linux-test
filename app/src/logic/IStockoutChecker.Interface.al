interface "IStockoutChecker"
{
    procedure SalesLineWouldStockOut(var SalesLine: Record "Sales Line"): Boolean
}
