namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Assembly.Document;

query 50012 "Open SD Assembly Header"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Assembly Header" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'openSDAssemblyHeader';
    EntitySetName = 'openSDAssemblyHeader';
    Caption = 'Open SD Assembly Header';

    elements
    {
        dataitem(AssemblyHeader; "Assembly Header")
        {
            // ADR 0001 deviation #2: Document Type = Order only. Blanket
            // assembly headers are excluded — we follow the Qty. on Asm.
            // Order FlowField, not CU 99000854's special-case for blanket
            // components.
            DataItemTableFilter = "Document Type" = const(Order),
                                  "Remaining Quantity (Base)" = filter('<>0');

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
            column(remainingQtyBase; "Remaining Quantity (Base)")
            {
            }
        }
    }
}
