namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Purchases.Document;

query 50006 "Open SD Purchase"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Purchase Line" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'openSDPurchase';
    EntitySetName = 'openSDPurchase';
    Caption = 'Open SD Purchase';

    elements
    {
        dataitem(PurchaseLine; "Purchase Line")
        {
            // Mirrors PurchaseLine.FilterLinesWithItemToPlan. ADR 0001:
            // quotes, invoices, credit memos, and blanket orders excluded.
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
            column(expectedReceiptDate; "Expected Receipt Date")
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
