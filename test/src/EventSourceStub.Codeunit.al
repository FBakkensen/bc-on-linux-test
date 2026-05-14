codeunit 50101 "Event Source Stub" implements "IEventSource"
{
    var
        FixtureDates: List of [Date];
        FixtureQtys: List of [Decimal];
        FixtureFromLineNos: List of [Integer];

    procedure AddEvent(EventDate: Date; SignedQtyBase: Decimal)
    begin
        AddEventFromLine(EventDate, SignedQtyBase, 0);
    end;

    procedure AddEventFromLine(EventDate: Date; SignedQtyBase: Decimal; FromLineNo: Integer)
    begin
        FixtureDates.Add(EventDate);
        FixtureQtys.Add(SignedQtyBase);
        FixtureFromLineNos.Add(FromLineNo);
    end;

    procedure CollectEvents(var Item: Record Item; var ExcludingSalesLine: Record "Sales Line"; var EventBuf: Record "Max Sellable Event Buf" temporary)
    var
        i: Integer;
        FromLineNo: Integer;
    begin
        for i := 1 to FixtureDates.Count() do begin
            FromLineNo := FixtureFromLineNos.Get(i);
            if (FromLineNo = 0) or (FromLineNo <> ExcludingSalesLine."Line No.") then begin
                EventBuf.Init();
                EventBuf."Entry No." := EventBuf.Count() + 1;
                EventBuf."Event Date" := FixtureDates.Get(i);
                EventBuf."Signed Quantity (Base)" := FixtureQtys.Get(i);
                EventBuf.Insert();
            end;
        end;
    end;
}
