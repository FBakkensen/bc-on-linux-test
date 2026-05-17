namespace FBakkensen.BcLinuxSmoke.Tests;

permissionset 50149 "Bc Linux Smoke Tests"
{
    Access = Public;
    Caption = 'Bc Linux Smoke Tests', MaxLength = 30;
    Assignable = true;

    Permissions =
        codeunit "Event Source Stub" = X,
        codeunit "Max Sellable Calc Tests" = X,
        codeunit "Max Sellable Handler Tests" = X,
        codeunit "Notification Dispatcher Stub" = X,
        codeunit "Stockout Checker Stub" = X;
}
