"""v3 hero template: hand-pixeled 16x32 body with layered hair, hats, clothes and
held items, drawn in front, back and side views with an idle breath and a 6-frame
walk. One frame is 24x38 (body origin 4,5); boots end on frame row 35.

Characters: K k s w skin, E/e eye white/iris, x blush, m mouth, T t c C shirt,
g/y belt. Layers: H h a A + hair; O o n N M material (outline, shadow, base, light,
shine); L glow; Y gold; 1 2 3 wood (outline, base, light).
"""

from __future__ import annotations

from .core import Canvas, ramp

W, H, OX, OY = 24, 38, 4, 5
FEET_ROW = OY + 30

UPPER_FRONT = [
    "................",
    ".....KKKKKK.....",
    "...KKwsssssKK...",
    "..KwsssssssskK..",
    "..KwsssssssskK..",
    "..KwsssssssskK..",
    "..KwsssssssskK..",
    "..KwsssssssskK..",
    "..KwsEesseEskK..",
    "..KwssessesskK..",
    "..KwxxssssxxkK..",
    "..KwsssmmssskK..",
    "...KksssssskK...",
    "....KKkkkkKK....",
    "..TTCcckkcccTT..",
    ".TCcccccccccctT.",
    ".TCctcccccctctT.",
    ".TCctcccccctctT.",
    ".TCctcccccctctT.",
    ".TCcgggyygggctT.",
    ".KwsTccccccTskK.",
    ".KKKTttttttTKKK.",
]
UPPER_BACK = [r.replace("E", "s").replace("e", "s").replace("x", "s").replace("m", "s") if 8 <= i <= 11 else r
              for i, r in enumerate(UPPER_FRONT)]
UPPER_SIDE = [
    "................",
    ".....KKKKKK.....",
    "....KwssssssK...",
    "...KwsssssssK...",
    "...KwssssssskK..",
    "...KwssssssskK..",
    "...KwssssssskK..",
    "...KwssssssskK..",
    "...KwssssssEeK..",
    "...KwsssssssesK.",
    "...KwsssssxxsK..",
    "...KwssssssmsK..",
    "....KksssssskK..",
    ".....KKkkkKK....",
    "....TTCcckcTT...",
    "....TCccccccT...",
    "....TCcTCcTcT...",
    "....TCcTCcTcT...",
    "....TCcTCcTcT...",
    "....TCgTCcTgT...",
    "....TttKwsKtT...",
    "....TttKKKttT...",
]
LEGS_FRONT = [
    "....PQqppqqP....",
    "....PQqPPqpP....",
    "....PQqPPqpP....",
    "....PQqPPqpP....",
    "....PQpPPqpP....",
    "....RUuRRuuR....",
    "...RUuuRRuurR...",
    "...RuurRRuurR...",
    "...RRRR..RRRR...",
]


def _face_shift(rows: list[str], d: int) -> list[str]:
    """Turn the face one pixel toward a diagonal facing (eyes, blush, mouth move)."""
    out = rows[:]
    for i in range(8, 12):
        r = out[i]
        core = r[4:12]
        core = ("s" * d + core[:-d]) if d > 0 else (core[-d:] + "s" * -d)
        out[i] = r[:4] + core + r[12:]
    return out


