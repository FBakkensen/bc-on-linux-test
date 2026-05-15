codeunit 50004 "BC Notification Dispatcher" implements "INotificationDispatcher"
{
    procedure Dispatch(var Notif: Notification; CallerRecID: RecordID)
    var
        NotifLifecycleMgt: Codeunit "Notification Lifecycle Mgt.";
    begin
        NotifLifecycleMgt.SendNotification(Notif, CallerRecID);
    end;
}
