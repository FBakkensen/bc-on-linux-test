namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Inventory.Transfer;

query 50008 "Open SD Transfer Out"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Transfer Line" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'openSDTransferOut';
    EntitySetName = 'openSDTransferOut';
    Caption = 'Open SD Transfer Out';

    elements
    {
        // Mirrors TransferLine.FilterLinesWithItemToPlan(Item, IsReceipt=false,
        // IsSupplyForPlanning=false). BC standard adds the Outstanding <> 0
        // filter on this path (only — the IsReceipt=true path doesn't).
        dataitem(TransferLine; "Transfer Line")
        {
            DataItemTableFilter = "Derived From Line No." = const(0),
                                  "Outstanding Qty. (Base)" = filter('<>0');

            column(itemNo; "Item No.")
            {
            }
            column(variantCode; "Variant Code")
            {
            }
            column(locationCode; "Transfer-from Code")
            {
            }
            column(shipmentDate; "Shipment Date")
            {
            }
            column(outstandingQtyBase; "Outstanding Qty. (Base)")
            {
            }
        }
    }
}
