namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Inventory.Ledger;
using Microsoft.Manufacturing.Document;

query 50002 "Production LT"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Production Order" = R,
                  tabledata "Item Ledger Entry" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'productionLT';
    EntitySetName = 'productionLT';
    Caption = 'Production LT';
    // No OrderBy: Python groupby on prod_order_no doesn't depend on row
    // order, so we let SQL stream in the Production Order clustered-key
    // order (Status, "No."). With Status filtered to a constant
    // server-side, that's a Key1 range scan — the cheapest possible plan.

    elements
    {
        dataitem(ProdOrderHeader; "Production Order")
        {
            // Only finished prod orders carry historical truth — cancelled
            // / scrapped orders (Status never reached Finished) are excluded
            // server-side per ADR 0006.
            DataItemTableFilter = Status = const(Finished);

            column(prodOrderNo; "No.")
            {
            }
            column(prodOrderStartingDate; "Starting Date")
            {
            }
            // BC's "Finished Date" is the order's actual finish marker —
            // the issue spec calls this "Finishing Date". When no ILE
            // Consumption exists (raw extraction, no BOM), the Python
            // parser falls back to (Finished − Starting).
            column(prodOrderFinishingDate; "Finished Date")
            {
            }
            column(prodOrderEndingDate; "Ending Date")
            {
            }

            dataitem(ILE; "Item Ledger Entry")
            {
                DataItemLink = "Order No." = ProdOrderHeader."No.";
                SqlJoinType = InnerJoin;
                // "Order Type" guards against false matches when a sales /
                // service / transfer order happens to share a No. with a
                // prod order — without it, ILE rows from other order types
                // could leak in. ADR 0006 limits production LT to Output
                // and Consumption ILE.
                DataItemTableFilter = "Order Type" = const(Production),
                                      "Entry Type" = filter(Output | Consumption);

                column(itemNo; "Item No.")
                {
                }
                column(variantCode; "Variant Code")
                {
                }
                column(locationCode; "Location Code")
                {
                }
                column(entryKind; "Entry Type")
                {
                }
                column(postingDate; "Posting Date")
                {
                }
            }
        }
    }
}
