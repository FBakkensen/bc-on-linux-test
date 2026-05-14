codeunit 50161 "Max Sellable Perf Stress"
{
    Subtype = Test;

    [Test]
    procedure StressScaleRunGatedFlowStaysSubQuadratic()
    var
        Fixture: Codeunit "Max Sellable Perf Fixture";
    begin
        // 2000 mixed events — ~40× typical. Budget is the regression envelope per
        // ADR 0004; a quadratic algorithm at this scale would land well past 60s.
        // Gated by BC_PERF_STRESS=1 via smoke.sh so local cycles stay fast.
        Fixture.MeasureRunGatedFlow(2000, 2000);
    end;
}
