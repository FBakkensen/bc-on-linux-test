interface "IEventSource"
{
    procedure CollectEvents(var Item: Record Item; var ExcludingSalesLine: Record "Sales Line"; var EventBuf: Record "Max Sellable Event Buf" temporary)
}
