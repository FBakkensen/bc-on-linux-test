"""Tests for the per-source `project_*` helpers in `bc_api`.

Each helper projects a snake-cased row from one Open SD AL Query into the
unified event shape. Sign and source_kind are the load-bearing pieces: get
them wrong and the simulator's initial state is wrong. These are pure
functions over dicts — no HTTP needed.
"""

from extracts import bc_api


def _sales_row(**overrides):
    base = {
        "item_no": "ITEM-A",
        "variant_code": "",
        "location_code": "BLUE",
        "event_date": "2026-05-20",
        "qty": 10.0,
        "document_type": "Order",
    }
    base.update(overrides)
    return base


def _purchase_row(**overrides):
    base = {
        "item_no": "ITEM-A",
        "variant_code": "",
        "location_code": "BLUE",
        "event_date": "2026-05-25",
        "qty": 50.0,
        "document_type": "Order",
    }
    base.update(overrides)
    return base


def test_sales_order_is_demand_with_negative_sign():
    [event] = bc_api.project_sales([_sales_row(qty=10, document_type="Order")])
    assert event["source_kind"] == bc_api.SOURCE_SALES_ORDER
    assert event["signed_quantity"] == -10.0


def test_sales_return_order_is_supply_with_positive_sign():
    [event] = bc_api.project_sales([_sales_row(qty=10, document_type="Return Order")])
    assert event["source_kind"] == bc_api.SOURCE_SALES_RETURN_ORDER
    assert event["signed_quantity"] == 10.0


def test_sales_tolerates_enum_serialization_without_spaces():
    # BC OData has serialized enums both as "Return Order" and "ReturnOrder"
    # across versions; the normalizer collapses both — never debug a CSV
    # that says sales_order when the BC line was a return.
    [event] = bc_api.project_sales([_sales_row(document_type="ReturnOrder")])
    assert event["source_kind"] == bc_api.SOURCE_SALES_RETURN_ORDER


def test_purchase_order_is_supply_with_positive_sign():
    [event] = bc_api.project_purchase([_purchase_row(qty=50, document_type="Order")])
    assert event["source_kind"] == bc_api.SOURCE_PURCHASE_ORDER
    assert event["signed_quantity"] == 50.0


def test_purchase_return_order_is_demand_with_negative_sign():
    [event] = bc_api.project_purchase([_purchase_row(qty=50, document_type="Return Order")])
    assert event["source_kind"] == bc_api.SOURCE_PURCHASE_RETURN_ORDER
    assert event["signed_quantity"] == -50.0


def test_transfer_in_uses_destination_location_with_positive_sign():
    rows = [
        {
            "item_no": "ITEM-A",
            "variant_code": "",
            "location_code": "DEST",
            "event_date": "2026-06-01",
            "qty": 5.0,
        }
    ]
    [event] = bc_api.project_transfer_in(rows)
    assert event["source_kind"] == bc_api.SOURCE_TRANSFER_IN
    assert event["location_code"] == "DEST"
    assert event["signed_quantity"] == 5.0


def test_transfer_in_skips_zero_qty_rows():
    # BC's IsReceipt=true filter doesn't add Outstanding<>0 (only the
    # IsReceipt=false path does). Skip zero rows in the projector so
    # fully-received in-transits don't pollute the event stream.
    rows = [
        {
            "item_no": "X",
            "variant_code": "",
            "location_code": "L",
            "event_date": "2026-01-01",
            "qty": 0,
        }
    ]
    assert bc_api.project_transfer_in(rows) == []


def test_transfer_out_uses_source_location_with_negative_sign():
    rows = [
        {
            "item_no": "ITEM-A",
            "variant_code": "",
            "location_code": "SRC",
            "event_date": "2026-05-30",
            "qty": 5.0,
        }
    ]
    [event] = bc_api.project_transfer_out(rows)
    assert event["source_kind"] == bc_api.SOURCE_TRANSFER_OUT
    assert event["location_code"] == "SRC"
    assert event["signed_quantity"] == -5.0


def test_prod_order_line_is_supply_prod_order_comp_is_demand():
    line_row = {
        "item_no": "ITEM-A",
        "variant_code": "",
        "location_code": "BLUE",
        "event_date": "2026-06-15",
        "qty": 100.0,
    }
    comp_row = {**line_row, "qty": 30.0}
    [line_event] = bc_api.project_prod_order_line([line_row])
    [comp_event] = bc_api.project_prod_order_comp([comp_row])
    assert line_event["source_kind"] == bc_api.SOURCE_PROD_ORDER_LINE
    assert line_event["signed_quantity"] == 100.0
    assert comp_event["source_kind"] == bc_api.SOURCE_PROD_ORDER_COMPONENT
    assert comp_event["signed_quantity"] == -30.0


def test_assembly_header_is_supply_assembly_line_is_demand():
    header_row = {
        "item_no": "ITEM-A",
        "variant_code": "",
        "location_code": "BLUE",
        "event_date": "2026-07-01",
        "qty": 12.0,
    }
    line_row = {**header_row, "qty": 4.0}
    [header_event] = bc_api.project_assembly_header([header_row])
    [line_event] = bc_api.project_assembly_line([line_row])
    assert header_event["source_kind"] == bc_api.SOURCE_ASSEMBLY_HEADER
    assert header_event["signed_quantity"] == 12.0
    assert line_event["source_kind"] == bc_api.SOURCE_ASSEMBLY_LINE
    assert line_event["signed_quantity"] == -4.0


def test_service_line_is_demand_with_negative_sign():
    rows = [
        {
            "item_no": "ITEM-A",
            "variant_code": "",
            "location_code": "BLUE",
            "event_date": "2026-05-22",
            "qty": 3.0,
        }
    ]
    [event] = bc_api.project_service(rows)
    assert event["source_kind"] == bc_api.SOURCE_SERVICE_LINE
    assert event["signed_quantity"] == -3.0


def test_job_planning_normal_line_emits_once_with_negative_sign():
    rows = [
        {
            "item_no": "ITEM-A",
            "variant_code": "",
            "location_code": "BLUE",
            "event_date": "2026-05-30",
            "qty": 7.0,
            "line_type": "Budget",
        }
    ]
    events = bc_api.project_job_planning(rows)
    assert len(events) == 1
    assert events[0]["source_kind"] == bc_api.SOURCE_JOB_PLANNING_LINE
    assert events[0]["signed_quantity"] == -7.0


def test_job_planning_both_budget_and_billable_emits_twice():
    # ADR 0001 deviation #3: BC's Job availability views double-count the
    # combo Line Type so our event stream stays in lock step. This is the
    # single most surprising behaviour — explicit test, explicit comment.
    rows = [
        {
            "item_no": "ITEM-A",
            "variant_code": "",
            "location_code": "BLUE",
            "event_date": "2026-05-30",
            "qty": 7.0,
            "line_type": "Both Budget and Billable",
        }
    ]
    events = bc_api.project_job_planning(rows)
    assert len(events) == 2
    assert all(e["signed_quantity"] == -7.0 for e in events)


def test_job_planning_tolerates_enum_serialization_without_spaces():
    rows = [
        {
            "item_no": "ITEM-A",
            "variant_code": "",
            "location_code": "BLUE",
            "event_date": "2026-05-30",
            "qty": 7.0,
            "line_type": "BothBudgetAndBillable",
        }
    ]
    assert len(bc_api.project_job_planning(rows)) == 2
