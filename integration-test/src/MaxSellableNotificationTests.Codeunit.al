codeunit 50158 "Max Sellable Notif Int Tests"
{
    Subtype = Test;

    var
        Assert: Codeunit "Library Assert";
        CapturedNotificationMessage: Text;
        NotificationWasFired: Boolean;

    [Test]
    [HandlerFunctions('CaptureNotificationHandler')]
    procedure NotificationFiresWhenMaxSellableExceeded()
    var
        Item: Record Item;
        SalesLine: Record "Sales Line";
        SalesSetup: Record "Sales & Receivables Setup";
        Handler: Codeunit "Max Sellable Validate Handler";
        BCEventSource: Codeunit "BC Event Source";
        BCStockoutChecker: Codeunit "BC Stockout Checker";
        BCNotificationDispatcher: Codeunit "BC Notification Dispatcher";
        EventSource: Interface "IEventSource";
        StockoutChecker: Interface "IStockoutChecker";
        NotificationDispatcher: Interface "INotificationDispatcher";
        ItemNo: Code[20];
        DocNo: Code[20];
    begin
        // GIVEN setup with Max Sellable Warning enabled, Stockout Warning off so the
        // gate proceeds straight to Calculate without involving CU 311 here.
        if not SalesSetup.Get() then begin
            SalesSetup.Init();
            SalesSetup.Insert();
        end;
        SalesSetup."Stockout Warning" := false;
        SalesSetup."Max Sellable Warning" := true;
        SalesSetup.Modify();

        ItemNo := MakeItem(Item);
        DocNo := UniqueDocNo();

        // AND 50 base on hand, but the editing line wants 100
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 50);

        SalesLine."Document Type" := SalesLine."Document Type"::Order;
        SalesLine."Document No." := DocNo;
        SalesLine."Line No." := 10000;
        SalesLine.Type := SalesLine.Type::Item;
        SalesLine."No." := ItemNo;
        SalesLine."Shipment Date" := WorkDate();
        SalesLine.Quantity := 100;
        SalesLine."Qty. per Unit of Measure" := 1;
        SalesLine.Insert();

        EventSource := BCEventSource;
        StockoutChecker := BCStockoutChecker;
        NotificationDispatcher := BCNotificationDispatcher;

        // WHEN the validate handler runs with the real BC composition
        Handler.RunGatedFlow(SalesLine, EventSource, StockoutChecker, NotificationDispatcher);

        // THEN a notification was raised through the real NotificationLifecycleMgt path
        Assert.IsTrue(NotificationWasFired, 'BC Notification Dispatcher must raise a notification when Max Sellable < entered Qty.');
        Assert.IsTrue(StrPos(CapturedNotificationMessage, ItemNo) > 0, 'Notification message must reference the Item No.');
    end;

    [SendNotificationHandler]
    procedure CaptureNotificationHandler(var Notif: Notification): Boolean
    begin
        NotificationWasFired := true;
        CapturedNotificationMessage := Notif.Message;
        exit(true);
    end;

    local procedure MakeItem(var Item: Record Item) ItemNo: Code[20]
    begin
        ItemNo := CopyStr('MST' + Format(CurrentDateTime, 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20);
        Item.Init();
        Item."No." := ItemNo;
        Item.Insert();
    end;

    local procedure UniqueDocNo(): Code[20]
    begin
        exit(CopyStr('SO-' + Format(CurrentDateTime, 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20));
    end;

    local procedure SeedOnHand(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; PostingDate: Date; Qty: Decimal)
    var
        ILE: Record "Item Ledger Entry";
        Last: Record "Item Ledger Entry";
        NextEntryNo: Integer;
    begin
        if Last.FindLast() then
            NextEntryNo := Last."Entry No." + 1
        else
            NextEntryNo := 1;
        ILE.Init();
        ILE."Entry No." := NextEntryNo;
        ILE."Item No." := ItemNo;
        ILE."Variant Code" := VariantCode;
        ILE."Location Code" := LocationCode;
        ILE."Posting Date" := PostingDate;
        ILE.Quantity := Qty;
        ILE."Remaining Quantity" := Qty;
        ILE.Open := Qty > 0;
        ILE.Positive := Qty > 0;
        ILE.Insert();
    end;
}