HAIR_FRONT = {
    "short": (0, ["....HHHHHHHH....", "...HaAAAaaaahH..", "..HaA+AaaaaaahHH", "..HaAAaaaaaahhH.",
                  "..HahaahaaahhhH.", "..Hhh.hh..hhhhH.", "..Hh........hH..", "..H..........H.."]),
    "bob": (0, ["....HHHHHHHH....", "...HaAAAaaaahH..", "..HaA+AaaaaaahH.", "..HaAAaaaaaahhH.",
                "..HaaaaaaaaahhH.", "..HhaahhaahahhH.", ".HaH........HhH.", ".HaH........HhH.",
                ".HaH........HhH.", ".HaH........HhH.", ".HhH........HhH.", ".HHH........HHH."]),
    "spiky": (-3, ["....H..H...H....", "...HaHHaH.HaH...", "..HaAaaAaHaahH..", "..HaA+AaaaaahH..",
                   ".HaAAaaaaaaahhH.", "..HaAaaaaaaahhH.", "..HahaahaaahhhH.", "..Hhh.hh..hhhhH.",
                   "..Hh........hH..", "..H..........H.."]),
    "ponytail": (0, ["....HHHHHHHH....", "...HaAAAaaaahH..", "..HaA+AaaaaaahHH", "..HaAAaaaaaahhaH",
                     "..HahaahaaahhhaH", "..Hhh.hh..hhhhaH", "..Hh........hHhH", "..H..........HhH",
                     ".............HhH", ".............HH."]),
    "fringe": (4, ["..HaaAaaaaaahH..", "..Hhh.hh..hhhH..", "..Hh........hH..", "..H..........H.."]),
    "baldsides": (5, ["..Hh........hH..", "..Hh........hH..", "..H..........H.."]),
}
HAIR_FRONT["long"] = (0, HAIR_FRONT["bob"][1][:11] + [".HaH........HhH.", ".HhH........HhH.", ".HaH........HhH.", ".HHH........HHH."])
HAIR_FRONT["bun"] = (-3, ["......HHHH......", ".....HaAahH.....", ".....HhhhhH....."] + HAIR_FRONT["short"][1])
BEARD = (9, ["..H..........H..", "..HaA......aaH..", "..HaaAhmmhaaaH..", "..HaaaaaaaaahH..", "...HaaaaaaahH...", "....HHaaahHH...."])
MUSTACHE = (10, ["................", "....HaAmmahH...."])

BACK_BASE = ["....HHHHHHHH....", "...HaAAAaaaahH..", "..HaA+AaaaaaahH.", "..HaAAaaaaaahhH.", "..HaaaaaaaaahhH.",
             "..HahaahaaahhhH.", "..HhaahhaahhhhH.", "..HhhaahhahhhhH.", "..HhhhhhhhhhhhH.", "...HHhhhhhhhHH.."]
HAIR_BACK = {
    "short": (0, BACK_BASE),
    "bob": (0, BACK_BASE + ["..HhhhhhhhhhhH..", "..HhhhhhhhhhhH..", "..HHHHHHHHHHHH.."]),
    "long": (0, BACK_BASE + ["..HhhhhhhhhhhH..", "..HhhhhhhhhhhH..", "..HhhhhhhhhhhH..", "..HhhhhhhhhhhH..", "...HHHHHHHHHH..."]),
    "spiky": (-3, ["....H..H...H....", "...HaHHaH.HaH...", "..HaAaaAaHaahH.."] + BACK_BASE[1:]),
    "ponytail": (0, BACK_BASE + ["......HahH......", "......HahH......", "......HahH......", ".......HH......."]),
    "fringe": (4, BACK_BASE[4:]),
    "baldsides": (5, ["..Hh........hH..", "..Hh........hH..", "..H..........H.."]),
    "bun": (-3, ["......HHHH......", ".....HaAahH.....", ".....HhhhhH....."] + BACK_BASE),
}
SIDE_BASE = ["....HHHHHHH.....", "...HaA+AaaaH....", "..HaAAaaaaaaH...", "..HaaaaaaaaahH..", "..HahaahhaahhH..",
             "..HhhhhhH..hH...", "..HhhhhH........", "..HhhhH.........", "..HhhH..........", "...HH..........."]
