namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Sales.Setup;

pageextension 50000 "Sales Recv Setup Page Ext" extends "Sales & Receivables Setup"
{
    layout
    {
        addafter("Stockout Warning")
        {
            field("Max Sellable Warning"; Rec."Max Sellable Warning")
            {
                ApplicationArea = Basic, Suite;
                Editable = Rec."Stockout Warning";
                ToolTip = 'Specifies whether BC warns when a Sales Line quantity exceeds the Max Sellable Quantity. Editable only when Stockout Warning is on.';
            }
        }
    }
}
