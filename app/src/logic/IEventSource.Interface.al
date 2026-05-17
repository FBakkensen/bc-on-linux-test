namespace FBakkensen.BcLinuxSmoke;

using Microsoft.Inventory.Item;
using Microsoft.Sales.Document;

interface "IEventSource"
{
    Access = Public;

    procedure CollectEvents(var Item: Record Item; var ExcludingSalesLine: Record "Sales Line"; var EventBuf: Record "Max Sellable Event Buf" temporary)
}
