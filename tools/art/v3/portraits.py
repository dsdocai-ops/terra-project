"""v3 dialogue portraits: a 34x34 bust (eyes with whites, iris and shine) on a
48x48 canvas, shipped 2x as 96x96."""

from __future__ import annotations

from .core import Canvas, dk, lt, mix

BONE, GOLD, WHITE, STEEL_D = "#efe3c4", "#f2c040", "#fffbe8", "#6c7a8c"


def _opts(c: dict) -> dict:
    p = dict(c)
    for k, col in c.get("cloth", []):
        if k == "overalls":
            p["overalls"] = c.get("pants")
        elif k not in ("plaid", "vest"):
            p[k] = col
    if c.get("mask"):
        p["hat"], p["maskC"] = "plague", c["mask"]
    if c.get("horns"):
        p["hat"] = "horns"
    return p


def bust(c: dict) -> Canvas:
    o = _opts(c)
    s = Canvas(34, 34)
    skin, hair, shirt, hs = o["skin"], o.get("hair", "#6a3a22"), o["shirt"], o.get("hairStyle")
    s.ell(17, 33, 13, 7, shirt); s.rect(4, 30, 26, 4, shirt); s.rect(14, 26, 6, 3, dk(skin, .15))
    if o.get("robe"):
        s.ell(17, 33, 13, 7, o["robe"]); s.rect(4, 30, 26, 4, o["robe"])
    if o.get("armor"):
        s.ell(17, 33, 13, 7, o["armor"]); s.ell(8, 29, 5, 3, lt(o["armor"], .2)); s.ell(26, 29, 5, 3, o["armor"])
    if o.get("cape"):
        s.rect(3, 30, 5, 4, o["cape"]); s.rect(26, 30, 5, 4, o["cape"])
    if o.get("overalls"):
        s.rect(11, 28, 2, 6, o["overalls"]); s.rect(21, 28, 2, 6, o["overalls"]); s.px(11, 30, GOLD); s.px(22, 30, GOLD)
    if o.get("apron"):
        s.rect(11, 29, 12, 5, o["apron"])
    if o.get("scarf"):
        s.ell(17, 27, 9, 2, o["scarf"])
    hat = o.get("hat")
    if hs == "long":
        s.rect(6, 9, 22, 20, hair)
    if hs == "bob":
        s.rect(6, 9, 22, 14, hair)
    if hs == "ponytail":
        s.ell(28, 18, 3, 7, hair)
    if hat in ("hood", "plague", "veil"):
        s.ell(17, 15, 12, 13, o["hatC"]); s.rect(5, 15, 24, 14, o["hatC"])
    s.ell(17, 16, 9, 10, skin); s.rect(9, 11, 17, 9, skin)
    s.ell(25, 17, 1, 6, dk(skin, .12)); s.ell(17, 25, 6, 1, dk(skin, .12))
    s.rect(7, 14, 2, 4, skin); s.rect(26, 14, 2, 4, skin); s.px(7, 15, dk(skin, .2)); s.px(27, 15, dk(skin, .2))
    if not o.get("noFace"):
        iris = o.get("glow") or o.get("eye", "#3a5a8a")
        for x, y in ((11, 14), (19, 14)):
            s.rect(x, y, 4, 4, "#fffaf0"); s.rect(x + 1, y, 2, 4, iris); s.rect(x + 1, y + 2, 2, 2, dk(iris, .5)); s.px(x + 1, y, "#ffffff")
            s.rect(x, y - 1, 4, 1, dk(skin, .55))
        s.rect(11, 12, 4, 1, dk(hair, .15)); s.rect(19, 12, 4, 1, dk(hair, .15))
        s.px(17, 19, dk(skin, .25)); s.px(16, 20, dk(skin, .15))
        if not o.get("noBlush"):
            s.rect(10, 19, 2, 1, mix(skin, "#e8607a", .35)); s.rect(22, 19, 2, 1, mix(skin, "#e8607a", .35))
        s.rect(15, 22, 4, 1, dk(skin, .4)); s.px(14, 21, dk(skin, .35)); s.px(19, 21, dk(skin, .35))
    if o.get("beard"):
        b = o["beard"]
        s.ell(17, 23, 9, 6, b); s.rect(8, 18, 18, 4, b); s.rect(14, 21, 6, 2, dk(b, .4)); s.rect(12, 20, 10, 1, lt(b, .15))
    if o.get("mustache"):
        s.rect(12, 20, 10, 2, o["mustache"]); s.px(11, 22, o["mustache"]); s.px(22, 22, o["mustache"])
    if hs and hs not in ("bald", "baldsides") and hat not in ("hood", "plague", "veil", "helm"):
        s.ell(17, 9, 10, 5, hair); s.rect(7, 9, 3, 7, hair); s.rect(24, 9, 3, 7, hair); s.rect(10, 11, 6, 2, hair); s.rect(18, 11, 4, 1, hair)
        s.ell(13, 6, 4, 1, lt(hair, .25))
        if hs == "spiky":
            s.tri(9, 7, 12, 5, 9, 1, hair); s.tri(14, 5, 18, 5, 15, 0, hair); s.tri(20, 5, 24, 6, 24, 1, hair)
        if hs == "bun":
            s.circ(17, 3, 3, hair)
        if hs == "bob":
            s.rect(6, 10, 3, 12, hair); s.rect(25, 10, 3, 12, hair); s.rect(10, 11, 14, 2, hair)
        if hs == "long":
            s.rect(6, 10, 3, 16, hair); s.rect(25, 10, 3, 16, hair)
    if hs in ("bald", "baldsides"):
        s.rect(7, 12, 2, 5, hair); s.rect(25, 12, 2, 5, hair); s.ell(14, 8, 3, 1, lt(skin, .35))
    hc, hc2 = o.get("hatC"), o.get("hatC2", GOLD)
    if hat == "miner":
        s.ell(17, 8, 11, 6, hc); s.rect(5, 10, 24, 2, dk(hc, .3)); s.ell(17, 5, 3, 2, "#fff6b0"); s.ell(12, 5, 3, 1, lt(hc, .4))
    elif hat == "cap":
        s.ell(17, 8, 10, 5, hc); s.rect(16, 10, 15, 2, dk(hc, .3)); s.ell(12, 6, 3, 1, lt(hc, .3))
    elif hat == "hood":
        s.ell(17, 9, 12, 7, hc); s.rect(5, 9, 4, 18, hc); s.rect(25, 9, 4, 18, dk(hc, .12)); s.rect(9, 11, 16, 1, dk(hc, .3))
    elif hat == "plague":
        m = o.get("maskC", BONE)
        s.ell(17, 9, 12, 7, hc); s.rect(5, 9, 4, 18, hc); s.rect(25, 9, 4, 18, dk(hc, .12)); s.rect(9, 11, 16, 12, m)
        s.circ(13, 15, 2, o.get("glow", "#8af06a")); s.circ(21, 15, 2, o.get("glow", "#8af06a")); s.tri(13, 19, 21, 19, 17, 29, dk(m, .15))
    elif hat == "veil":
        s.ell(17, 9, 12, 7, hc); s.rect(5, 9, 4, 20, hc); s.rect(25, 9, 4, 20, dk(hc, .1)); s.rect(9, 10, 16, 2, hc2)
    elif hat == "wizard":
        s.tri(8, 8, 26, 8, 22, -6, hc); s.ell(17, 9, 14, 2, dk(hc, .15)); s.rect(9, 6, 16, 2, hc2)
    elif hat == "helm":
        s.ell(17, 10, 11, 8, hc); s.rect(6, 10, 4, 12, hc); s.rect(24, 10, 4, 12, dk(hc, .2)); s.rect(16, 9, 2, 9, dk(hc, .1)); s.ell(12, 6, 3, 1, lt(hc, .45))
        if o.get("plume"):
            s.ell(17, 1, 3, 3, o["plume"])
    elif hat == "horns":
        s.ell(17, 8, 11, 6, hc or "#7a2a2a"); s.rect(6, 10, 22, 2, dk(hc or "#7a2a2a", .3)); s.tri(6, 8, 9, 6, 2, -2, BONE); s.tri(28, 8, 25, 6, 32, -2, BONE)
    elif hat == "crown":
        c = hc or GOLD
        s.rect(9, 5, 16, 4, c); s.tri(9, 5, 12, 5, 9, 1, c); s.tri(15, 5, 19, 5, 17, 0, c); s.tri(22, 5, 25, 5, 25, 1, c)
        for x in (12, 17, 22):
            s.px(x, 6, o.get("gem", "#e83a5a"))
    elif hat == "tophat":
        s.rect(10, -1, 14, 10, hc); s.rect(6, 8, 22, 2, dk(hc, .2)); s.rect(10, 6, 14, 2, hc2)
    elif hat == "bandana":
        s.ell(17, 8, 10, 4, hc); s.rect(7, 9, 20, 2, hc); s.tri(26, 9, 31, 7, 30, 13, hc)
    elif hat == "goggles":
        s.rect(7, 9, 20, 2, "#3a2a2a"); s.circ(13, 9, 3, STEEL_D); s.circ(21, 9, 3, STEEL_D); s.circ(13, 9, 1, "#9ae0f0"); s.circ(21, 9, 1, "#9ae0f0")
    if o.get("halo"):
        s.ell(17, 1, 8, 1, GOLD)
    return s.outline()


def portrait(c: dict) -> Canvas:
    out = Canvas(48, 48)
    out.blit(bust(c), 7, 14)
    return out
