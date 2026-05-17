namespace FBakkensen.BcLinuxSmoke.Tests;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Sales.Document;

codeunit 50102 "Stockout Checker Stub" implements "IStockoutChecker"
{
    Access = Internal;

    var
        StockoutHits: Boolean;

    procedure SetWouldStockOut(Hits: Boolean)
    begin
        StockoutHits := Hits;
    end;

    procedure SalesLineWouldStockOut(var SalesLine: Record "Sales Line"): Boolean
    begin
        exit(StockoutHits);
    end;
}
