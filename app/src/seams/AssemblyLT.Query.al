namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Assembly.History;

query 50003 "Assembly LT"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Posted Assembly Header" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'assemblyLT';
    EntitySetName = 'assemblyLT';
    Caption = 'Assembly LT';
    OrderBy = ascending(itemNo, variantCode, locationCode, postingDate);

    elements
    {
        // Posted Assembly Header is the BC representation of a finished
        // assembly order — it only exists after posting, so no in-flight
        // assemblies leak through. ADR 0006: LT = Posting Date − Starting
        // Date, derived Python-side from these two columns.
        dataitem(PostedAsmHeader; "Posted Assembly Header")
        {
            column(assemblyDocNo; "No.")
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
            column(startingDate; "Starting Date")
            {
            }
            column(postingDate; "Posting Date")
            {
            }
        }
    }
}