HAIR_SIDE = {
    "short": (0, SIDE_BASE),
    "bob": (0, SIDE_BASE[:9] + ["..HhhH..........", "..HhhH..........", "..HHH..........."]),
    "long": (0, SIDE_BASE[:9] + ["..HhhH..........", "..HhhH..........", "..HhhH..........", "..HhhH..........", "..HHH..........."]),
    "spiky": (-3, ["....H..H........", "...HaHHaH.......", "..HaAaaAaH......"] + SIDE_BASE[1:]),
    "ponytail": (0, [r if i < 3 else r for i, r in enumerate(SIDE_BASE)]),
    "fringe": (4, SIDE_BASE[4:]),
    "baldsides": (5, ["..HhH...........", "..HhH...........", "..HH............"]),
    "bun": (-3, ["....HHHH........", "...HaAahH.......", "...HhhhhH......."] + SIDE_BASE),
}
PONY_SIDE = (3, ["HH..............", "HaH.............", "HaH.............", ".HaH............", ".HhH............", "..HH............"])
BEARD_SIDE = (9, ["................", ".........HaaH...", "........HaAmhH..", "........HaaahH..", ".........HaaH...", "..........HH...."])

HOOD = ["....OOOOOOOO....", "...ONNnnnnnnO...", "..ONMNnnnnnnoO..", ".ONNnnnnnnnnnoO.", ".ONnOOOOOOOOnoO.",
        ".ONO........OoO.", ".ONO........OoO.", ".ONO........OoO.", ".ONO........OoO.", ".ONO........OoO.",
        ".ONO........OoO.", ".OnO........OoO.", ".OnnO......OooO.", "..OOnn....nnOO.."]
HELM = ["....." "OOOOOO.....", "....ONNnnnnO....", "...ONMNnnnnnO...", "..ONNnnnnnnnoO..", "..ONnnnnnnnnoO..",
        "..ONnnnnnnnnoO..", "..OnnOOOOOOnoO..", "..OnO..Nn..OoO..", "..OnO..Nn..OoO..", "..OnO..Nn..OoO..",
        "..OnO..Nn..OoO..", "..OnO......OoO..", "..OnO......OoO..", "..OOO......OOO.."]
