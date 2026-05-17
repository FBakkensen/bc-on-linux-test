namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Sales.Setup;

tableextension 50000 "Sales Recv Setup Ext" extends "Sales & Receivables Setup"
{
    fields
    {
        field(50000; "Max Sellable Warning"; Boolean)
        {
            Caption = 'Max Sellable Warning';
            DataClassification = SystemMetadata;
            ToolTip = 'Specifies whether BC warns when a Sales Line quantity exceeds the Max Sellable Quantity. Requires Stockout Warning to be enabled.';
        }
    }
}
