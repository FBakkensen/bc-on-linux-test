namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Sales.Document;

query 50005 "Open SD Sales"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Sales Line" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'openSDSales';
    EntitySetName = 'openSDSales';
    Caption = 'Open SD Sales';
    // No OrderBy: the document-type + type + outstanding filter set maps to
    // the (Document Type, Type, No., …) clustered key — SQL streams rows in
    // that order naturally. ADR 0006 / sister-extract pattern (#14): adding
    // OrderBy forces a sort temp table on a multi-million-row Sales Line.

    elements
    {
        dataitem(SalesLine; "Sales Line")
        {
            // Mirrors SalesLine.FilterLinesWithItemToPlan: Document Type ∈
            // {Order, Return Order}, Type = Item, Outstanding > 0. ADR 0001
            // inclusion list — quotes, invoices, credit memos, and blanket
            // orders are excluded server-side. Drop-shipment lines stay in;
            // BC standard doesn't strip them and the simulator wants the
            // commitment to be visible.
            DataItemTableFilter = "Document Type" = filter(Order | "Return Order"),
                                  Type = const(Item),
                                  "Outstanding Qty. (Base)" = filter('<>0');

            column(itemNo; "No.")
            {
            }
            column(variantCode; "Variant Code")
            {
            }
            column(locationCode; "Location Code")
            {
            }
            column(shipmentDate; "Shipment Date")
            {
            }
            column(outstandingQtyBase; "Outstanding Qty. (Base)")
            {
            }
            column(documentType; "Document Type")
            {
            }
        }
    }
}
