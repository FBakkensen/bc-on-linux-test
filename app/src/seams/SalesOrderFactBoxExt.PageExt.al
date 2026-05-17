namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Sales.Document;

pageextension 50001 "Sales Order FactBox Ext" extends "Sales Order"
{
    layout
    {
        addlast(factboxes)
        {
            part("Max Sellable FactBox"; "Max Sellable FactBox")
            {
                ApplicationArea = Basic, Suite;
                Caption = 'Max Sellable Qty';
                Provider = SalesLines;
                SubPageLink = "Document Type" = field("Document Type"),
                              "Document No." = field("Document No."),
                              "Line No." = field("Line No.");
            }
        }
    }
}
