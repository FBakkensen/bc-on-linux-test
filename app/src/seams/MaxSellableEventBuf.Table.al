namespace FBakkensen.BcLinuxSmoke;

table 50001 "Max Sellable Event Buf"
{
    Caption = 'Max Sellable Event Buffer';
    DataClassification = SystemMetadata;
    TableType = Temporary;
    Access = Public;
    Extensible = false;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            ToolTip = 'Specifies the entry number of the event in the temporary buffer.';
        }
        field(2; "Event Date"; Date)
        {
            Caption = 'Event Date';
            ToolTip = 'Specifies the date of the supply or demand event.';
        }
        field(3; "Signed Quantity (Base)"; Decimal)
        {
            Caption = 'Signed Quantity (Base)';
            ToolTip = 'Specifies the signed base-unit quantity (positive for supply, negative for demand).';
            AutoFormatType = 0;
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(ByEventDate; "Event Date")
        {
        }
    }
}
