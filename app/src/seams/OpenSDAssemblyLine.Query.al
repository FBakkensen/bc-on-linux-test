namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Assembly.Document;

query 50013 "Open SD Assembly Line"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Assembly Line" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'openSDAssemblyLine';
    EntitySetName = 'openSDAssemblyLine';
    Caption = 'Open SD Assembly Line';

    elements
    {
        dataitem(AssemblyLine; "Assembly Line")
        {
            // ADR 0001 deviation #2: Document Type = Order only. Blanket
            // assembly lines excluded for symmetry with the header.
            DataItemTableFilter = "Document Type" = const(Order),
                                  Type = const(Item),
                                  "Remaining Quantity (Base)" = filter('<>0');

            column(itemNo; "No.")
            {
            }
            column(variantCode; "Variant Code")
            {
            }
            column(locationCode; "Location Code")
            {
            }
            column(dueDate; "Due Date")
            {
            }
            column(remainingQtyBase; "Remaining Quantity (Base)")
            {
            }
        }
    }
}
