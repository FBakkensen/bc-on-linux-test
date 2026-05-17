namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Sales.Document;

interface "IStockoutChecker"
{
    Access = Public;

    procedure SalesLineWouldStockOut(var SalesLine: Record "Sales Line"): Boolean
}
