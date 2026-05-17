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
        query "Assembly LT" = X,
        query "Item Ledger Summary" = X,
        query "Open SD Assembly Header" = X,
        query "Open SD Assembly Line" = X,
        query "Open SD Job Planning" = X,
        query "Open SD Prod Order Comp" = X,
        query "Open SD Prod Order Line" = X,
        query "Open SD Purchase" = X,
        query "Open SD Sales" = X,
        query "Open SD Service" = X,
        query "Open SD Transfer In" = X,
        query "Open SD Transfer Out" = X,
        query "Production LT" = X,
        query "Purchase Receipt LT" = X,
        query "Transfer LT" = X,
        tabledata "Max Sellable Event Buf" = RIMD,
        table "Max Sellable Event Buf" = X;
}
