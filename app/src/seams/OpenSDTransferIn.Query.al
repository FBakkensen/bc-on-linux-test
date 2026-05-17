namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Inventory.Transfer;

query 50007 "Open SD Transfer In"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Transfer Line" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'openSDTransferIn';
    EntitySetName = 'openSDTransferIn';
    Caption = 'Open SD Transfer In';

    elements
    {
        // Mirrors TransferLine.FilterLinesWithItemToPlan(Item, IsReceipt=true,
        // IsSupplyForPlanning=false). BC standard's IsReceipt=true path
        // deliberately omits the Outstanding <> 0 filter (only the
        // shipment-side has it); we mirror that so the row set matches
        // BCEventSource exactly — Python's project_transfer_in drops the
        // resulting zero-qty rows. "Derived From Line No." = 0 strips
        // planning-engine-generated child lines.
        dataitem(TransferLine; "Transfer Line")
        {
            DataItemTableFilter = "Derived From Line No." = const(0);

            column(itemNo; "Item No.")
            {
            }
            column(variantCode; "Variant Code")
            {
            }
            column(locationCode; "Transfer-to Code")
            {
            }
            column(receiptDate; "Receipt Date")
            {
            }
            column(outstandingQtyBase; "Outstanding Qty. (Base)")
            {
            }
        }
    }
}
