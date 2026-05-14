codeunit 50103 "Notification Dispatcher Stub" implements "INotificationDispatcher"
{
    procedure Dispatch(var Notif: Notification; CallerRecID: RecordID)
    begin
        // Default stub: swallow the dispatch. Future tests will record into an in-memory list.
    end;
}
