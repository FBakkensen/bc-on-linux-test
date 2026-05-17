namespace FBakkensen.BcLinuxSmoke;

permissionset 50049 "Bc Linux Smoke"
{
    Access = Public;
    Caption = 'Bc Linux Smoke', MaxLength = 30;
    Assignable = true;

    Permissions =
        codeunit "BC Event Source" = X,
        codeunit "BC Notification Dispatcher" = X,
        codeunit "BC Stockout Checker" = X,
        codeunit "Max Sellable Calc" = X,
        codeunit "Max Sellable PBT" = X,
        codeunit "Max Sellable Subscribers" = X,
        codeunit "Max Sellable Validate Handler" = X,
        page "Max Sellable FactBox" = X,
        query "Item Ledger Summary" = X,
        query "Purchase Receipt LT" = X,
        tabledata "Max Sellable Event Buf" = RIMD,
        table "Max Sellable Event Buf" = X;
}
