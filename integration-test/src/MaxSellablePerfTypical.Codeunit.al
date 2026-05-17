namespace FBakkensen.BcLinuxSmoke.IT;

codeunit 50160 "Max Sellable Perf Typical"
{
    Subtype = Test;
    Access = Internal;

    [Test]
    procedure TypicalScaleRunGatedFlowFitsTypingBudget()
    var
        Fixture: Codeunit "Max Sellable Perf Fixture";
    begin
        // 50 mixed events spread across all six sources — representative of a busy SKU
        // at one warehouse. Budget is the typing-SLA envelope per ADR 0004; failures
        // surface the 5 measured timings in the Error message.
        Fixture.MeasureRunGatedFlow(50, 300);
    end;
}
