# Domain glossary

Canonical language for this workspace. Terms here are load-bearing — when in
doubt, use these words and not synonyms.

## Available Inventory

The quantity of an item physically on hand (plus, depending on the asker, in
transit and on open documents in aggregate). Not date-aware. In BC, surfaced
via `Item.Inventory` and the date-less `Qty. on Sales Order`,
`Qty. on Purch. Order`, `Qty. in Transit`, `Qty. on Prod. Order`,
`Qty. on Asm. Order`, `Qty. on Service Order`, `Qty. on Job Order`, …
flow-fields. Answers *"do I have stock?"*.

## Projected Available Balance

The signed cumulative balance of an item at a specific future date `t`:

```
ProjectedAvailableBalance(t) = Inventory
                             + Σ(scheduled receipts dated ≤ t)
                             − Σ(gross requirements dated ≤ t)
```

across all signed event sources (item ledger, sales lines, purchase lines,
transfer in/out, prod. order output + components, asm. output + components,
service lines, job planning lines, …). Surfaced in BC by page 5530
*Item Availability by Date*. Answers *"what will the balance look like on
date t?"*.

## Available-to-Promise (ATP) Quantity

The quantity that can be committed to a new sales line on date `D` without
driving Projected Available Balance below zero at any `t ≥ D`:

```
ATP(D) = max(0, min over t ≥ D of ProjectedAvailableBalance(t))
```

Distinguished from Available Inventory: ATP respects already-committed future
demand; Available Inventory does not. Related BC code lives in
Codeunit 5790 *Available to Promise*.

## Max Sellable Quantity

This project's wrapper concept. The ATP Quantity for a specific
`(Item, Variant, Location, ShipmentDate)` tuple, exposed via a project-owned
codeunit. Intended for use at sales line entry/validation time.
