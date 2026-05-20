namespace FBakkensen.BcLinuxSmoke.Seed;

permissionset 50299 "PO Seed"
{
    Access = Public;
    Caption = 'PO Seed', MaxLength = 30;
    Assignable = true;

    Permissions =
        codeunit "PO Seed Bootstrap" = X,
        codeunit "PO Seed Companies" = X,
        codeunit "PO Seed Constants" = X,
        codeunit "PO Seed Install" = X,
        codeunit "PO Seed Demand History" = X,
        codeunit "PO Seed Items" = X,
        codeunit "PO Seed LT Samples" = X,
        codeunit "PO Seed Open Documents" = X,
        codeunit "PO Seed Regime Change" = X,
        codeunit "PO Seed Rng" = X,
        codeunit "PO Seed Stockout History" = X,
        codeunit "PO Seed Teardown" = X,
        page "PO Seed Endpoints" = X,
        table "PO Seed Trigger" = X,
        tabledata "PO Seed Trigger" = RIMD;
}
