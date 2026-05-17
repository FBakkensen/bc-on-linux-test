namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Manufacturing.Document;

query 50011 "Open SD Prod Order Comp"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Prod. Order Component" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'openSDProdOrderComp';
    EntitySetName = 'openSDProdOrderComp';
    Caption = 'Open SD Prod Order Comp';

    elements
    {
        dataitem(ProdOrderComponent; "Prod. Order Component")
        {
            // Same ADR 0001 deviation #1 status set as Open SD Prod Order Line.
            DataItemTableFilter = Status = filter(Planned .. Released),
                                  "Remaining Qty. (Base)" = filter('<>0');

            column(itemNo; "Item No.")
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
            column(remainingQtyBase; "Remaining Qty. (Base)")
            {
            }
        }
    }
}
