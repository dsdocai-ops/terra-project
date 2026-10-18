# SINKHOLE: Game Design Spec (v3)

**Project:** Hack Club Terra game
**Team:** 2 developers, heavy use of Claude Code for implementation and content
**Engine:** Godot 4.4 or newer (GDScript). Needs 4.3+ for `TileMapLayer`
**Timeline:** 12 weeks
**Genre:** 2D isometric action roguelike RPG with 7 classes, extraction, town building, story, and 1 to 4 player online co-op

---

## 1. Pitch

A small mining town sits on the edge of a bottomless pit called the Sinkhole. Twenty years ago the miners dug too deep and woke something. Now the pit is growing, swallowing the town street by street. You and up to 3 friends dive into the pit, fight through 6 biomes and 16 bosses, and decide when to climb back out with your loot. Loot rebuilds the town, the skill tree makes you permanently stronger, and a story unfolds about what the miners found at the bottom and why the pit is calling to you.

## 2. Design Pillars

1. **Risk vs reward every floor.** Every rope point is a choice: cash out or go deeper.
2. **Wild builds.** Relics, abilities, and weapon mutations should stack into builds that feel broken in a fun way. Not +5% damage, but "my dodge spawns lightning clones that explode."
3. **Combat that feels fair.** Every enemy and boss attack has a readable windup.
4. **Visible progress.** The town rebuilds, the skill tree fills, the story advances.
5. **Better with friends.** Co-op is built in from day one, not bolted on.

## 3. Core Loop

1. **Town:** talk to NPCs (story), spend resources on buildings and skill tree, pick character, class, and starting weapon
2. **Dive:** enter the pit solo or with up to 3 friends
3. **Clear floors:** fight, loot relics, abilities, weapons, and currencies, make build choices
4. **Rope points:** on floor 2 and after the biome boss of every biome. Climb out and keep everything, or go deeper
5. **Death:** lose carried ore, relics, run abilities, weapon mutations, and your Ascension, keep 25% gold. Echo Shards, Class XP, and story progress always kept. Extracting also ends the run, so relics, abilities, mutations, and Ascension reset either way (see section 9.5 for full economy rules)
6. **Return:** new dialogue, new upgrades, dive again

## 4. Characters and Classes

**Character = who you are in the story. Class = how you fight.** Any character can play any class, so there are 28 character + class combos. Before every run you pick a character, a class, and a starting weapon from that class's affinity list.

### 4.1 Playable Characters

4 characters, each with a small unique passive, a unique ultimate (section 8), and their own story thread. 1 available at start, 3 unlocked through story and achievements.

| Character | Passive | Unlock |
|---|---|---|
| **Wren, the Miner's Daughter** | Ore drops +25%, can break certain walls to find secret rooms | Default |
| **Brann, the Old Miner** | Gains armor stacks when standing still, loses them when moving | Defeat The Foreman |
| **Ivy, the Lamplighter** | Lights up dark rooms, enemies in her light take +15% damage | Find all 5 Lost Lanterns in the Fungal Caverns |
| **Kestrel, the Drifter** | Every dodge has a 30% chance to reset instantly | Reach Biome 4 |

### 4.2 Classes (7)

Each class has:
- **Role** (matters for co-op team comps)
- **Weapon affinity:** bonus effects with certain weapons. Any class can still use any weapon
- **Class passive**
- **Class skill** (Shift, its own cooldown, separate from abilities)
- **Ascensions (subclasses):** after beating the first biome boss in a run, choose 1 of 2 Ascensions for the rest of that run. After the Biome 4 boss, your Ascension evolves into a stronger Tier 2 form
- **Class tree:** a small per-class skill tree, bought with **Class XP** earned by playing that class
- **Mastery levels 1 to 10:** unlock class tree nodes, an alternate class skill at level 5, and cosmetics at level 10

Unlocks: Warrior, Ranger, and Mage at start. The other 4 are unlocked by rescuing specific trapped miners (ties into the story, see Rescue missions in section 11):

| Class | Rescued miner | Found in |
|---|---|---|
| Rogue | Sly Nettie, a pickpocket miner | Fungal Caverns |
| Engineer | Cogsworth, the mine's machinist | Crystal Hollows |
| Necromancer | Mortimer, the town gravedigger | Drowned City |
| Lightbearer | Sister Ash's apprentice, Elian | Ember Forge |

**Starting weapons rule:** at the start of the game, the Pickaxe, Crossbow, and Lantern Staff are unlocked so each starting class has an affinity weapon. Unlocking a class also unlocks one of its affinity weapons for free (Rogue: Twin Daggers, Engineer: Hand Cannon, Necromancer: Grave Scythe, Lightbearer: Longsword). Every other weapon is bought at the Blacksmith. The Pickaxe can always be picked by any class.

**Ascension timing rule:** if a run starts at a deeper rope point (Map Room shortcut) past Biome 1, the player picks their Ascension at the start of the run. If it starts past Biome 4, they start at Tier 2.

---

#### Warrior
- **Role:** Melee bruiser / tank
- **Affinity:** Blades and Heavy weapons (heavy attacks charge 25% faster)
- **Passive: Rage.** Dealing and taking damage builds Rage. At full Rage, attacks cleave in a wide arc and you take 20% less damage until it drains
- **Class skill: Battle Cry.** Taunt nearby enemies, gain armor, knock back small enemies
- **Ascensions:**
  - **Berserker:** lower HP = more damage and attack speed, Rage never decays. *Tier 2, Blood Frenzy:* kills at full Rage fully heal you once per room
  - **Guardian:** gains a shield block, blocking projectiles reflects them, allies near you take less damage. *Tier 2, Bulwark:* Battle Cry shields every ally
- **Class tree highlights:** faster Rage, Battle Cry stuns, heavy attacks send shockwaves, cleaves apply Bleed

#### Ranger
- **Role:** Ranged DPS
- **Affinity:** Ranged weapons (projectiles pierce 1 extra enemy)
- **Passive: Far Shot.** Damage increases with distance from the target (up to +40%)
- **Class skill: Tumble Volley.** Backflip away and fire a fan of arrows forward
- **Ascensions:**
  - **Beastmaster:** a wolf companion fights with you, Tumble Volley makes it pounce. *Tier 2, Pack Leader:* adds a hawk that marks enemies and grabs loot
  - **Sharpshooter:** charged shots deal massive damage, enemies show a weak spot that always crits. *Tier 2, Deadeye:* time slows while you charge a shot
- **Class tree highlights:** faster projectiles, companions inherit your relics, longer Far Shot range, traps where Tumble lands

