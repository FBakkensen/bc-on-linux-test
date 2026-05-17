namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Manufacturing.Document;

query 50010 "Open SD Prod Order Line"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Prod. Order Line" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'openSDProdOrderLine';
    EntitySetName = 'openSDProdOrderLine';
    Caption = 'Open SD Prod Order Line';

    elements
    {
        dataitem(ProdOrderLine; "Prod. Order Line")
        {
            // ADR 0001 deviation #1: include Planned + Firm Planned +
            // Released (the BC range Planned..Released — Status enum order:
            // Simulated, Planned, "Firm Planned", Released, Finished, so
            // the range hits the three middle values). Simulated and
            // Finished are excluded. Matches BCEventSource's
            // FilterLinesWithItemToPlan(Item, IncludeFirmPlanned=true).
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
