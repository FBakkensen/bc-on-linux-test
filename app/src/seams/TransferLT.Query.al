namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Inventory.Ledger;

query 50004 "Transfer LT"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Item Ledger Entry" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'transferLT';
    EntitySetName = 'transferLT';
    Caption = 'Transfer LT';
    // No OrderBy: the Python pairing inner-merges on (document_no, item,
    // variant) and doesn't depend on row order. ILE can be 100M+ rows on
    // real tenants — sorting by document_no + posting_date forces SQL to
    // either build a sort temp table or pick a non-clustered index. We
    // let SQL stream in the ILE Entry No. clustered key instead, which
    // is the cheapest scan.

    elements
    {
        // ADR 0006: transfer LT pairs ILE Transfer source (Quantity < 0,
        // source location) with ILE Transfer destination (Quantity > 0,
        // destination location), matched by Document No. + Item + Variant.
        // The Python parser does the pairing; here we just expose every
        // Entry Type = Transfer row. Unmatched in-flight transfers are
        // excluded at parse time, not server-side, so the seam stays
        // tolerant of mid-cycle extracts.
        dataitem(ILE; "Item Ledger Entry")
        {
            DataItemTableFilter = "Entry Type" = const(Transfer);

            column(documentNo; "Document No.")
            {
            }
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
            }
        }
    }
}