#### Mage
- **Role:** Elemental AoE DPS
- **Affinity:** Magic weapons (spells apply their element twice)
- **Passive: Arcane Flow.** Every element combo you trigger cuts all ability cooldowns by 1 second
- **Class skill: Blink.** Short teleport, leaves an explosion of your last used element
- **Ascensions:**
  - **Pyromancer:** everything applies Burn, burning enemies explode on death. *Tier 2, Phoenix:* rise from death in flames once per run
  - **Stormcaller:** abilities chain to extra enemies, Blink becomes a lightning strike. *Tier 2, Eye of the Storm:* a storm cloud follows you and strikes enemies
- **Class tree highlights:** +1 ability charge, longer status effects, Blink gets 2 charges, combos leave elemental zones

#### Rogue
- **Role:** Burst assassin
- **Affinity:** Twin Daggers, Throwing Knives, Chain Whip (attacks from behind always crit)
- **Passive: Backstab.** Hitting enemies from behind deals +75% damage and applies Mark
- **Class skill: Smoke Step.** Dash and turn invisible for 2 seconds, enemies lose track of you
- **Ascensions:**
  - **Assassin:** Marked enemies below 30% HP are executed instantly. *Tier 2, Death Mark:* executions reset Smoke Step and Mark every nearby enemy
  - **Trickster:** leaves decoy clones and traps, can steal a buff from elites. *Tier 2, Master Thief:* stolen buffs last the whole floor, chests can drop double
- **Class tree highlights:** longer invisibility, crits refund dodge cooldown, poison daggers, extra gold from kills

#### Necromancer
- **Role:** Summoner
- **Affinity:** Grave Scythe, Reaper's Chain, Spore Tome (kills always drop souls)
- **Passive: Soul Harvest.** Kills drop souls. Every 5 souls raises a skeleton minion (max 3, more with upgrades)
- **Class skill: Corpse Burst.** Detonate a minion or corpse for big AoE damage. A minion detonated this way rises again after 10s
- **Ascensions:**
  - **Gravelord:** max minions 6, minions are raised as the enemy types you killed. *Tier 2, Lord of the Dead:* merge 3 minions into a giant bone golem
  - **Plague Lord:** minions apply Toxin and burst into poison clouds on death. *Tier 2, Pestilence:* poison clouds raise dead enemies as plague zombies
- **Class tree highlights:** minions inherit 25% of your stats, faster souls, minions taunt, life steal per living minion

#### Engineer
- **Role:** Zone control / builder
- **Affinity:** Hand Cannon, Drill Gauntlets, Saw Boomerang, Crossbow (build Scrap faster)
- **Passive: Scrap.** Hits and kills generate Scrap, which powers gadgets
- **Class skill: Deploy.** Spend Scrap to place a turret (up to 2). Use on a placed turret to upgrade it
- **Ascensions:**
  - **Mechanist:** spend 100 Scrap to pilot a mech suit for 12 seconds (rockets, stomp, flamethrower). *Tier 2, War Machine:* longer mech, allies can ride on top
  - **Demolitionist:** turrets become mines and grenade launchers, your explosions don't hurt you. *Tier 2, Chain Reaction:* explosions can trigger more explosions
- **Class tree highlights:** turrets inherit your elements, 3rd turret slot, repair drone, turrets copy some relic effects

#### Lightbearer
- **Role:** Support / healer (best in co-op, still solid solo)
- **Affinity:** Lantern Staff, Sledgehammer, Longsword (hits heal nearby allies a little)
- **Passive: Radiance.** A light aura heals allies inside over time and burns enemies standing in it
- **Class skill: Sanctuary.** Holy zone: allies inside take 40% less damage, downed allies inside revive faster
- **Ascensions:**
  - **Paladin:** holy melee warrior, attacks release light waves, takes less damage. *Tier 2, Avatar of Light:* sprout wings and smite from above for 8 seconds
  - **Oracle:** pure support, revive allies from range, overhealing becomes shields. *Tier 2, Foresight:* once per room, cancel a hit that would down an ally
- **Class tree highlights:** bigger aura, Sanctuary cleanses debuffs, revives give buffs, solo nodes that boost self-healing

---

