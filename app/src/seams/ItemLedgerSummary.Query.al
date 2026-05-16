query 50000 "Item Ledger Summary"
{
    QueryType = API;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'itemLedgerSummary';
    EntitySetName = 'itemLedgerSummaries';
    Caption = 'Item Ledger Summary';
    OrderBy = ascending(itemNo, variantCode, locationCode, postingDate);

    elements
    {
        dataitem(ItemLedgerEntry; "Item Ledger Entry")
        {
            column(itemNo; "Item No.")
            {
            }
            column(variantCode; "Variant Code")
            {
            }
            column(locationCode; "Location Code")
            {
            }
            column(postingDate; "Posting Date")
            {
            }
            column(quantity; Quantity)
            {
                Method = Sum;
            }
        }
    }
}