HAT = {
    "miner": (-3, [".....OOOOOO.....", "....ONNnnnnO....", "...ONMNLLnnnO...", "..ONNnnLLnnnnO..", "..ONnnnnnnnnoO..",
                   "..ONnnnnnnnooO..", ".OOooooooooooOO.", "..OOOOOOOOOOOO.."]),
    "cap": (-2, [".....OOOOOO.....", "....ONNnnnnO....", "...ONMNnnnnnO...", "..ONNnnnnnnnoO..", "..ONnnnYnnnooOOO",
                 "..OoooooooooooNO", "...OOOOOOOOOOOO."]),
    "bandana": (0, ["....OOOOOOOO....", "...ONNnnnnnnO...", "..ONMNnnnnnnoO..", "..OnnnnnnnnnoOO.", "..OOOOOOOOOOOnoO",
                    ".............OnO", "..............OO"]),
    "hood": (-1, HOOD),
    "veil": (-1, [r if i != 3 else ".ONYYYYYYYYYYoO." for i, r in enumerate(HOOD)]),
    "wizard": (-5, [".........OO.....", "........ONO.....", ".......ONnO.....", "......ONnnO.....", ".....ONMnnoO....",
                    "....ONNnnnnoO...", "...OYYYYYYYYYO..", "OOONnnnnnnnnnoOO", ".OOooooooooooOO."]),
    "helm": (-2, HELM),
    "crown": (-3, ["...O...OO...O...", "...OO.ONNO.OO...", "...ONOnLLnONO...", "...ONNnLLnnnO...", "...OoooooooooO.."]),
    "tophat": (-6, ["....OOOOOOOO....", "....ONNnnnnO....", "....ONMnnnnO....", "....ONnnnnnO....", "....OYYYYYYO....",
                    "....OnnnnnnO....", ".OOOOOOOOOOOOOO.", "..OOOOOOOOOOOO.."]),
    "goggles": (2, ["...OOOO..OOOO...", ".OONMMnOONMMnOO.", "...OOOO..OOOO..."]),
}
EXTRA = {
    "horns": (-4, ["O..............O", "OnO..........OnO", ".OnO........OnO.", ".ONnO......ONnO.", "..ONO......ONO.."]),
    "plague": (4, ["...OnnnnnnnnO...", "...ONnnnnnnnO...", "...OnLLnnLLnO...", "...OnLLnnLLnO...", "...OnnnOOnnnO...",
                   "....OnNnnnoO....", "....OnNnnnoO....", ".....OnnnoO.....", "......OnoO......", ".......OO......."]),
    "halo": (-6, [".....YYYYYY.....", "....Y......Y....", ".....YYYYYY....."]),
    "plume": (-6, [".......OO.......", "......ONNO......", "......OnNO......", ".......On......."]),
    "ears": (5, [".O............O.", "ONO..........ONO", "OnnO........OnnO", ".OnO........OnO."]),
}
CLOTH = {
    "overalls": (14, [".....q....q.....", ".....q....q.....", ".....yqqqqy.....", ".....qQqqqq.....", ".....qQqqqq.....",
                      "....PqqqqqqP....", "....PqqqqqqP....", "....PppppppP...."]),
    "vest": (15, ["....On....nO...."] * 4),
    "scarf": (13, ["....ONNnnnnO....", "...ONMNnnnnoO...", "..OnOOOOOOOOO...", "..OnO...........", "..OoO...........", "..OOO..........."]),
    "plaid": (15, ["..o..o..o..o....", "................", "..o..o..o..o....", "................"]),
    "robe": (14, ["..OONnnnnnnoOO..", ".ONNnnnnnnnnnoO.", ".ONnOnnnnnnOnoO.", ".ONnOnnnnnnOnoO.", ".ONnOnnnnnnOnoO.",
                  ".ONnOYYYYYYOnoO.", "....ONnnnnnO....", "...ONnnnnnnoO...", "...ONnnnnnnoO...", "...ONnnOnnnoO...",
                  "..ONnnnOnnnnoO..", "..ONnnnOnnnnoO..", "..ONnnnOnnnnoO..", ".ONnnnnOnnnnnoO.", ".OooooooooooooO.",
                  ".OOOOOOOOOOOOOO."]),
    "apron": (15, [".....O....O.....", "....ONnnnnnO....", "....ONnnnnnO....", "....ONnnnnnO....", "....ONnnnnnO....",
                   "....ONnnnnnO....", "....ONnnnnoO....", "....ONnnnnoO....", "....OooooooO....", "....OOOOOOOO...."]),
    "armor": (14, ["OOOO.ONNnnO.OOOO", "ONMnOONMnnoOOnoO", "ONnoONnnnnnoOooO", "OOOOONnnnnnoOOOO", "....ONnnnnnoO..."]),
    "tail": (22, ["....PQqqqqpP....", "....PQqqqqpP....", ".....PQqqpP.....", ".....PQqqpP.....", "......PQpP......",
                  ".....PPqpPP.....", "....PQqPPqpP....", "...PQqP..PqpP...", "...PPP....PPP..."]),
}
SIDE_CLOTH = {
    "robe": (14, [".....OONnnoO....", "....ONNnnnnoO...", "....ONnnnnnoO...", "....ONnnnnnoO...", "....ONnnnnnoO...",
                  "....ONYYYYYoO...", "....ONnnnnnoO...", "....ONnnnnnoO...", "...ONnnnnnnoO...", "...ONnnnnnnnoO..",
                  "...ONnnnnnnnoO..", "...ONnnnnnnnoO..", "..ONnnnnnnnnoO..", "..ONnnnnnnnnnoO.", "..OooooooooooO..",
                  "..OOOOOOOOOOOO.."]),
    "armor": (14, ["....OOOOOOO.....", "...ONMnnnnoO....", "...ONnnnnnoO....", "....OOOOOOO....."]),
    "scarf": (13, [".....ONNnnnO....", "....ONMNnnnoO...", "...OnOOOOOOO....", "...OnO..........", "...OOO.........."]),
    "vest": (15, ["....On....nO...."] * 4),
    "apron": (15, ["...........O....", "..........ONO...", "..........ONO...", "..........ONO...", "..........ONO...",
                   "..........OnO...", "..........OOO..."]),
    "overalls": (14, ["........q.......", "........q.......", "........q.......", "....PqqqqqqqP...", "....PqqqqqqqP..."]),
}

