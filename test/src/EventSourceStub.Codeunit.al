codeunit 50101 "Event Source Stub" implements "IEventSource"
{
    procedure CollectEvents(var Item: Record Item; var ExcludingSalesLine: Record "Sales Line"; var EventBuf: Record "Max Sellable Event Buf" temporary)
    begin
        // Default stub: no events. Future tests will set fixtures via a separate setter.
    end;
}
