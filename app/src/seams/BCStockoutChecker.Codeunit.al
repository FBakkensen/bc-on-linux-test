codeunit 50003 "BC Stockout Checker" implements "IStockoutChecker"
{
    procedure SalesLineWouldStockOut(var SalesLine: Record "Sales Line"): Boolean
    var
        ItemCheckAvail: Codeunit "Item-Check Avail.";
    begin
        exit(ItemCheckAvail.SalesLineShowWarning(SalesLine));
    end;
}