ITEM = {
    "pick": (13, 11, ["..OOOOO..", ".ONMNNnO.", "ONnO3OnoO", "Oo.O2O.oO", "O..O2O..O", "...O2O...", "...O2O...", "...O3O...",
                      "...O2O...", "...O2O...", "...O2O...", "...O2O...", "...OOO..."]),
    "hammer": (13, 12, ["OOOOOOOOO", "ONMNNnnoO", "ONnnnnnoO", "OoooooooO", "OOOO2OOOO", "...O3O...", "...O2O...",
                        "...O2O...", "...O2O...", "...O2O...", "...O2O...", "...OOO..."]),
    "lanternstaff": (15, 6, [".OOOOO...", "O32222O..", "O2OOO2O..", "OO...O2O.", "O3O.OOOOO", "O2O.ONLNO", "O2O.OLLLO",
                             "O2O.OLLoO", "O2O.OOOOO"] + ["O2O......"] * 10 + ["OOO......"]),
    "dagger": (15, 18, ["..O..", ".OMO.", ".ONO.", ".ONO.", ".OnO.", "OYYYO", ".O2O.", ".OOO."]),
    "sword": (15, 12, ["..O..", ".OMO.", ".ONO.", ".ONO.", ".ONO.", ".ONO.", ".ONO.", ".ONO.", ".ONO.", ".OnO.", ".OnO.",
                       "OYYYO", ".O2O.", ".O2O.", ".OOO."]),
    "staff": (15, 5, [".OOO.", "ONMNO", "ONnnO", "OnnoO", ".OOO."] + [".O2O."] * 16 + [".OOO."]),
    "bow": (17, 18, [".OO.", "O32O", "O2OO", "O2.O", "O2.O", "O2.O", "O2.O", "O2.O", "O2.O", "O2.O", "O2.O", "O2OO", "O32O", ".OO."]),
    "crossbow": (12, 22, ["........O.", "OOOOOOOONO", "O3222222NO", "OOOOOOOONO", "........O."]),
    "spear": (16, 3, ["..O..", ".OMO.", ".ONO.", "OnNnO", ".OOO."] + [".O2O."] * 18 + [".OOO."]),
    "scythe": (10, 5, ["..OOOOOO..", ".ONMNNnoO.", "ONnOOOOOO.", "OnO....O2O", "OO.....O2O"] + [".......O2O"] * 16 + [".......OOO"]),
    "axe": (16, 11, [".OOOO..", ".O2ONO.", ".O2ONNO", ".O2ONnO", ".O2OnO.", ".O2OO.."] + [".O2O..."] * 9 + [".OOO..."]),
    "wrench": (15, 16, ["OO.OO", "ONONO", ".ONO."] + [".ONO."] * 7 + [".OOO."]),
    "cannon": (12, 22, ["..OOOOOOOOO", ".OONMMNNnOO", "OOnnnnnnnoO", ".OOooooooOO", "..OOOOOOOOO", "...O2O.....", "...OOO....."]),
    "bomb": (16, 21, ["....OL", "...O..", ".OOOO.", "OnMnnO", "OnnnnO", "OonnoO", ".OOOO."]),
    "orb": (16, 20, [".OOO.", "ONMNO", "ONnnO", "OnnoO", ".OOO."]),
    "book": (15, 21, ["OOOOOO", "ONNnoO", "ONYnoO", "ONnnoO", "OooooO", "OOOOOO"]),
    "lantern": (16, 24, ["..O..", ".OOO.", "OLLLO", "OLMLO", "OLLLO", ".OOO."]),
    "dynamite": (17, 20, ["...L", "..O.", "OOO.", "OnO.", "OnO.", "OnO.", "OOO."]),
    "shield": (0, 19, ["OOOOOOO", "ONMNnoO", "ONYYYoO", "ONnYnoO", ".ONnoO.", "..OOO.."]),
}

