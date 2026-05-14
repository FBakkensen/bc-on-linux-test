codeunit 50102 "Stockout Checker Stub" implements "IStockoutChecker"
{
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
