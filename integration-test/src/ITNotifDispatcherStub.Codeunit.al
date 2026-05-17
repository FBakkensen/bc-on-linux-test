namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;

codeunit 50199 "IT Notif. Dispatcher Stub" implements "INotificationDispatcher"
{
    Access = Internal;

    procedure Dispatch(var Notif: Notification; CallerRecId: RecordId)
    begin
    end;
}
