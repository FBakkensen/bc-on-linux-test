tableextension 50000 "Sales Recv Setup Ext" extends "Sales & Receivables Setup"
{
    fields
    {
        field(50000; "Max Sellable Warning"; Boolean)
        {
            Caption = 'Max Sellable Warning';
            DataClassification = SystemMetadata;
            ToolTip = 'If enabled, BC warns when a Sales Line quantity exceeds the Max Sellable Quantity (ATP). Requires Stockout Warning to be enabled — turning Stockout Warning off automatically disables this flag.';
        }
    }
}
