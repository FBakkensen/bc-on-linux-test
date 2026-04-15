codeunit 50100 "Smoke Math Tests"
{
    Subtype = Test;

    [Test]
    procedure AddReturnsSum()
    var
        SmokeMath: Codeunit "Smoke Math";
    begin
        if SmokeMath.Add(20, 22) <> 42 then
            Error('Expected 42 when adding 20 and 22.');
    end;

    [Test]
    procedure AddHandlesNegativeInput()
    var
        SmokeMath: Codeunit "Smoke Math";
    begin
        if SmokeMath.Add(10, -3) <> 7 then
            Error('Expected 7 when adding 10 and -3.');
    end;
}
