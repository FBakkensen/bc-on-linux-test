namespace FBakkensen.BcLinuxSmoke.IT;

permissionset 50199 "Bc Linux Smoke IT"
{
    Access = Public;
    Caption = 'Bc Linux Smoke IT', MaxLength = 30;
    Assignable = true;

    Permissions =
        codeunit "Assembly Evt Src Tests" = X,
        codeunit "Assembly LT Query Tests" = X,
        codeunit "ILE Summary Query Tests" = X,
        codeunit "IT Notif. Dispatcher Stub" = X,
        codeunit "IT Stockout Checker Stub" = X,
        codeunit "Job Planning Evt Src Tests" = X,
        codeunit "Max Sellable FactBox Tests" = X,
        codeunit "Max Sellable Notif Int Tests" = X,
        codeunit "Max Sellable Perf Fixture" = X,
        codeunit "Max Sellable Perf Typical" = X,
        codeunit "Max Sellable Skeleton Tests" = X,
        codeunit "Open SD Query Tests" = X,
        codeunit "Prod Order Evt Src Tests" = X,
        codeunit "Production LT Query Tests" = X,
        codeunit "Purch Line Evt Src Tests" = X,
        codeunit "Purch Receipt LT Query Tests" = X,
        codeunit "Sales Line Evt Src Tests" = X,
        codeunit "Service Line Evt Src Tests" = X,
        codeunit "Transfer Line Evt Src Tests" = X,
        codeunit "Transfer LT Query Tests" = X;
}
