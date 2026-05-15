table 50001 "Max Sellable Event Buf"
{
    Caption = 'Max Sellable Event Buffer';
    DataClassification = SystemMetadata;
    TableType = Temporary;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            DataClassification = SystemMetadata;
        }
        field(2; "Event Date"; Date)
        {
            Caption = 'Event Date';
            DataClassification = SystemMetadata;
        }
        field(3; "Signed Quantity (Base)"; Decimal)
        {
            Caption = 'Signed Quantity (Base)';
            DataClassification = SystemMetadata;
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
