namespace FBakkensen.BcLinuxSmoke.Tests;

using FBakkensen.BcLinuxSmoke;

codeunit 50103 "Notification Dispatcher Stub" implements "INotificationDispatcher"
{
    Access = Internal;

    var
        LastRecId: RecordId;
        DispatchCount: Integer;
        LastMessage: Text;

    procedure Dispatch(var Notif: Notification; CallerRecId: RecordId)
    begin
        DispatchCount += 1;
        LastMessage := Notif.Message();
        LastRecId := CallerRecId;
    end;

    procedure GetDispatchCount(): Integer
    begin
        exit(DispatchCount);
    end;
}
