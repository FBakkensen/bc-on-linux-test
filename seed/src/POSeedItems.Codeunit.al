namespace FBakkensen.BcLinuxSmoke.Seed;

using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Finance.VAT.Setup;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Setup;
using Microsoft.Manufacturing.Setup;

codeunit 50204 "PO Seed Items"
{
    Access = Public;
    Permissions = tabledata Item = RI,
                  tabledata "Item Unit of Measure" = RI,
                  tabledata "Inventory Posting Group" = RI,
                  tabledata "Inventory Posting Setup" = RI,
                  tabledata "Gen. Product Posting Group" = R,
                  tabledata "VAT Product Posting Group" = R;

    var
        ItemNoFmtLbl: Label 'POS-I%1', Comment = '%1 = item index padded to 4 digits', Locked = true;
        ItemDescFmtLbl: Label 'Seed Item %1', Comment = '%1 = item index';
        ItemIdxFmtLbl: Label '<Integer,4><Filler Character,0>', Locked = true;
        SeedInvPostingGroupCodeTok: Label 'POS-INV', Locked = true;
        SeedInvPostingGroupDescriptionLbl: Label 'Planning Optimizer Seed Inventory';
        ThreeDaysTok: Label '<3D>', Locked = true;
        OneWeekTok: Label '<1W>', Locked = true;

    procedure SeedItems()
    var
        Constants: Codeunit "PO Seed Constants";
        Idx: Integer;
    begin
        for Idx := 1 to Constants.ItemsPerCompany() do
            EnsureItem(Idx);
    end;

    local procedure EnsureItem(ItemIndex: Integer)
    var
        Item: Record Item;
        ItemNo: Code[20];
    begin
        ItemNo := BuildItemNo(ItemIndex);
        if Item.Get(ItemNo) then
            exit;
        Item.Init();
        Item."No." := ItemNo;
        Item.Description := CopyStr(StrSubstNo(ItemDescFmtLbl, ItemIndex), 1, MaxStrLen(Item.Description));
        Item.Type := Item.Type::Inventory;
        EnsureItemUnitOfMeasure(ItemNo, 'PCS');
        Item."Base Unit of Measure" := 'PCS';
        Item."Unit Cost" := UnitCostForIndex(ItemIndex);
        Item."Unit Price" := UnitPriceForIndex(ItemIndex);
        Item."Replenishment System" := ReplenishmentSystemForIndex(ItemIndex);
        Item."Manufacturing Policy" := ManufacturingPolicyForIndex(ItemIndex);
        Item."Reordering Policy" := ReorderingPolicyForIndex(ItemIndex);
        AssignPlanningFieldsForClass(Item, ItemIndex);
        AssignConstraintFields(Item, ItemIndex);
        AssignPostingGroups(Item);
        Item.Insert(true);
        EnsureInventoryPostingSetupFor(Item."Inventory Posting Group");
    end;

    local procedure EnsureItemUnitOfMeasure(ItemNo: Code[20]; UoMCode: Code[10])
    var
        ItemUnitOfMeasure: Record "Item Unit of Measure";
    begin
        if ItemUnitOfMeasure.Get(ItemNo, UoMCode) then
            exit;
        ItemUnitOfMeasure.Init();
        ItemUnitOfMeasure."Item No." := ItemNo;
        ItemUnitOfMeasure.Code := UoMCode;
        ItemUnitOfMeasure."Qty. per Unit of Measure" := 1;
        ItemUnitOfMeasure.Insert(false);
    end;

    local procedure BuildItemNo(ItemIndex: Integer): Code[20]
    begin
        exit(CopyStr(StrSubstNo(ItemNoFmtLbl, Format(ItemIndex, 4, ItemIdxFmtLbl)), 1, 20));
    end;

    local procedure AbcClassForIndex(ItemIndex: Integer): Integer
    begin
        exit(ItemIndex mod 4);
    end;

    local procedure UnitCostForIndex(ItemIndex: Integer): Decimal
    begin
        case AbcClassForIndex(ItemIndex) of
            0:
                exit(500);
            1:
                exit(50);
            2:
                exit(5);
        end;
        exit(2);
    end;

    local procedure UnitPriceForIndex(ItemIndex: Integer): Decimal
    begin
        case AbcClassForIndex(ItemIndex) of
            0:
                exit(1000);
            1:
                exit(120);
            2:
                exit(12);
        end;
        exit(5);
    end;

    local procedure ReplenishmentSystemForIndex(ItemIndex: Integer): Enum "Replenishment System"
    begin
        case ItemIndex mod 5 of
            3:
                exit("Replenishment System"::"Prod. Order");
            4:
                exit("Replenishment System"::Assembly);
        end;
        exit("Replenishment System"::Purchase);
    end;

    local procedure ManufacturingPolicyForIndex(ItemIndex: Integer): Enum "Manufacturing Policy"
    begin
        if ItemIndex mod 7 = 0 then
            exit("Manufacturing Policy"::"Make-to-Order");
        exit("Manufacturing Policy"::"Make-to-Stock");
    end;

    local procedure ReorderingPolicyForIndex(ItemIndex: Integer): Enum "Reordering Policy"
    begin
        case ItemIndex mod 5 of
            1:
                exit("Reordering Policy"::"Fixed Reorder Qty.");
            2:
                exit("Reordering Policy"::"Maximum Qty.");
            3:
                exit("Reordering Policy"::"Lot-for-Lot");
            4:
                exit("Reordering Policy"::Order);
        end;
        exit("Reordering Policy"::" ");
    end;

    local procedure AssignPlanningFieldsForClass(var Item: Record Item; ItemIndex: Integer)
    begin
        case AbcClassForIndex(ItemIndex) of
            0:
                AssignAClassPlanningFields(Item);
            1:
                AssignBClassPlanningFields(Item);
            2:
                AssignCClassPlanningFields(Item);
        end;
    end;

    local procedure AssignAClassPlanningFields(var Item: Record Item)
    begin
        Item."Reorder Point" := 50;
        Item."Reorder Quantity" := 100;
        Item."Safety Stock Quantity" := 10;
        Item."Maximum Inventory" := 200;
    end;

    local procedure AssignBClassPlanningFields(var Item: Record Item)
    begin
        Item."Reorder Point" := 20;
        Item."Reorder Quantity" := 50;
        Item."Safety Stock Quantity" := 5;
        Item."Maximum Inventory" := 100;
    end;

    local procedure AssignCClassPlanningFields(var Item: Record Item)
    begin
        Item."Reorder Point" := 5;
        Item."Reorder Quantity" := 25;
        Item."Safety Stock Quantity" := 2;
        Item."Maximum Inventory" := 50;
    end;

    local procedure AssignConstraintFields(var Item: Record Item; ItemIndex: Integer)
    begin
        if ItemIndex mod 3 = 0 then
            Item."Order Multiple" := 5;
        if ItemIndex mod 6 = 0 then
            Item."Minimum Order Quantity" := 15;
        if ItemIndex mod 8 = 0 then
            Item."Maximum Order Quantity" := 500;
        if ItemIndex mod 4 = 0 then
            Evaluate(Item."Safety Lead Time", ThreeDaysTok);
        if Item."Reordering Policy" = Item."Reordering Policy"::"Lot-for-Lot" then
            Evaluate(Item."Lot Accumulation Period", OneWeekTok);
        // Lead Time Calculation is required by Refresh Production Order
        // (it computes Starting Date = Due Date - Lead Time). Without it,
        // Refresh leaves dates blank and ChangeProdOrderStatus fails.
        case Item."Replenishment System" of
            Item."Replenishment System"::"Prod. Order",
            Item."Replenishment System"::Assembly:
                Evaluate(Item."Lead Time Calculation", OneWeekTok);
        end;
    end;

    local procedure AssignPostingGroups(var Item: Record Item)
    var
        InventoryPostingGroup: Record "Inventory Posting Group";
    begin
        if InventoryPostingGroup.FindFirst() then
            Item."Inventory Posting Group" := InventoryPostingGroup.Code
        else begin
            InventoryPostingGroup.Init();
            InventoryPostingGroup.Code := SeedInvPostingGroupCodeTok;
            InventoryPostingGroup.Description := CopyStr(SeedInvPostingGroupDescriptionLbl, 1, MaxStrLen(InventoryPostingGroup.Description));
            InventoryPostingGroup.Insert(true);
            Item."Inventory Posting Group" := InventoryPostingGroup.Code;
        end;
        // Created in POSeedBootstrap.EnsurePostingGroups.
        Item."Gen. Prod. Posting Group" := 'POS-PROD';
        Item."VAT Prod. Posting Group" := 'POS-PROD';
    end;

    local procedure EnsureInventoryPostingSetupFor(GroupCode: Code[20])
    var
        InventoryPostingSetup: Record "Inventory Posting Setup";
        Constants: Codeunit "PO Seed Constants";
    begin
        EnsureInventoryPostingSetupRow(InventoryPostingSetup, Constants.LocationBlueCode(), GroupCode);
        EnsureInventoryPostingSetupRow(InventoryPostingSetup, Constants.LocationRedCode(), GroupCode);
        EnsureInventoryPostingSetupRow(InventoryPostingSetup, Constants.LocationGreenCode(), GroupCode);
        // In-Transit location too — Transfer shipment posts ILE through it.
        EnsureInventoryPostingSetupRow(InventoryPostingSetup, Constants.LocationInTransitCode(), GroupCode);
    end;

    local procedure EnsureInventoryPostingSetupRow(var InventoryPostingSetup: Record "Inventory Posting Setup"; LocationCode: Code[10]; GroupCode: Code[20])
    begin
        if InventoryPostingSetup.Get(LocationCode, GroupCode) then
            exit;
        InventoryPostingSetup.Init();
        InventoryPostingSetup."Location Code" := LocationCode;
        InventoryPostingSetup."Invt. Posting Group Code" := GroupCode;
        // POS-CATCHALL is the single G/L account POSeedBootstrap creates and
        // assigns to every Inventory/Posting Setup slot — Item Jnl posting
        // requires Inventory Account to be non-empty.
        InventoryPostingSetup."Inventory Account" := 'POS-CATCHALL';
        InventoryPostingSetup."Inventory Account (Interim)" := 'POS-CATCHALL';
        InventoryPostingSetup.Insert(true);
    end;
}
