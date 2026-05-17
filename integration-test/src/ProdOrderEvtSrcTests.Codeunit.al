namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Manufacturing.Document;
using Microsoft.Sales.Document;
using System.TestLibraries.Utilities;

codeunit 50155 "Prod Order Evt Src Tests"
{
    Subtype = Test;
    Access = Internal;
    Permissions = tabledata Item = I,
                  tabledata "Item Ledger Entry" = RI,
                  tabledata "Prod. Order Component" = I,
                  tabledata "Prod. Order Line" = I;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure ReleasedProdOrderLineRaisesMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertProdOrderLine("Production Order Status"::Released, UniqueDocNo(), 10000, ItemNo, '', '', WorkDate() + 2, 25);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(125, Result, 'A Released Production Order Line must raise Max Sellable on its Due Date.');
    end;

    [Test]
    procedure FirmPlannedProdOrderLineRaisesMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertProdOrderLine("Production Order Status"::"Firm Planned", UniqueDocNo(), 10000, ItemNo, '', '', WorkDate() + 2, 25);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(125, Result, 'A Firm Planned Production Order Line must raise Max Sellable.');
    end;

    [Test]
    procedure PlannedProdOrderLineRaisesMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        // ADR 0001 deviation #1: include Planned status (matches Qty. on Prod. Order FlowField,
        // not the narrower Scheduled Receipt view). This test pins the deviation in place.
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertProdOrderLine("Production Order Status"::Planned, UniqueDocNo(), 10000, ItemNo, '', '', WorkDate() + 2, 25);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(125, Result, 'ADR 0001 deviation #1: Planned Production Order Lines must raise Max Sellable.');
    end;

    [Test]
    procedure SimulatedProdOrderLineDoesNotAffectMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertProdOrderLine("Production Order Status"::Simulated, UniqueDocNo(), 10000, ItemNo, '', '', WorkDate() + 2, 999);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(100, Result, 'A Simulated Production Order Line must not affect Max Sellable.');
    end;

    [Test]
    procedure FinishedProdOrderLineDoesNotAffectMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertProdOrderLine("Production Order Status"::Finished, UniqueDocNo(), 10000, ItemNo, '', '', WorkDate() + 2, 999);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(100, Result, 'A Finished Production Order Line must not affect Max Sellable.');
    end;

    [Test]
    procedure ReleasedProdOrderComponentLowersMaxSellable()
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Decimal;
    begin
        ItemNo := MakeItem(Item);
        SeedOnHand(ItemNo, '', '', WorkDate() - 5, 100);
        InsertProdOrderComponent("Production Order Status"::Released, UniqueDocNo(), 10000, 10000, ItemNo, '', '', WorkDate() + 2, 30);

        Result := RunCalculate(ItemNo, '', '', WorkDate());

        Assert.AreEqual(70, Result, 'A Released Production Order Component must lower Max Sellable on its Due Date.');
    end;

    local procedure MakeItem(var Item: Record Item) ItemNo: Code[20]
    begin
        ItemNo := CopyStr('MST' + Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20);
        Item.Init();
        Item."No." := ItemNo;
        Item.Insert(false);
    end;

    local procedure UniqueDocNo(): Code[20]
    begin
        exit(CopyStr('PRO-' + Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(9999)), 1, 20));
    end;

    local procedure SeedOnHand(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; PostingDate: Date; Qty: Decimal)
    var
        ILE: Record "Item Ledger Entry";
        Last: Record "Item Ledger Entry";
        NextEntryNo: Integer;
    begin
        Last.SetLoadFields("Entry No.");
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
        ILE.Insert(false);
    end;

    local procedure InsertProdOrderLine(Status: Enum "Production Order Status"; DocNo: Code[20]; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; DueDate: Date; RemainingQtyBase: Decimal)
    var
        ProdOrderLine: Record "Prod. Order Line";
    begin
        ProdOrderLine.Init();
        ProdOrderLine.Status := Status;
        ProdOrderLine."Prod. Order No." := DocNo;
        ProdOrderLine."Line No." := LineNo;
        ProdOrderLine."Item No." := ItemNo;
        ProdOrderLine."Variant Code" := VariantCode;
        ProdOrderLine."Location Code" := LocationCode;
        ProdOrderLine."Due Date" := DueDate;
        ProdOrderLine.Quantity := RemainingQtyBase;
        ProdOrderLine."Quantity (Base)" := RemainingQtyBase;
        ProdOrderLine."Remaining Quantity" := RemainingQtyBase;
        ProdOrderLine."Remaining Qty. (Base)" := RemainingQtyBase;
        ProdOrderLine."Qty. per Unit of Measure" := 1;
        ProdOrderLine.Insert(false);
    end;

    local procedure InsertProdOrderComponent(Status: Enum "Production Order Status"; DocNo: Code[20]; ProdOrderLineNo: Integer; LineNo: Integer; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; DueDate: Date; RemainingQtyBase: Decimal)
    var
        ProdOrderComp: Record "Prod. Order Component";
    begin
        ProdOrderComp.Init();
        ProdOrderComp.Status := Status;
        ProdOrderComp."Prod. Order No." := DocNo;
        ProdOrderComp."Prod. Order Line No." := ProdOrderLineNo;
        ProdOrderComp."Line No." := LineNo;
        ProdOrderComp."Item No." := ItemNo;
        ProdOrderComp."Variant Code" := VariantCode;
        ProdOrderComp."Location Code" := LocationCode;
        ProdOrderComp."Due Date" := DueDate;
        ProdOrderComp."Quantity (Base)" := RemainingQtyBase;
        ProdOrderComp."Remaining Quantity" := RemainingQtyBase;
        ProdOrderComp."Remaining Qty. (Base)" := RemainingQtyBase;
        ProdOrderComp."Qty. per Unit of Measure" := 1;
        ProdOrderComp.Insert(false);
    end;

    local procedure RunCalculate(ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; ShipmentDate: Date): Decimal
    var
        ExcludingSalesLine: Record "Sales Line";
        MaxSellableCalc: Codeunit "Max Sellable Calc";
        BCEventSource: Codeunit "BC Event Source";
        EventSource: Interface "IEventSource";
    begin
        EventSource := BCEventSource;
        exit(MaxSellableCalc.Calculate(
            ItemNo, VariantCode, LocationCode, ShipmentDate, ExcludingSalesLine,
            EventSource));
    end;
}
