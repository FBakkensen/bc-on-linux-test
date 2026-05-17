query 50001 "Purchase Receipt LT"
{
    QueryType = API;
    APIPublisher = 'fbakkensen';
    APIGroup = 'planningOptimizer';
    APIVersion = 'v1.0';
    EntityName = 'purchaseReceiptLT';
    EntitySetName = 'purchaseReceiptLT';
    Caption = 'Purchase Receipt LT';
    OrderBy = ascending(itemNo, variantCode, locationCode, receiptPostingDate);

    elements
    {
        dataitem(PurchRcptLine; "Purch. Rcpt. Line")
        {
            // Type = Item filters out G/L Account / Comment / Charge lines —
            // only item receipts have a lead time. Drop-shipments link a
            // sales order on the receipt line; special orders link a sales
            // line via Special Order Sales No. Both are item-specific demand,
            // not replenishment lead time (ADR 0006), so we exclude them
            // server-side.
            DataItemTableFilter = Type = const(Item),
                                  "Sales Order No." = filter(''),
                                  "Special Order Sales No." = filter('');

            column(itemNo; "No.")
            {
            }
            column(variantCode; "Variant Code")
            {
            }
            column(locationCode; "Location Code")
            {
            }
            column(quantity; Quantity)
            {
            }
            column(documentNo; "Document No.")
            {
            }
            column(receiptPostingDate; "Posting Date")
            {
            }

            dataitem(PurchRcptHeader; "Purch. Rcpt. Header")
            {
                DataItemLink = "No." = PurchRcptLine."Document No.";
                SqlJoinType = InnerJoin;

                column(vendorNo; "Buy-from Vendor No.")
                {
                }
                // Order Date is captured at posting time on the receipt
                // header, so it survives the source PO being deleted —
                // safe to use even when PurchaseHeader (below) is gone.
                column(poOrderDate; "Order Date")
                {
                }

                dataitem(PurchaseHeader; "Purchase Header")
                {
                    DataItemLink = "No." = PurchRcptHeader."Order No.";
                    // Left-outer: the source PO may have been deleted (fully
                    // invoiced / archived). Expected Receipt Date then comes
                    // back null, which the Python parser maps to a NaN
                    // plan_to_receipt_days while still emitting
                    // order_to_receipt_days (ADR 0006).
                    SqlJoinType = LeftOuterJoin;

                    column(expectedReceiptDate; "Expected Receipt Date")
                    {
                    }
                }
            }
        }
    }
}