WOOD = ramp("#a8703a")
SKIN_BLUSH = "#f0907a"


def _pal(r, chars: str) -> dict[str, str]:
    return {c: r[i] for i, c in enumerate(chars) if c != "_"}


class Hero:
    """One character definition (a dict of options) rendered in any facing and frame."""

    def __init__(self, o: dict) -> None:
        self.o = o
        g = o.get("glow")
        self.skin = ramp(o["skin"], 10)
        self.hair = ramp(o.get("hair", "#5a3a2a"), 6)
        shirt, pants = ramp(o["shirt"]), ramp(o.get("pants", o["shirt"]))
        boots, belt = ramp(o.get("boots", "#7a4a2a")), ramp(o.get("belt", "#6a3e22"))
        self.pants, self.boots = pants, boots
        self.base = {**_pal(self.skin, "Kksw"), **_pal(shirt, "TtcC"), **_pal(pants, "PpqQ"),
                     "e": g or o.get("eye", "#3a2a5a"), "E": ramp(g)[4] if g else "#fffaf0",
                     "x": self.skin[2] if o.get("noBlush") else SKIN_BLUSH, "m": self.skin[1],
                     "R": boots[0], "r": boots[1], "u": boots[2], "U": boots[3], "g": belt[2], "y": belt[4]}
        self.hair_map = {"H": self.hair[0], "h": self.hair[1], "a": self.hair[2], "A": self.hair[3], "+": self.hair[4], "m": self.skin[1]}

    def layer(self, base: str, extra: dict | None = None) -> dict[str, str]:
        r, g = ramp(base), self.o.get("glow")
        m = {"O": r[0], "o": r[1], "n": r[2], "N": r[3], "M": r[4], "L": ramp(g)[3] if g else "#fff3a8", "Y": "#f6c84a",
             "1": WOOD[0], "2": WOOD[2], "3": WOOD[3]}
        if extra:
            m.update(extra)
        return m

    # -- drawing helpers ------------------------------------------------------
    @staticmethod
    def _put(s: Canvas, y: int, rows: list[str], cmap: dict, dx: int = 0, dy: int = 0) -> None:
        s.rows(OX + dx, OY + y + dy, rows, cmap)

    def _legs(self, s: Canvas, view: str, frame: int) -> None:
        o = self.o
        if o.get("noLegs"):
            return
        walk = frame >= 2
        f = frame - 2
        if view == "side":
            p, b = self.pants, self.boots
            dx = (0, 1, 2, 0, -1, -2)[f] if walk else 0
            for leg, off, shade in ((1, -dx, True), (0, dx, False)):
                x = OX + 6 + off
                pc = p[1] if shade else p[2]
                s.rect(x, OY + 22, 3, 5, pc)
                s.rect(x - 1, OY + 22, 1, 5, p[0]); s.rect(x + 3, OY + 22, 1, 5, p[0])
                if not shade:
                    s.rect(x, OY + 22, 1, 5, p[3])
                bc = b[1] if shade else b[2]
                s.rect(x - 1, OY + 27, 5, 1, b[0]); s.rect(x, OY + 27, 3, 1, bc)
                s.rect(x - 1, OY + 28, 6, 1, b[0]); s.rect(x, OY + 28, 4, 1, bc)
                s.rect(x - 1, OY + 29, 6, 1, b[0]); s.rect(x, OY + 29, 4, 1, b[1])
                s.rect(x - 1, OY + 30, 6, 1, b[0])
            return
        lift_l = (0, 1, 1, 0, 0, 0)[f] if walk else 0
        lift_r = (0, 0, 0, 0, 1, 1)[f] if walk else 0
        for j, row in enumerate(LEGS_FRONT):
            for i, ch in enumerate(row):
                c = self.base.get(ch)
                if not c:
                    continue
                lift = lift_l if i <= 7 else lift_r
                s.px(OX + i, OY + 22 + j - lift, c)

    def render(self, facing: str, frame: int) -> Canvas:
        o = self.o
        view = "front" if facing in ("s", "se", "sw") else "back" if facing in ("n", "ne", "nw") else "side"
        s = Canvas(W, H)
        bob = 1 if (frame == 1) or (frame >= 2 and (frame - 2) in (0, 3)) else 0
        self._legs(s, view, frame)
        up = Canvas(W, H)
        self._upper(up, view, facing)
        s.blit(up, 0, bob)
        if o.get("tint"):
            s.tint(o["tint"], o.get("tintAmt", 0.5))
        if facing in ("w", "sw", "nw") and view != "front":
            s = s.flip_x()
        return s

    def _upper(self, s: Canvas, view: str, facing: str) -> None:
        o, P = self.o, self._put
        hs, hat = o.get("hairStyle"), o.get("hat")
        covered = hat in ("hood", "veil", "helm")
        if o.get("wings"):
            w = ramp(o["wings"])
            s.tri(OX + 2, OY + 16, OX - 4, OY + 8, OX - 3, OY + 22, w[0]); s.tri(OX + 2, OY + 16, OX - 3, OY + 10, OX - 2, OY + 20, w[3])
            s.tri(OX + 13, OY + 16, OX + 19, OY + 8, OX + 18, OY + 22, w[0]); s.tri(OX + 13, OY + 16, OX + 18, OY + 10, OX + 17, OY + 20, w[2])
        cape = ramp(o["cape"]) if o.get("cape") else None
        if cape and view != "back":
            x0 = OX + (2 if view == "front" else 1)
            s.rect(x0, OY + 14, 12 if view == "front" else 8, 15, cape[0]); s.rect(x0 + 1, OY + 14, 10 if view == "front" else 6, 14, cape[1])
            s.rect(x0 + 1, OY + 14, 4, 13, cape[2])
        if view in ("back", "side") and o.get("item"):
            self._item(s, view, behind=view == "back")
        if view == "front" and hs in ("long", "bob") and not covered:
            n = 12 if hs == "long" else 9
            s.rect(OX + 1, OY + 3, 14, n, self.hair[1]); s.rect(OX + 1, OY + 3, 1, n, self.hair[0]); s.rect(OX + 14, OY + 3, 1, n, self.hair[0])
        if hat in ("hood", "veil") and view == "front":
            s.rect(OX + 1, OY + 3, 14, 12, ramp(o["hatC"])[1])
        upper = UPPER_FRONT if view == "front" else UPPER_BACK if view == "back" else UPPER_SIDE
        if facing == "se":
            upper = _face_shift(upper, 1)
        elif facing == "sw":
            upper = _face_shift(upper, -1)
        P(s, 0, upper, self.base)
        if o.get("tail"):
            P(s, *CLOTH["tail"], {**self.base, **_pal(ramp(o["tail"]), "PpqQ")})
        for k, col in o.get("cloth", []):
            table = SIDE_CLOTH if view == "side" else CLOTH
            if k not in table or (view == "back" and k == "apron"):
                continue
            y, rows = table[k]
            P(s, y, rows, self.base if k == "overalls" else self.layer(col))
        if o.get("ears") and view != "side":
            P(s, *EXTRA["ears"], self.layer(o["ears"]))
        if hs and not covered:
            hair = (HAIR_FRONT if view == "front" else HAIR_BACK if view == "back" else HAIR_SIDE).get(hs)
            if hair:
                P(s, hair[0], hair[1], self.hair_map)
            if hs == "ponytail" and view == "side":
                P(s, *PONY_SIDE, self.hair_map)
        if o.get("beard") and view != "back":
            br = ramp(o["beard"])
            P(s, *(BEARD if view == "front" else BEARD_SIDE), {"H": br[0], "h": br[1], "a": br[2], "A": br[3], "m": self.skin[0]})
        if o.get("mustache") and view == "front":
            mr = ramp(o["mustache"])
            P(s, *MUSTACHE, {"H": mr[0], "h": mr[1], "a": mr[2], "A": mr[3], "m": self.skin[0]})
        if hat:
            y, rows = HAT[hat]
            if view != "front":
                rows = [r.replace("L", "n") for r in rows]
                if hat in ("hood", "veil", "helm"):
                    rows = [_fill_opening(r, view) if 4 < i < len(rows) - 1 else r for i, r in enumerate(rows)]
                if hat == "goggles" and view == "back":
                    rows = ["..OOOOOOOOOOOO.."]
            P(s, y, rows, self.layer(o["hatC"]))
        if o.get("mask") and view != "back":
            P(s, *EXTRA["plague"], self.layer(o["mask"]))
        for k in ("horns", "plume", "halo"):
            if o.get(k):
                P(s, *EXTRA[k], self.layer({"horns": "#efe3c4", "halo": "#f6c84a"}.get(k, o.get(k) if isinstance(o.get(k), str) else "#ffffff")))
        if cape and view == "back":
            s.rect(OX + 2, OY + 14, 12, 15, cape[0]); s.rect(OX + 3, OY + 14, 10, 14, cape[1]); s.rect(OX + 3, OY + 14, 4, 13, cape[2])
        if o.get("shield") and view == "front":
            x, y, rows = ITEM["shield"]
            s.rows(x, y, rows, self.layer(o["shield"]))
        if o.get("item") and view == "front":
            self._item(s, view)
        if o.get("item2") and view == "front":
            x, y, rows = ITEM[o["item2"]]
            s.rows(3, y, rows, self.layer("#b8c4d4"))

    def _item(self, s: Canvas, view: str, behind: bool = False) -> None:
        x, y, rows = ITEM[self.o["item"]]
        cmap = self.layer(self.o.get("itemC", "#b8c4d4"))
        if view == "side":
            x -= 9
        if behind:
            rows = [r[::-1] for r in rows]
            x = W - x - len(rows[0])
        s.rows(x, y, rows, cmap)


