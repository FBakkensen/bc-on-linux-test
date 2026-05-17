namespace FBakkensen.BcLinuxSmoke.IT;

using FBakkensen.BcLinuxSmoke;
using Microsoft.Assembly.History;
using System.TestLibraries.Utilities;

codeunit 50166 "Assembly LT Query Tests"
{
    Subtype = Test;
    Access = Internal;
    Permissions = tabledata "Posted Assembly Header" = I;

    var
        Assert: Codeunit "Library Assert";

    [Test]
    procedure EmitsRowPerPostedAssemblyHeaderWithStartingAndPostingDate()
    var
        AssemblyLT: Query "Assembly LT";
        DocNo: Code[20];
        ItemNo: Code[20];
        Rows: Integer;
    begin
        // GIVEN a Posted Assembly Header — represents a finished assembly,
        // ADR 0006 says LT = Posting Date − Starting Date. The Python
        // parser does the subtraction; the AL Query just exposes both.
        DocNo := UniqueDocNo();
        ItemNo := UniqueItemNo();
        InsertPostedAsmHeader(DocNo, ItemNo, '', 'BLUE', 20260401D, 20260405D);

        AssemblyLT.SetFilter(itemNo, ItemNo);
        AssemblyLT.Open();
        while AssemblyLT.Read() do begin
            Rows += 1;
            Assert.AreEqual(DocNo, AssemblyLT.assemblyDocNo, 'assemblyDocNo from Posted Assembly Header "No.".');
            Assert.AreEqual(ItemNo, AssemblyLT.itemNo, 'itemNo from Posted Assembly Header.');
            Assert.AreEqual('', AssemblyLT.variantCode, 'variantCode passes through.');
            Assert.AreEqual('BLUE', AssemblyLT.locationCode, 'locationCode passes through.');
            Assert.AreEqual(20260401D, AssemblyLT.startingDate, 'startingDate from Posted Assembly Header.');
            Assert.AreEqual(20260405D, AssemblyLT.postingDate, 'postingDate from Posted Assembly Header.');
        end;
        AssemblyLT.Close();

        Assert.AreEqual(1, Rows, 'Exactly one row per Posted Assembly Header.');
    end;

    local procedure InsertPostedAsmHeader(No: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; LocationCode: Code[10]; StartingDate: Date; PostingDate: Date)
    var
        PostedAsmHeader: Record "Posted Assembly Header";
    begin
        PostedAsmHeader.Init();
        PostedAsmHeader."No." := No;
        PostedAsmHeader."Item No." := ItemNo;
        PostedAsmHeader."Variant Code" := VariantCode;
        PostedAsmHeader."Location Code" := LocationCode;
        PostedAsmHeader."Starting Date" := StartingDate;
        PostedAsmHeader."Posting Date" := PostingDate;
        PostedAsmHeader.Insert(false);
    end;

    local procedure UniqueDocNo(): Code[20]
    begin
        exit(CopyStr('ASM' + UniqueSuffix(), 1, 20));
    end;

    local procedure UniqueItemNo(): Code[20]
    begin
        exit(CopyStr('AKIT' + UniqueSuffix(), 1, 20));
    end;

    local procedure UniqueSuffix(): Text
    begin
        exit(Format(CurrentDateTime(), 0, '<Hours24,2><Minutes,2><Seconds,2><Thousands,3>') + Format(Random(99999)));
    end;
}