### 4.3 Classes in Co-op
- Suggested team: a tank (Warrior Guardian), a support (Lightbearer), and 2 damage classes
- **Class pair bonuses:** Warrior + Lightbearer (taunted enemies take more damage), Mage + Engineer (turrets apply the Mage's element), Rogue + Ranger (Marks are shared), Necromancer + Warrior (minions gain Rage when the Warrior does)
- Two players can pick the same class, but must take different Ascensions

## 5. Controls (keyboard + mouse, controller support planned)

| Action | Input |
|---|---|
| Move | WASD (8 directions, mapped to isometric axes) |
| Aim | Mouse |
| Light attack | Left click |
| Heavy attack | Right click (hold to charge) |
| Dodge roll | Space |
| Class skill | Shift |
| Swap weapon | Mouse wheel or 1 / 2 |
| Ability 1 / Ability 2 / Ability 3 | Q / R / V (third slot unlocked by the Arcane skill tree) |
| Ultimate | X (when charged) |
| Active relic 1 / Active relic 2 | C / B (second slot unlocked by the Abyss skill tree) |
| Use potion | E |
| Interact / revive teammate | F (hold to revive) |
| Inventory / map | Tab |
| Ping (co-op) | Middle click |
| Pause | Esc |

All inputs defined in Godot's Input Map so they can be rebound.

## 6. Player and Combat

**Stats:** Max HP, Attack, Defense, Move Speed, Attack Speed, Dodge Cooldown, Crit Chance, Crit Damage, Ability Power, Cooldown Reduction, Luck.

- Dodge roll with i-frames, cooldown ~0.8s
- Hit-stun, knockback, brief invincibility after taking damage
- Every enemy attack: **windup** (telegraph) → **active** (hitbox) → **recovery** (vulnerable)
- Hit feedback: hit flash, screen shake, hit-stop on heavy hits, damage numbers (crits bigger and colored)
- **Elements and status effects:**

| Element | Status | Effect |
|---|---|---|
| Fire | Burn | Damage over time |
| Frost | Chill → Freeze | Slows, then freezes at 5 stacks |
| Storm | Shock | Chains to nearby enemies |
| Poison | Toxin | Stacking damage over time, reduces healing |
| Shadow | Mark | Next hit on a marked enemy crits |
| Blood | Bleed | Damage when the enemy moves |
| Void | Unravel | Increases all damage taken |

- **Element combos:** applying two elements triggers a reaction
  - Fire + Frost = **Shatter** (big burst damage)
  - Storm + Water tile/Drowned enemy = **Conduct** (shock spreads across the whole puddle)
  - Fire + Poison = **Blight Explosion**
  - Shadow + Bleed = **Hemorrhage** (bleed ticks crit)
  - Frost + Storm = **Superconduct** (enemies lose armor)
  - Void + anything = **Collapse** (pulls nearby enemies together)

## 7. Weapons (19 weapons, 5 weapon types)

Every weapon has a light combo, a heavy attack, and a **weapon skill**. The weapon skill fires when you press heavy attack within 0.5s after a perfect dodge (dodging through an attack at the last moment), and then has a cooldown of about 6s. Weapons are unlocked permanently at the Blacksmith or found as rare drops in the pit. You can carry 2 weapons and swap with the mouse wheel. Classes get bonus effects with their affinity weapons (section 4.2).

### Blades
| Weapon | Feel | Signature |
|---|---|---|
| **Pickaxe** | Balanced starter | Heavy cracks the ground in a line |
| **Longsword** | Wide arcs | Heavy is a spinning slash that pulls enemies in |
| **Twin Daggers** | Very fast | Every 5th hit applies Mark, weapon skill teleports behind the nearest Marked enemy |
| **Grave Scythe** | Long reach, slow | Kills drop soul orbs that heal and boost damage |

### Heavy
| Weapon | Feel | Signature |
|---|---|---|
| **Sledgehammer** | Slow, huge damage | Charged slam sends a shockwave ring |
| **Greataxe** | Spin to win | Holding heavy spins continuously, faster the longer you spin |
| **Rust Anchor** | Thrown chain weapon | Throw it, then yank yourself to it or yank enemies to you |

### Ranged
| Weapon | Feel | Signature |
|---|---|---|
| **Crossbow** | Precise | Charged bolt pierces everything in a line |
| **Shortbow** | Rapid fire | Holding heavy rains arrows on the cursor area |
| **Hand Cannon** | Shotgun blast | Recoil knocks you backward (can be used as a dash) |
| **Throwing Knives** | Spray | Knives stick in walls and can be recalled through enemies |

### Magic
| Weapon | Feel | Signature |
|---|---|---|
| **Lantern Staff** | Light | Charged beam, enemies in light take bonus damage |
| **Spore Tome** | Poison | Spells leave toxic clouds that grow when stacked |
| **Tide Orb** | Water | Creates water puddles (combo with Storm) and a returning wave |
| **Blood Grimoire** | Life cost | Spells cost HP instead of cooldowns, massive damage |

### Exotic
| Weapon | Feel | Signature |
|---|---|---|
| **Chain Whip** | Mid range | Hitting the tip deals triple damage |
| **Drill Gauntlets** | Close range | Holding attack drills through enemies, shreds armor |
| **Saw Boomerang** | Bouncing | Bounces between enemies, faster each bounce |
| **Reaper's Chain** | Long chain arcs | Scythe blade on a long chain, swings in wide arcs. Heavy hooks an enemy and pulls it in. Kills drop souls |

### Weapon Mutations
- **Anvil rooms** in the pit offer 1 of 3 mutations for your current weapon
- Each weapon has 6 possible mutations (114 for the 19 main weapons). Examples:
  - Sledgehammer, **Thunderhead:** slams call down lightning
  - Twin Daggers, **Phantom Pair:** a shadow copy repeats your combo half a second later
  - Rust Anchor, **Wrecking Ball:** anchor becomes a spinning ball that orbits you
  - Hand Cannon, **Grapeshot:** fires 12 pellets that bounce off walls
  - Saw Boomerang, **Twin Saws:** throws two, they fly in a figure 8
  - Grave Scythe, **Reaper's Harvest:** every 10 kills summons a ghost reaper for 8 seconds
- Mutations are lost at the end of a run
- The secret 20th weapon (Leviathan's Tooth, section 10) gets its own 6 mutations, so the real total is 120

## 8. Abilities

Abilities are found in the pit as **Rune Stones** and slotted into Q and R (and V once the third slot is unlocked). Swap them anytime at Shrine rooms. Each ability can be upgraded up to 3 times during a run by finding duplicate runes. **30 abilities listed below.**

### Fire
- **Meteor Call:** drop a meteor at the cursor, leaves burning ground
- **Flame Dash:** dash leaving a fire wall behind you
- **Inferno Ring:** ring of fire expands outward from you

### Frost
- **Glacier Spike:** line of ice spikes erupts from the ground
- **Frozen Clone:** leave an ice copy that taunts enemies, then shatters
- **Blizzard:** storm follows you for 6 seconds, chilling everything

### Storm
- **Chain Lightning:** bolt jumps between up to 8 enemies
- **Static Field:** zone that shocks anything inside
- **Thunder Step:** teleport to cursor, lightning strikes where you land

### Shadow
- **Shadow Clones:** summon 3 clones that copy your attacks
- **Vanish:** go invisible, next attack deals 3x damage
- **Umbral Grasp:** shadow hands root enemies in an area

### Poison
- **Toxic Cloud:** throw a gas canister that leaves a growing Toxin cloud
- **Plague Swarm:** release flies that chase enemies and spread Toxin between them
- **Acid Rain:** acid falls in a wide area, melting enemy armor

### Earth
- **Boulder Roll:** roll a huge boulder that grows as it rolls
- **Stone Skin:** become immune to knockback and take 50% less damage
- **Fault Line:** crack the floor, enemies fall in (instant kill on small enemies)

### Blood
- **Blood Pact:** sacrifice HP, gain huge attack speed
- **Crimson Leech:** tether to an enemy and drain its HP
- **Hemoburst:** all bleeding enemies explode

### Void
- **Black Hole:** pull every enemy to a point, then implode
- **Rift Walk:** step into the void, reappear anywhere on screen
- **Unmake:** erase all enemy projectiles on screen

### Utility
- **Grapple Hook:** pull yourself to walls or pull enemies to you
- **Turret Drop:** place an auto-firing turret
- **Mine Field:** scatter 6 explosive mines
- **Decoy Lantern:** enemies attack a lantern instead of you
- **Smoke Bomb:** enemies inside lose track of you
- **Barrier Dome:** a dome that blocks all enemy projectiles for 4 seconds (allies can stand inside)

**Total: 30 abilities across 9 schools** (Fire, Frost, Storm, Shadow, Poison, Earth, Blood, Void, Utility).

### Ultimates (X)
Charged by dealing and taking damage. One per character (classes change how it looks and adds a class twist, like Necromancer's Cave-In raising the crushed enemies as minions), plus alternate ultimates unlocked in the skill tree:
- **Wren, Cave-In:** the whole room's ceiling collapses on enemies
- **Brann, Foreman's Fury:** become giant for 10 seconds
- **Ivy, Sunrise:** blinding light stuns everything and doubles damage taken
- **Kestrel, Thousand Cuts:** dash through every enemy on screen
- Alternate ultimates: **Pit's Embrace** (summon tentacles from the floor), **Echo Storm** (replay your last 5 seconds of attacks), **Last Light** (revive all downed teammates and heal everyone)

## 9. Relics (88 listed: 70 passive, 10 active, 8 cursed)

Relics are run-only items. Most are passive, some are active (C key). Relics have tags (Fire, Dodge, Crit, Kill, etc.) that power **Synergies** in section 9.4. Rarity: Common, Rare, Epic, Legendary, Cursed.

### 9.1 Passive relics (70 listed)

**On Dodge**
1. **Ember Boots:** dodge leaves a fire trail
2. **Storm Sandals:** dodging through an enemy shocks it
3. **Mirror Step:** dodge leaves a clone that explodes after 1s
4. **Frostwalkers:** dodge freezes the ground, enemies slip
5. **Ghost Wrap:** perfect dodges make you invisible for 2s
6. **Rebound Spring:** dodge distance doubled, dodging into walls bounces you off them

**On Hit**
7. **Echo Blade:** every 4th hit strikes twice
8. **Spark Plug:** 10% chance on hit to fire chain lightning
9. **Hungry Steel:** each hit on the same enemy deals +5% more (stacks)
10. **Venom Gland:** hits apply Toxin
11. **Splitting Shot:** projectiles split into 3 on hit
12. **Gravity Stone:** hits pull nearby enemies slightly toward the target
13. **Leech Fang:** heal 2% of damage dealt
14. **Rune of Ricochet:** projectiles bounce to 2 more enemies

**On Kill**
15. **Volatile Core:** enemies explode on death
16. **Soul Jar:** kills charge a jar, at 20 kills it releases a ghost army for 10s
17. **Bloodthirst:** kills give +10% attack speed for 3s (stacks 5x)
18. **Corpse Bloom:** dead enemies sprout healing flowers
19. **Domino:** killing an enemy with a status effect spreads it to nearby enemies
20. **Trophy Belt:** every elite killed gives +3% damage for the rest of the run

**On Getting Hit**
21. **Thorn Mail:** reflect 50% of melee damage
22. **Panic Button:** when hit below 30% HP, release a frost nova (once per room)
23. **Spite Totem:** getting hit charges your ultimate 3x faster
24. **Cracked Shell:** first hit each room is blocked
25. **Revenge Pact:** after getting hit, next attack deals triple damage

**Crit**
26. **Lucky Coin:** +10% crit chance
27. **Glass Cannonball:** crits explode
28. **Assassin's Mark:** crits apply Mark
29. **Jackpot:** crits have a 5% chance to drop gold
30. **Fracture Lens:** crits reduce enemy armor permanently

**Elemental**
31. **Kindling:** burning enemies take +25% damage
32. **Permafrost:** frozen enemies take double damage from the next hit
33. **Lightning Rod:** shocks chain 2 extra times
34. **Plague Doctor's Mask:** Toxin stacks never expire
35. **Shadow Ink:** Marked enemies leave shadow puddles that slow
36. **Void Shard:** Unravel also makes enemies drop extra loot
37. **Prism:** every element you apply also applies a random second element

**Ability**
38. **Overcharger:** abilities have 1 extra charge
39. **Spellweaver:** using an ability buffs your next 3 attacks with its element
40. **Rune Battery:** killing enemies reduces ability cooldowns by 0.5s
41. **Echo Rune:** abilities have a 25% chance to cast twice
42. **Big Brain:** +40% ability power, -20% attack

**Movement and Position**
43. **Momentum Gear:** the longer you move without stopping, the more damage you deal
44. **Anchor Stone:** standing still for 1s gives +50% damage
45. **Wall Runner:** attacks near walls deal +30%
46. **Speed Demon:** +25% move speed, move speed adds to damage

**Economy and Exploration**
47. **Miner's Luck:** +20% gold
48. **Ore Magnet:** pick up loot from across the room
49. **Treasure Map:** reveals treasure and secret rooms
50. **Merchant's Badge:** shops have 1 extra item and 15% discount
51. **Echo Collector:** +50% Echo Shards this run

**Transformation (Legendary, change how you play)**
52. **Crown of the Deep:** each floor cleared without getting hit gives +10% damage permanently this run
53. **Second Wind:** revive once per run at 50% HP
54. **Hydra Heart:** every projectile you fire also fires 2 more at random angles
55. **Titan's Grip:** weapons are 50% bigger and hit 50% harder, attack speed -30%
56. **Clockwork Heart:** every 10 seconds, time stops for 1 second
57. **Infinity Loop:** abilities have no cooldown, but cost 10% HP each
58. **Mimic Crown:** copies the effect of your last picked relic
59. **The Pit's Eye:** you see enemy attacks 0.5s earlier (telegraphs show sooner)
60. **Necro Lantern:** killed enemies have a 15% chance to rise as your minion for the room (nod to the saved Necro Gardener concept)
61. **Worldbreaker:** heavy attacks cause earthquakes that damage the whole room
62. **Golden Idol:** all gold you hold boosts damage (1% per 100 gold), lose it all on death
63. **Twin Souls:** you have 2 HP bars, when the first empties you swap to the second
64. **Chaos Engine:** every room, gain a random legendary effect for that room only

**Extra tag fillers (so every synergy has enough relics)**
65. **Rot Lung:** enemies that die while poisoned release a Toxin cloud
66. **Acid Flask:** heavy attacks splash Toxin in a small area
67. **Frost Fang:** 15% chance on hit to apply 2 Chill stacks
68. **Thunder Bell:** every 8 seconds your next hit Shocks
69. **Night Cowl:** Marked enemies take +20% damage from all sources
70. **Ember Heart:** burning enemies have a chance to drop extra gold

### 9.2 Active relics (C key, one slot)
1. **Bomb Bag:** throw a bomb (3 charges, refill per room)
2. **Portal Stone:** place a portal, use again to teleport back to it
3. **Healing Totem:** drop a totem that heals allies nearby
4. **War Horn:** all allies gain +30% damage for 8s
5. **Pocket Golem:** summon a stone golem companion for the room
6. **Gambler's Die:** reroll the relic choices at the next shrine
7. **Time Hourglass:** rewind yourself 3 seconds (position and HP)
8. **Grappling Claw:** pull a far enemy straight to you and stun it
9. **Lantern of Souls:** captures an elite's ability, use it once
10. **Mega Magnet:** pull every enemy in the room to the center

### 9.3 Cursed relics
Powerful but with a downside. Found in **Cursed Altars** (optional risky rooms).
1. **Cursed Crown:** +100% damage, enemies have +50% HP
2. **Bleeding Heart:** +3 max HP per kill, but you constantly lose HP
3. **Coward's Cloak:** dodge cooldown is 0, but you can't heal
4. **Hunger Ring:** huge stat boost, but you must kill something every 10s or take damage
5. **Glass Body:** +80% everything, you die in 3 hits
6. **Pit Pact:** start every floor with a random legendary, but elites spawn in every room
7. **Greed Chain:** triple loot, but shops cost triple
8. **Silence Stone:** +200% weapon damage, no abilities

### 9.4 Synergies (relic tag combos)
Collecting relics with matching tags unlocks set bonuses shown on the HUD. Every relic has 1 to 2 tags in its `RelicData` (example: Ember Boots = Fire + Dodge). Every synergy must have at least 4 relics that carry its tag so it's actually reachable in a run.

| Synergy | Requirement | Bonus |
|---|---|---|
| **Pyromaniac** | 3 Fire relics | Burn spreads between enemies |
| **Glacial** | 3 Frost relics | Frozen enemies shatter for AoE when killed |
| **Thunderstruck** | 3 Storm relics | Every 5s a lightning bolt strikes a random enemy |
| **Plaguebringer** | 3 Poison relics | Toxin clouds follow you |
| **Nightblade** | 3 Shadow relics | Crits make you briefly invisible |
| **Phantom Dancer** | 3 Dodge relics | Dodge has 2 charges |
| **Reaper** | 3 Crit relics | Crits on low HP enemies instantly kill |
| **Arcanist** | 3 Ability relics | Every 3rd ability cast is free and empowered |
| **Juggernaut** | 3 On Getting Hit relics | Take 30% less damage, gain size |
| **Gold Fever** | 3 Economy relics | Gold pickups heal 1 HP |
| **Elementalist** | 1 relic of 4 different elements | Element combos deal double damage |
| **Doomed** | 2 Cursed relics | Curses' downsides halved |

### 9.5 Economy and Currencies

| Currency | Where it comes from | Used for | On death |
|---|---|---|---|
| **Gold** | Enemies, chests, breakables | Shops in the pit, potions, Blacksmith weapon purchases, respecs | Keep 25% (more with Delver tree) |
| **Ore** | Mining nodes, elites, bosses. Each biome has its own: Copper (1), Iron (2), Crystal (3), Pearl (4), Ember Ore (5), Heartstone (6) | Town building upgrades. Deeper buildings levels need deeper ores | Lose all (Ore Heart capstone keeps 50%) |
| **Echo Shards** | 1 per floor cleared (2 in Biomes 4 to 6), 1 to 2 per elite, 10 per mini-boss, 20 per biome boss, bounties | Main skill tree | Always kept |
| **Class XP** | Earned by the class you're playing: kills, floors, bosses | Class tree nodes and mastery levels for that class | Always kept |
| **Scrap** (Engineer only) | Hits and kills | Turrets and mech | Run-only |
| **Souls** (Necromancer only) | Kills | Raising minions | Run-only |

- In co-op, gold and ore are shared, Echo Shards and Class XP are earned by each player separately
- **Elites:** glowing outline, +100% HP, and one random affix (Shielded, Hasted, Splitting, Vampiric, Explosive, Teleporting). They drop better loot and Echo Shards
- **Depth scaling:** enemy HP and damage go up about 12% per biome, plus more enemies per room and more elites on deeper floors

## 10. The Pit: 6 Biomes, 30 Floors, 16 Bosses

Each biome: 5 floors. **Mini-boss on floor 3, biome boss on floor 5** (in Biome 6, floor 5 is the final boss). Rope points on floor 2 and after the biome boss on floor 5 of every biome. Mini-bosses do not give a rope, so floors 3 to 5 are a real commitment.

**Boss count:** 6 mini-bosses + 5 biome bosses + 1 final boss + 4 secret bosses = 16.

### Biome 1: Collapsed Mines (Floors 1 to 5)
- Hazards: falling rocks, runaway mine carts, gas pockets that ignite with Fire
- Enemies: **Hollow Miner** (melee), **Rock Tick** (fast rush), **Lantern Wisp** (fireballs), **Dynamite Goblin** (throws bombs), **Cave Bat Swarm** (erratic flyers)
- **Mini-boss: Boomer Jack.** Explosives expert who tosses dynamite and drops mines
- **Boss: The Foreman.** Giant possessed miner. Ground slams, summons Ticks, triggers cave-ins at 50% HP

### Biome 2: Fungal Caverns (Floors 6 to 10)
- Hazards: spore vents (poison), bouncy mushrooms that launch you, darkness zones
- Enemies: **Shroomling** (splits on death), **Spore Spitter** (lobs poison), **Mycel Brute** (charges), **Glow Moth** (blinds), **Root Strangler** (grabs from the ground)
- **Mini-boss: The Sporelord Twins.** Two mushroom knights, kill both within 10s or the other revives
- **Boss: The Bloom Mother.** Rooted giant mushroom, fills arena with spores, exposes weak core between attacks

### Biome 3: Crystal Hollows (Floors 11 to 15)
- Hazards: crystals that reflect projectiles (yours too), laser beams between crystal pillars
- Enemies: **Shard Golem** (splits into shards), **Prism Bat** (fires refracting beams), **Geode Turtle** (shell is immune, hit from behind), **Crystal Mimic** (disguised as loot)
- **Mini-boss: The Gem Collector.** A greedy goblin king in a crystal mech, steals your gold when he hits you, drops it all on death
- **Boss: The Prism Queen.** Splits into 3 mirror copies, only the real one takes damage, beams bounce around the room

### Biome 4: Drowned City (Floors 16 to 20)
- Hazards: deep water slows, currents push, rising water tiles
- Enemies: **Deepkin** (spear lunges), **Eel Lurker** (ambush), **Drowned Priest** (heals and shields), **Barnacle Crab** (armored), **Siren** (pulls you toward her)
- **Mini-boss: Captain Saltbones.** Undead pirate captain with a cannon crew
- **Boss: The Tide King.** Sunken throne fight, water level rises and falls changing the walkable area

### Biome 5: Ember Forge (Floors 21 to 25)
- Hazards: lava rivers, conveyor belts, molten metal pours, steam vents
- Enemies: **Forge Imp** (fast fire), **Slag Golem** (leaves lava), **Bellows Drone** (pushes you into lava), **Clockwork Sentry** (turret), **Ashen Smith** (buffs other enemies' weapons)
- **Mini-boss: The Iron Maiden.** A forge automaton that switches between hammer, saw, and flamethrower modes
- **Boss: Old Vulkar, the First Smith.** Ancient dwarf ghost who forged the miners' tools. Forges new weapons mid-fight and uses them against you

### Biome 6: The Heart (Floors 26 to 30)
- Hazards: pulsing walls that shoot spikes, breathing floor tiles, rooms that shrink
- Enemies: corrupted versions of all previous enemies plus **Veinling** (drains HP until dodged off), **Heart Guard** (vulnerable only from behind), **Echo** (copies your last ability)
- **Mini-boss: The Hollow You.** A dark copy of your character with your current build
- **Final Boss: The Sinkhole.** 3 phases:
  1. The pit's maw: uses attacks from bosses 1 to 3
  2. The pit's heart: uses attacks from bosses 4 and 5, the arena collapses
  3. The pit's true form: a story moment based on choices made in the story, then a final duel

### Secret Bosses
| Boss | How to find | Reward |
|---|---|---|
| **The Rat King** | Break a hidden wall in Biome 1 (easier with Wren) | Legendary relic + Rat companion cosmetic |
| **The Mushroom Hermit** | Bring a rare Golden Spore to a hidden room in Biome 2 | Unlocks a 4th alternate ultimate, **Spore Bloom** (giant mushrooms erupt across the room, launching and poisoning enemies) |
| **The Leviathan** | Fish with a found Fishing Rod in Drowned City | Weapon: Leviathan's Tooth (secret 20th weapon) |
| **The Watcher** | Beat the game, then find the eye in the town well | True ending |

### Floor Generation
- Grid-based generation in GDScript, painted on `TileMapLayer` nodes with `set_cell()`
- 8 to 14 rooms per floor, connected with corridors plus extra loops
- **Room types:** Start, Combat (doors lock), Elite Combat, Treasure, Shrine (choose 1 of 3 relics), Anvil (weapon mutation), Rune Room (ability), Shop, Cursed Altar, Challenge Room (beat a timed or no-hit challenge for loot), Lore Room (story pages), Rest Room (heal or upgrade), Secret Room, Rope Room, Exit
- **Floor modifiers** (random, deeper floors more likely): Darkness, Double Elites, Fast Enemies, Low Gravity (dodge goes farther), Gold Rush, Explosive Enemies
- Seeded generation for reproducing bugs and for syncing co-op

## 11. Story

### Premise
Twenty years ago the miners of Hollowmere struck something at the bottom of the mine: a living crystal heart. The mine collapsed into the Sinkhole, and every miner below was lost, including Wren's father. Now the pit is growing again, and the dead miners are coming back up wrong.

### Acts
| Act | Biomes | Story beats |
|---|---|---|
| **Act 1: The Fall** | 1 to 2 | Discover the miners aren't dead, they're possessed. The Foreman (Brann's older brother, who ran the mine) is the first. Learn the pit "calls" to people |
| **Act 2: The Descent** | 3 to 4 | Find the journals of Old Vulkar and the drowned city of the people who lived down there before the miners. Learn the pit has done this before |
| **Act 3: The Heart** | 5 to 6 | Learn the truth: the pit feeds on what people lose. It wants a new keeper. Confront it |

### Endings
1. **Seal the Pit:** sacrifice your carried relics to seal it. The town is saved, the pit sleeps
2. **Become the Keeper:** take the pit's power. Dark ending, unlocks Deep Mode with you as the antagonist
3. **True Ending:** requires beating The Watcher and collecting all lore. Free the trapped miners and destroy the heart

### Town NPCs (each has dialogue that changes as the story and town progress)
| NPC | Role |
|---|---|
| **Mayor Hilde** | Gives main story quests |
| **Gruff (Blacksmith)** | Weapon unlocks, tells stories about the old mine |
| **Moss (Alchemist)** | Potions, weird mushroom-obsessed scientist |
| **Pip (Map Maker)** | Kid who draws maps, gets braver as you go deeper |
| **Sister Ash (Shrine Keeper)** | Skill tree, secretly knows more about the pit |
| **Old Tom (Tavern)** | Rumors, hints about secret bosses |
| **Vesper (Mysterious Merchant)** | Appears randomly in town and the pit, sells cursed items |
| **The Rescued** | Miners you save in the pit come back to town and open new features |

### Story systems
- **Dialogue system:** JSON or Resource based dialogue trees with conditions (story flags, items, character)
- **Story flags:** stored in save data, unlock dialogue and events
- **Lore pages:** 40+ collectible journal pages in Lore Rooms, viewable in a codex
- **Rescue missions:** trapped miners appear on certain floors. Free them, then escort them to the next rope point (they follow you and can be hurt). Rescuing class miners unlocks classes (section 4.2), other rescued miners move into the Rescue Camp
- **Character threads:** each playable character has 3 personal story events
- All dialogue and lore written with Claude, then edited by the team for tone

## 12. Multiplayer (1 to 4 player online co-op)

### Approach
- Godot's built-in high-level multiplayer: `ENetMultiplayerPeer`, `MultiplayerSpawner`, `MultiplayerSynchronizer`, RPCs
- **Host-authoritative:** the host runs enemies, damage, loot rolls, and floor generation. Clients send inputs and play animations
- Floor generation: host sends the seed, every client generates the same floor locally
- **Connecting:** host shares an IP + port. For playing across the internet without port forwarding, use a tunneling tool like playit.gg or Tailscale. (Steam lobbies are a stretch goal, they need a Steam app ID)
- **Local co-op fallback:** 2 players on one screen with keyboard + controller, shared camera. Much easier and a safety net if online co-op runs into trouble

### Co-op rules
- Enemy HP scales with player count
- **Downed state:** at 0 HP you go down, teammates hold F to revive. If everyone is down, the run ends
- **Loot:** relics and abilities are per-player (each player sees their own drops). Gold and ore are shared
- **Rope votes:** extracting requires all living players to vote yes
- **Ping system:** middle click to mark enemies, loot, or locations
- **Team synergies:** relics like War Horn and Healing Totem affect allies
- Progress (town, skill tree) is saved per player, the host's town is the one you visit together

### Time effects in co-op
Several things slow or stop time (Clockwork Heart, Perfect Dodge, Sharpshooter Deadeye, Time Hourglass, hit-stop). **Never use `Engine.time_scale` for these.** Instead, every enemy, projectile, and boss reads a time multiplier from a `TimeManager` (or per-entity value), so "time stop" means enemies and enemy projectiles freeze while players keep moving. Hit-stop is done by pausing the attacker's and target's animations for a few frames, not the whole game. Time Hourglass rewind only affects the player who used it.

### Rule for development
Multiplayer has to be built in from Week 1. Every system (player, enemies, loot, abilities) gets written with "who owns this, how does it sync" in mind. Retrofitting multiplayer into a finished single-player game is way harder than building it in early.

## 13. Town (Meta Progression)

Town has 3 upgrade levels per building, visibly rebuilt each level. The pit's edge physically shrinks back as the story progresses.

| Building | Function |
|---|---|
| **Blacksmith** | Unlock weapons, permanent weapon damage tiers |
| **Alchemist** | Potion slots and types, starting potions |
| **Map Room** | Start runs at deeper rope points, reveals floor modifiers before diving |
| **Shrine of Echoes** | Skill tree, respec |
| **Tavern** | Story, rumors, co-op lobby board |
| **Relic Vault** | Codex of discovered relics, start runs with 1 chosen common relic |
| **Rune Library** | Codex of abilities, start runs with 1 chosen ability |
| **Training Grounds** | Test weapons and abilities on dummies, shows DPS |
| **Rescue Camp** | Rescued miners live here and give passive bonuses |
| **Bounty Board** | Daily and weekly challenges (kill X with Y, beat boss without healing) for bonus Echo Shards |
| **Wardrobe** | Cosmetic skins and hats unlocked from bosses and achievements |

## 14. Skill Tree

Opened at the Shrine of Echoes. Permanent upgrades bought with Echo Shards. Node graph UI with connecting lines, locked nodes greyed, purchasable nodes glowing. 4 branches + a center Abyss tree. Free respec once per day, otherwise costs gold.

### Steel (Weapons and offense)
| Node | Ranks | Effect |
|---|---|---|
| Sharpened Edge | 5 | +4% damage per rank |
| Heavy Hands | 3 | Heavy attacks charge 10% faster |
| Critical Eye | 5 | +2% crit chance |
| Brutal Strikes | 3 | +15% crit damage |
| Combo Master | 1 | Every 3rd light attack deals +50% |
| Dual Wielder | 1 | Swapping weapons triggers a free heavy attack |
| Armory | 2 | Anvil rooms offer +1 mutation choice |
| Weapon Master | 3 | +10% weapon skill damage |
| **Capstone: Executioner** | 1 | Enemies below 20% HP take double damage |

### Grit (Defense and survival)
| Node | Ranks | Effect |
|---|---|---|
| Thick Skin | 5 | +10 max HP |
| Iron Hide | 3 | +5% damage reduction |
| Quick Feet | 3 | -10% dodge cooldown |
| Perfect Dodge | 1 | Dodging at the last moment slows time for 1s |
| Potion Mastery | 2 | Potions heal +15% |
| Last Stand | 1 | Below 25% HP, +25% damage reduction |
| Field Medic | 2 | Revive teammates 30% faster, revived allies get a shield |
| **Capstone: Undying** | 1 | Once per run, survive a killing blow at 1 HP |

### Arcane (Abilities and elements)
| Node | Ranks | Effect |
|---|---|---|
| Rune Affinity | 5 | +5% ability power |
| Quick Cast | 3 | -6% ability cooldown |
| Elemental Study | 3 | +10% status effect duration |
| Reactive | 1 | Element combos deal +40% |
| Ult Charge | 3 | Ultimate charges 10% faster |
| Rune Finder | 2 | Rune Rooms appear more often |
| Third Rune | 1 | Unlocks a third ability slot (V) |
| **Capstone: Archmage** | 1 | Abilities have a 20% chance to not go on cooldown |

### Delver (Loot and exploration)
| Node | Ranks | Effect |
|---|---|---|
| Deep Pockets | 3 | Keep +10% gold on death |
| Prospector | 5 | +6% ore drops |
| Treasure Sense | 1 | Treasure rooms shown on minimap |
| Lucky Find | 3 | +5% higher relic rarity chance |
| Haggler | 2 | Shop prices -10% |
| Safe Line | 1 | Keep 1 random relic when extracting |
| Curse Breaker | 1 | Can remove a cursed relic's downside once per run |
| **Capstone: Ore Heart** | 1 | Keep 50% of carried ore on death |

### Abyss (center tree, unlocks after beating The Foreman)
| Node | Ranks | Effect |
|---|---|---|
| Abyssal Attunement | 1 | Second active relic slot |
| Echo Resonance | 3 | +10% Echo Shard gain |
| Pit Sight | 1 | See room types on the minimap before entering |
| Alt Ultimates | 3 | Unlocks Pit's Embrace, Echo Storm, Last Light |
| **Capstone: Heart of the Pit** | 1 | Requires all 4 branch capstones. +15% all stats |

Costs scale so a full tree takes roughly 25 to 40 runs.

## 15. Endgame and Replayability

- **Deep Mode:** unlocked after beating the game with any ending. Harder loop, enemies get new attacks, better loot. If the player got the Become the Keeper ending, Deep Mode runs have the player's dark version appear as an extra boss
- **Heat levels (difficulty modifiers):** 10 stackable modifiers (enemies faster, less healing, elites everywhere, bosses get a 4th phase) that multiply Echo Shard rewards
- **Daily Dive:** a seeded run everyone gets the same day, with a local or online leaderboard
- **Achievements:** 50+, unlock cosmetics and characters
- **Codex:** relics, abilities, enemies, bosses, lore pages, all tracked

## 16. UI and Screens

- Main menu: Play Solo, Host Co-op, Join Co-op, Settings, Codex, Quit
- HUD: HP bars (yours + teammates), potions, abilities and cooldowns, ultimate meter, active relic, current floor/biome, gold, ore, relic icons, active synergies, minimap
- Pause, inventory/run screen (relics, stats, synergy progress, floor map)
- Town menus, skill tree screen, character + class select, class tree and mastery screen, Ascension choice popup, weapon select
- Relic/ability choice popups with clear descriptions and tags
- Rope vote prompt, death screen (lost/kept, stats), victory screen
- Dialogue box with portraits, codex, settings (audio, video, screen shake, key rebinding)

## 17. Art and Audio Direction

- Pixel art, isometric 2:1 tiles (64x32 base). Characters as 8-direction sprite sheets
- Each biome has its own palette and lighting (`PointLight2D`, `CanvasModulate` to darken deeper biomes)
- Particle effects (`GPUParticles2D`) for every element, ability, and relic proc. Builds should look as crazy as they feel
- Music: town theme, one track per biome, mini-boss theme, unique boss themes for main bosses, final boss track
- SFX for every hit, dodge, pickup, ability, UI click
- Placeholder art early, final art pass in the second half

## 18. Technical Architecture (Godot 4.x)

### Folder structure
```
res://
  scenes/
    main/  town/  dungeon/  player/  enemies/  bosses/
    abilities/  projectiles/  pickups/  ui/  dialogue/  network/
  scripts/
    autoload/     (GameState, SaveManager, Events, AudioManager, NetworkManager, StoryManager, TimeManager)
    components/   (Health, Hitbox, Hurtbox, StateMachine, StatusEffects, StatBlock)
    data/         (Resource class definitions)
  data/
    characters/  classes/  ascensions/  weapons/  mutations/  abilities/  relics/  synergies/
    enemies/  bosses/  biomes/  skills/  dialogue/  lore/
  assets/
    sprites/  tilesets/  vfx/  audio/  fonts/
```

### Autoloads
- **GameState:** run data and persistent data
- **SaveManager:** save/load to `user://save.json`
- **Events:** global signal bus (`enemy_died`, `player_dodged`, `crit_landed`, `room_cleared`, `boss_defeated`, etc.)
- **NetworkManager:** hosting, joining, player spawning, peer tracking
- **StoryManager:** story flags, dialogue state, lore unlocks
- **AudioManager:** music crossfades, SFX
- **TimeManager:** enemy-side time multiplier for slow and stop effects (see section 12)

### Data-driven content (the key to having lots of content)
Everything is a custom `Resource` so new content is a new `.tres` file plus a small effect script, not a new system:
- `CharacterData`, `ClassData`, `ClassPairData`, `AscensionData`, `ClassTreeNodeData`, `WeaponData`, `MutationData`, `AbilityData`, `RelicData`, `SynergyData`, `EnemyData`, `BossData`, `BiomeData`, `SkillNodeData`, `DialogueData`

### Effect / trigger system (how relics stay "cool" and not just stat buffs)
- Relics, mutations, and synergies hook into **events** from the Events bus: `on_hit`, `on_crit`, `on_kill`, `on_dodge`, `on_damaged`, `on_ability_cast`, `on_room_enter`, `on_room_clear`, every X seconds
- Each relic has an effect script that listens to the events it cares about and spawns things (explosions, clones, projectiles, status effects)
- Stat relics apply modifiers through a central `StatBlock` (base + flat + percent), never editing base values
- Proc chains need a limit (a proc can't trigger more than 3 levels deep, and procs created by procs can't trigger the same relic again) so builds don't freeze the game
- Class passives, class skills, and Ascensions use the same event hooks and `StatBlock`, so they stack with relics automatically
- In co-op, effects only run on the host, which then spawns the results with `MultiplayerSpawner` so every client sees them

### Other systems
- Components shared by player, enemies, bosses (Health, Hitbox, Hurtbox, StatusEffects)
- Node-based state machines for player, enemies, bosses (boss phases as states)
- Pathfinding with `AStarGrid2D` or `NavigationAgent2D`
- Y-sort world node, `Camera2D` with smoothing, shake, and co-op framing (zooms out to fit all players)
- Object pooling for projectiles and damage numbers (lots of procs = lots of objects)

### Saving
Persistent only: town, skill tree, unlocks, characters, classes, Class XP and mastery, story flags, codex, banked currency, achievements. Saves on returning to town, buying upgrades, and quitting. Runs aren't saved mid-run.

## 19. Team Split

| Developer A: The Pit | Developer B: The Surface + Systems |
|---|---|
| Player controller, combat feel | Networking (NetworkManager, sync) |
| Weapons, mutations, classes and Ascensions | Relic effect/trigger system, synergies |
| Abilities and ultimates | Stat system, status effects, element combos |
| Enemies and AI | Town, buildings, NPCs |
| Bosses and mini-bosses | Story, dialogue system, lore codex |
| Floor generation, room types, hazards | Skill tree, class trees and mastery, save/load, UI and menus |

**Both:** art, audio, balancing, playtesting, and bulk content (writing relics, abilities, enemies as data files).

**Git rules:** each dev owns their scenes, small commits, feature branches, pull before working. Never edit the same `.tscn` at the same time.

## 20. 12-Week Milestones

Every week ends with a playable build. Content weeks are heavy because content is data files on top of finished systems.

| Week | Goal | Done when |
|---|---|---|
| 1 | Foundation + networking | Isometric TileSet, Y-sort, player movement, camera. 2 players can connect and see each other move (host + client) |
| 2 | Combat core | Light/heavy attacks, dodge, weapon swap, Health/Hitbox/Hurtbox components, 3 enemies with telegraphs, all synced in co-op |
| 3 | Floor generation | Procedural floors with Start, Combat, Elite Combat, Treasure, Rope, and Exit rooms, locking combat rooms, seed sync for co-op, downed/revive |
| 4 | Effect system + loot | Events bus, StatBlock, TimeManager, status effects, element combos, 20 relics, Shrine rooms, elites with affixes, gold/ore/Echo drops |
| 5 | Abilities + classes v1 + extraction | Ability system with 10 abilities, Rune rooms, ultimates, class system with Warrior, Ranger, Mage (passives + class skills), rope points and votes, death rules, town v1, save/load |
| 6 | Biome 1 complete + story base | All Biome 1 enemies, Boomer Jack, The Foreman, dialogue system, first NPCs and story flags, Shop rooms, Rest rooms |
| 7 | Skill tree + weapons + Ascensions | Full skill tree UI and all branches, 10 weapons, anvil rooms with mutations, Ascensions for the first 3 classes, class XP and mastery, rescue mission system |
| 8 | Biomes 2 and 3 | Enemies, hazards, mini-bosses, bosses for Fungal Caverns and Crystal Hollows, 40 relics, synergies |
| 9 | Biomes 4 and 5 | Drowned City and Ember Forge with all enemies and bosses, all 19 weapons, all 30 abilities, characters 2 to 4, Rogue, Necromancer, Engineer, Lightbearer (unlocked through their rescues) |
| 10 | Biome 6 + final boss + story | The Heart, The Hollow You, The Sinkhole 3-phase fight, all 3 endings, all NPC dialogue, Lore rooms and 40+ lore pages |
| 11 | Content and endgame | Tier 2 Ascensions and all class trees, class pair bonuses, all 88 relics, Cursed Altars, Challenge rooms, Secret rooms, all 120 mutations, secret bosses, Deep Mode, heat levels, all town buildings |
| 12 | Polish | Final art/audio/VFX pass, balancing, co-op bug fixing, achievements, settings, external playtests |

## 21. Cut List (only if seriously behind, cut in this order)

1. Secret bosses beyond The Rat King
2. Daily Dive and leaderboards
3. Heat levels
4. Reduce mutations from 6 to 3 per weapon
5. Online co-op becomes local co-op only
6. Biome 5 (Ember Forge) cut, its boss moves into Biome 6
7. Characters reduced from 4 to 2
8. Tier 2 Ascensions cut (keep Tier 1)
9. Classes reduced from 7 to 5 (drop Engineer and Lightbearer)

**Never cut:** combat feel, the effect/trigger system, extraction loop, skill tree, story main path, at least 5 classes with Ascensions, at least 4 biomes with mini-bosses and bosses, save system.

## 22. Stretch Goals

- Steam lobbies and Steam release
- Controller support for all menus
- 6 player co-op
- New Game+ with a 7th biome
- Run history and build sharing (export a run as a code)
- Web export on itch.io (solo mode)

## 23. Testing and Quality Bar

- Debug console: spawn enemy, give relic by name, give gold, skip floor, unlock all skills, set seed, god mode
- Floor generator: test 500+ seeds for unreachable rooms or exits
- Co-op: test with 2 machines every week, not just at the end. Test lag with simulated latency
- Every class + Ascension gets tested solo and in co-op
- Every time-slow/stop effect is tested in co-op to make sure it never freezes another player
- Every relic gets a quick test: does it trigger, does it stack, does it work in co-op
- Proc chains capped so no build crashes or freezes the game
- Stable 60 FPS with 60+ units on screen (enemies + minions + turrets, worst case is 4 Necromancers or Engineers in co-op) and heavy VFX
- External playtests (at least 5 people) starting Week 9

## 24. Out of Scope

- Voice acting
- Mobile
- PvP
- Player trading
