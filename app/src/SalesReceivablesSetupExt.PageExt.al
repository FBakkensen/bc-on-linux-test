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
                ToolTip = 'If enabled, BC warns when a Sales Line quantity exceeds the Max Sellable Quantity (ATP). The field becomes editable only when Stockout Warning is enabled, and is cleared automatically when Stockout Warning is turned off.';
            }
        }
    }
}
