namespace FBakkensen.BcLinuxSmoke.Seed;

table 50211 "PO Seed Trigger"
{
    Caption = 'PO Seed Trigger';
    Access = Public;
    DataPerCompany = true;
    Extensible = false;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key';
            ToolTip = 'Specifies the primary key of the single-record trigger row.';
        }
    }

    keys
    {
        key(PK; "Primary Key")
        {
            Clustered = true;
        }
    }
}
