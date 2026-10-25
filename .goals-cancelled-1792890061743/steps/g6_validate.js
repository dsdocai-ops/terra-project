#!/usr/bin/env node
// G6 validator: required entries per NPC file, declared-flag check, goto resolution.
// False-positive fix: the declared set comes from flags.<namespace> keys (nested object),
// not from scanning the top-level JSON string.
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const flagsRaw = JSON.parse(fs.readFileSync(path.join(ROOT, 'data', 'dialogue', 'flags.json'), 'utf8'));

// Build declared set: every name under each namespace object, as "ns.name".
const declared = new Set();
for (const [ns, entries] of Object.entries(flagsRaw.flags || {})) {
  const names = Array.isArray(entries) ? entries : Object.keys(entries || {});
  for (const n of names) declared.add(`${ns}.${n}`);
}

const REQUIRED = ['intro', 'act_1', 'act_2_stub', 'act_3_stub', 'endings_stub', 'default'];
const NPCS = ['hilde', 'gruff', 'moss', 'pip', 'sister_ash', 'old_tom', 'vesper', 'rescued_miner_v1'];

function walkFlags(node, out) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node)) { node.forEach((n) => walkFlags(n, out)); return; }
  for (const [k, v] of Object.entries(node)) {
    if (k === 'flag' || k === 'flag_not') out.add(String(v));
    else walkFlags(v, out);
  }
}
function walkGotos(node, out) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node)) { node.forEach((n) => walkGotos(n, out)); return; }
  for (const [k, v] of Object.entries(node)) {
    if (k === 'goto') out.add(String(v));
    else walkGotos(v, out);
  }
}

let errors = 0;
const check = (ok, msg) => { if (!ok) { errors++; console.log('FAIL: ' + msg); } };

for (const npc of NPCS) {
  const file = path.join(ROOT, 'data', 'dialogue', `${npc}.json`);
  if (!fs.existsSync(file)) { check(false, `${npc}: file missing`); continue; }
  const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
  const ids = new Set((doc.entries || []).map((e) => e.id));

  for (const req of REQUIRED) check(ids.has(req), `${npc}: missing required entry "${req}"`);

  const usedFlags = new Set(); walkFlags(doc, usedFlags);
  for (const f of usedFlags) check(declared.has(f), `${npc}: undeclared flag "${f}"`);

  const usedGotos = new Set(); walkGotos(doc, usedGotos);
  for (const g of usedGotos) check(ids.has(g), `${npc}: goto "${g}" unresolved (no entry with that id)`);

  // on_end set_flags must also be declared
  for (const e of doc.entries || []) {
    for (const sf of ((e.on_end && e.on_end.set_flags) || [])) {
      check(declared.has(sf), `${npc}: on_end set_flags undeclared "${sf}"`);
    }
  }
  console.log(`${npc}: entries=${ids.size} flags=${usedFlags.size} gotos=${usedGotos.size} ok=${errors === 0}`);
}

console.log(errors === 0 ? 'ALL CHECKS PASS' : `${errors} FAILURES`);
process.exit(errors === 0 ? 0 : 1);
