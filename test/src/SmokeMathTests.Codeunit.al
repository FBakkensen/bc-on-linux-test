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

    [Test]
    procedure MultiplyReturnsProduct()
    var
        SmokeMath: Codeunit "Smoke Math";
    begin
        // GIVEN two positive integers
        // WHEN we multiply them
        // THEN the result is their product
        if SmokeMath.Multiply(6, 7) <> 42 then
            Error('Expected 42 when multiplying 6 and 7.');
    end;

    [Test]
    procedure MultiplyByZeroReturnsZero()
    var
        SmokeMath: Codeunit "Smoke Math";
    begin
        // GIVEN any integer and zero
        // WHEN we multiply them
        // THEN the result is zero
        if SmokeMath.Multiply(99, 0) <> 0 then
            Error('Expected 0 when multiplying 99 and 0.');
    end;
}
