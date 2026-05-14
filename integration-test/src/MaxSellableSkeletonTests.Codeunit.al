codeunit 50150 "Max Sellable Skeleton Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure IntegrationAppPublishedAndRuns()
    begin
        // GIVEN this codeunit was published into BC alongside the production app
        // WHEN the test framework dispatches it
        // THEN it runs to completion — proves the integration-test pipeline is alive
        Assert.AreEqual(2, 1 + 1, 'Integration test pipeline reached this codeunit.');
    end;
}
