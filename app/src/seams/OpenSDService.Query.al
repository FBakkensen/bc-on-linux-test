namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Service.Document;

query 50009 "Open SD Service"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Service Line" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'openSDService';
    EntitySetName = 'openSDService';
    Caption = 'Open SD Service';

    elements
    {
        dataitem(ServiceLine; "Service Line")
        {
            // Mirrors ServiceLine.FilterLinesWithItemToPlan: Order only
            // (no quote / invoice / credit memo), Type = Item, Outstanding
            // > 0.
            DataItemTableFilter = "Document Type" = const(Order),
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
            column(neededByDate; "Needed by Date")
            {
            }
            column(outstandingQtyBase; "Outstanding Qty. (Base)")
            {
            }
        }
    }
}
