namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Inventory.Availability;
using Microsoft.Sales.Document;

codeunit 50003 "BC Stockout Checker" implements "IStockoutChecker"
{
    Access = Public;

    procedure SalesLineWouldStockOut(var SalesLine: Record "Sales Line"): Boolean
    var
        ItemCheckAvail: Codeunit "Item-Check Avail.";
    begin
        exit(ItemCheckAvail.SalesLineShowWarning(SalesLine));
    end;
}
