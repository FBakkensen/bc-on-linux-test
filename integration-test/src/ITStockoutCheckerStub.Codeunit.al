namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Sales.Document;

codeunit 50198 "IT Stockout Checker Stub" implements "IStockoutChecker"
{
    Access = Internal;

    procedure SalesLineWouldStockOut(var SalesLine: Record "Sales Line"): Boolean
    begin
        exit(false);
    end;
}
