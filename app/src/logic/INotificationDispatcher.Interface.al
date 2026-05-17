namespace FBakkensen.BcLinuxSmoke;

interface "INotificationDispatcher"
{
    Access = Public;

    procedure Dispatch(var Notif: Notification; CallerRecId: RecordId)
}
