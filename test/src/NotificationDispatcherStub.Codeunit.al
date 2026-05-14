codeunit 50103 "Notification Dispatcher Stub" implements "INotificationDispatcher"
{
    var
        DispatchCount: Integer;
        LastMessage: Text;
        LastRecId: RecordId;

    procedure Dispatch(var Notif: Notification; CallerRecID: RecordID)
    begin
        DispatchCount += 1;
        LastMessage := Notif.Message;
        LastRecId := CallerRecID;
    end;

    procedure GetDispatchCount(): Integer
    begin
        exit(DispatchCount);
    end;

    procedure GetLastMessage(): Text
    begin
        exit(LastMessage);
    end;

    procedure GetLastRecId(): RecordId
    begin
        exit(LastRecId);
    end;
}
