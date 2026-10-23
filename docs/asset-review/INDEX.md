# Asset review index

One row per review sheet. Status: `pending`, `approved`, `changes`, `polish-list`. Sheets live in `docs/asset-review/week-N/`. Process in `specs/SPEC-art-audio.md`, "Review step".

| Week | Lane | Sheet | Asset ids | Reviewer | Status | Notes |
|---|---|---|---|---|---|---|
| 5 | surface | `week-5/town_buildings_1.png`, `week-5/town_buildings_2.png` | 11 buildings x 4 states (sign, ruined, rebuilt, upgraded), 3 props | Dev B | approved | `tools/art/gen_town.py`; in-engine capture `week-5/town_in_engine.png` |
| 5 | surface | `week-5/town_ground_pit_wren.png` | town atlas (floor, fence, pit), pit edge stages 0 to 3, Wren portrait | Dev B | approved | `gen_town.py`, `gen_portraits.py`; pit logic radius is coarser than the art (Town.PIT_RADIUS_BY_STAGE) |
