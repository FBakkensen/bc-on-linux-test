namespace FBakkensen.BcLinuxSmoke.Seed;

codeunit 50202 "PO Seed Rng"
{
    // Deterministic LCG (Park-Miller style) so the entire seed is reproducible
    // given a single starting seed. AL's built-in Randomize/Random would mostly
    // work but BC posting routines can pull from the global RNG and break
    // determinism. Owning the sequence inside this codeunit insulates the seed
    // from incidental Random() calls elsewhere in the stack.
    Access = Public;

    var
        State: BigInteger;

    procedure Init(Seed: Integer)
    begin
        if Seed <= 0 then
            State := 1
        else
            State := Seed;
    end;

    procedure NextInt(Bound: Integer): Integer
    var
        BoundedState: BigInteger;
    begin
        // Park-Miller: state = (state * 48271) mod (2^31 - 1)
        State := (State * 48271) mod 2147483647;
        if State <= 0 then
            State := 1;
        if Bound <= 0 then
            exit(0);
        BoundedState := State mod Bound;
        exit(BoundedState);  // implicit BigInteger → Integer; bounded
    end;

    procedure NextIntInRange(MinValue: Integer; MaxValue: Integer): Integer
    var
        Range: Integer;
    begin
        if MaxValue <= MinValue then
            exit(MinValue);
        Range := MaxValue - MinValue + 1;
        exit(MinValue + NextInt(Range));
    end;

    procedure NextDecimalUnit(): Decimal
    begin
        // Returns a uniform decimal in [0, 1).
        exit(NextInt(1000000) / 1000000.0);
    end;

    procedure NextBool(TrueProbability: Decimal): Boolean
    begin
        exit(NextDecimalUnit() < TrueProbability);
    end;
}