def _fill_opening(row: str, view: str) -> str:
    """Close a hood or helm's face opening for the back view (and the far half for
    the side view)."""
    first, last = row.find("O", 2), row.rfind("O", 0, 14)
    if first < 0 or last <= first:
        return row
    inner = row[first + 1:last]
    if "." not in inner:
        return row
    if view == "back":
        inner = "".join("n" if ch == "." else ch for ch in inner)
    else:
        half = len(inner) // 2
        inner = "".join("n" if (ch == "." and i < half) else ch for i, ch in enumerate(inner))
    return row[:first + 1] + inner + row[last:]


FACINGS = ("s", "sw", "w", "nw", "n", "ne", "e", "se")


def sheet(hero: Hero, cell_w: int = 32, cell_h: int = 48, scale: int = 2) -> "Image.Image":
    """8 facings x (2 idle + 6 walk), boots on cell row cell_h - 2 (shipped row
    cell_h*scale - 4, the feet line enemy.gd and player.tscn expect)."""
    sh = Canvas(cell_w * 8, cell_h * len(FACINGS))
    ox, oy = (cell_w - W) // 2, (cell_h - 2) - FEET_ROW
    for row, facing in enumerate(FACINGS):
        for col in range(8):
            sh.blit(hero.render(facing, col), col * cell_w + ox, row * cell_h + oy)
    return sh.image(scale)
