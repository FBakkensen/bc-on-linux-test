namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Projects.Project.Planning;

query 50014 "Open SD Job Planning"
{
    QueryType = API;
    Access = Public;
    Permissions = tabledata "Job Planning Line" = R;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'openSDJobPlanning';
    EntitySetName = 'openSDJobPlanning';
    Caption = 'Open SD Job Planning';

    elements
    {
        dataitem(JobPlanningLine; "Job Planning Line")
        {
            // Mirrors JobPlanningLine.FilterLinesWithItemToPlan: Status =
            // Order, Type = Item, Remaining > 0. ADR 0001 deviation #3
            // (Job line double-count for Both Budget and Billable) lives
            // Python-side because a single SELECT can't emit a row twice;
            // the lineType column lets project_job_planning do the
            // duplication.
            DataItemTableFilter = Status = const(Order),
                                  Type = const(Item),
                                  "Remaining Qty. (Base)" = filter('<>0');

            column(itemNo; "No.")
            {
            }
            column(variantCode; "Variant Code")
            {
            }
            column(locationCode; "Location Code")
            {
            }
            column(planningDate; "Planning Date")
            {
            }
            column(remainingQtyBase; "Remaining Qty. (Base)")
            {
            }
            column(lineType; "Line Type")
            {
            }
        }
    }
}
