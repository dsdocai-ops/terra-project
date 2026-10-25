# Asset review index

One row per review sheet. Status: `pending`, `approved`, `changes`, `polish-list`. Sheets live in `docs/asset-review/week-N/`. Process in `specs/SPEC-art-audio.md`, "Review step".

| Week | Lane | Sheet | Asset ids | Reviewer | Status | Notes |
|---|---|---|---|---|---|---|
| 5 | surface | `week-5/town_buildings_1.png`, `week-5/town_buildings_2.png` | 11 buildings x 4 states (sign, ruined, rebuilt, upgraded), 3 props | Dev B | changes | `tools/art/gen_town.py`; in-engine capture `week-5/town_in_engine.png`. Superseded by art direction v2 (2026-10-24); stays in game until AR-5 is approved |
| 5 | surface | `week-5/town_ground_pit_wren.png` | town atlas (floor, fence, pit), pit edge stages 0 to 3, Wren portrait | Dev B | changes | Superseded by art direction v2 (2026-10-24): town by AR-5, Wren portrait by AR-9; stays in game until those are approved. `gen_town.py`, `gen_portraits.py`; pit logic radius is coarser than the art (Town.PIT_RADIUS_BY_STAGE) |
| 6 | pit | `week-6/v2_mines_floor1_in_engine.png`, `week-6/v2_mines_floor_start_in_engine.png` | v2 Collapsed Mines floor, wall, pit (`gen_tiles_v2.py`); Wren, Kestrel, Ivy, Brann (`gen_sprites_v2.py`, BODY template); Hollow Miner, Rock Tick, Lantern Wisp, Dynamite Goblin, Cave Bat | Dev A | pending | First v2 pass (AR-3, AR-7, AR-8). Small enemies derive facings from one front drawing; Goblin and Bat have no `EnemyData` yet, so they are not in game. Floor variants need a floor-generation hook (only `Tiles.FLOOR` is painted) |
