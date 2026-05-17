namespace FBakkensen.BcLinuxSmoke;

using System.Environment.Configuration;

codeunit 50004 "BC Notification Dispatcher" implements "INotificationDispatcher"
{
    Access = Public;

    procedure Dispatch(var Notif: Notification; CallerRecId: RecordId)
    var
        NotifLifecycleMgt: Codeunit "Notification Lifecycle Mgt.";
    begin
        NotifLifecycleMgt.SendNotification(Notif, CallerRecId);
    end;
}
