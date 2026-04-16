codeunit 50100 "Smoke Math Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        SmokeMath: Codeunit "Smoke Math";

    [Test]
    procedure AddReturnsSum()
    begin
        // GIVEN two positive integers
        // WHEN we add them
        // THEN the result is their sum
        Assert.AreEqual(42, SmokeMath.Add(20, 22), 'Expected 42 when adding 20 and 22.');
    end;

    [Test]
    procedure AddHandlesNegativeInput()
    begin
        // GIVEN a positive and a negative integer
        // WHEN we add them
        // THEN the result is their sum
        Assert.AreEqual(7, SmokeMath.Add(10, -3), 'Expected 7 when adding 10 and -3.');
    end;

    [Test]
    procedure MultiplyReturnsProduct()
    begin
        // GIVEN two positive integers
        // WHEN we multiply them
        // THEN the result is their product
        Assert.AreEqual(42, SmokeMath.Multiply(6, 7), 'Expected 42 when multiplying 6 and 7.');
    end;

    [Test]
    procedure MultiplyByZeroReturnsZero()
    begin
        // GIVEN any integer and zero
        // WHEN we multiply them
        // THEN the result is zero
        Assert.AreEqual(0, SmokeMath.Multiply(99, 0), 'Expected 0 when multiplying 99 and 0.');
    end;
}
