#!/usr/bin/env python3
"""Anatomische Körperkarte (vorn und hinten) als Vektordaten.

Eigene Zeichnung, frei von fremden Bildrechten. Quelle der Wahrheit für `lib/ui/body_map_art.dart`:

    python3 tool/body_map_art.py                      # schreibt die Dart-Datei
    python3 tool/body_map_art.py --preview out.svg    # Vorschau als SVG (Chromium, Inkscape …)

Zeichenfläche je Ansicht 200 × 400, Körpermitte x = 100. Muskeln mit `mirror` werden nur links gezeichnet und in
der App gespiegelt. `muscle` ist der Name aus `Muscle` (coach_core) oder None für Muskeln ohne eigenen Wert (grau).
Fasern: ("angle", Grad) parallel, ("fan", x, y) strahlenförmig von einem Punkt (Sehnenansatz).
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

W, H = 200, 400


def fmt(value: float) -> str:
    text = f"{value:.1f}".rstrip("0").rstrip(".")
    return "0" if text == "-0" else text


def path(start, *segments, close=True) -> str:
    """Pfad aus Startpunkt und Kurven (c1, c2, p) bzw. Linien (p,)."""
    parts = [f"M{fmt(start[0])} {fmt(start[1])}"]
    for seg in segments:
        if len(seg) == 1:
            parts.append(f"L{fmt(seg[0][0])} {fmt(seg[0][1])}")
        else:
            (a, b, p) = seg
            parts.append(f"C{fmt(a[0])} {fmt(a[1])} {fmt(b[0])} {fmt(b[1])} {fmt(p[0])} {fmt(p[1])}")
    if close:
        parts.append("Z")
    return " ".join(parts)


def mirror_point(p):
    return (W - p[0], p[1])


def sym(start, *segments) -> str:
    """Symmetrische Form: linke Hälfte von der Mitte oben bis zur Mitte unten, rechts gespiegelt zurück."""
    points = [start]
    for seg in segments:
        points.append(seg[-1])
    back = []
    for index in range(len(segments) - 1, -1, -1):
        seg = segments[index]
        target = mirror_point(points[index])
        if len(seg) == 1:
            back.append((target,))
        else:
            back.append((mirror_point(seg[1]), mirror_point(seg[0]), target))
    return path(start, *segments, *back)


def ellipse(cx, cy, rx, ry) -> str:
    k = 0.5523
    return path(
        (cx, cy - ry),
        ((cx + rx * k, cy - ry), (cx + rx, cy - ry * k), (cx + rx, cy)),
        ((cx + rx, cy + ry * k), (cx + rx * k, cy + ry), (cx, cy + ry)),
        ((cx - rx * k, cy + ry), (cx - rx, cy + ry * k), (cx - rx, cy)),
        ((cx - rx, cy - ry * k), (cx - rx * k, cy - ry), (cx, cy - ry)),
    )


def d(text: str) -> str:
    """Pfad in Kurzschreibweise „M x y C … Z“ (nur absolute Befehle)."""
    return " ".join(text.split())


def muscle(name, muscle_id, data, fibre=None, mirror=True, lines=(), plain=False):
    return {
        "name": name,
        "muscle": muscle_id,
        "d": data,
        "fibre": fibre,
        "mirror": mirror,
        "lines": list(lines),
        "plain": plain,
    }


# ---------------------------------------------------------------------------------------------------------------
# Umriss (beide Ansichten)

BODY = sym(
    (100, 58),
    ((95, 58), (92, 59), (90, 60)),
    ((84, 66), (72, 70), (62, 73)),
    ((56, 75), (54, 82), (56, 92)),
    ((58, 100), (62, 106), (64, 112)),
    ((63, 125), (64, 140), (67, 152)),
    ((70, 162), (71, 172), (69, 182)),
    ((66, 192), (63, 205), (62, 220)),
    ((61, 245), (65, 268), (69, 285)),
    ((70, 292), (68, 300), (67, 310)),
    ((66, 326), (70, 346), (76, 364)),
    ((78, 372), (78, 378), (77, 384)),
    ((73, 388), (70, 393), (75, 396)),
    ((82, 399), (90, 398), (94, 395)),
    ((96, 389), (94, 380), (93, 372)),
    ((91, 354), (95, 334), (94, 318)),
    ((93, 305), (91, 296), (92, 286)),
    ((94, 270), (96, 246), (98, 230)),
    ((99, 228), (100, 227), (100, 227)),
)

ARM = path(
    (58, 74),
    ((48, 76), (43, 86), (43, 98)),
    ((42, 110), (41, 124), (41, 136)),
    ((40, 146), (39, 152), (37, 160)),
    ((34, 176), (31, 192), (32, 208)),
    ((32, 212), (32, 215), (33, 218)),
    ((29, 224), (29, 236), (35, 241)),
    ((41, 245), (48, 242), (49, 234)),
    ((50, 227), (48, 221), (46, 217)),
    ((49, 200), (52, 180), (54, 162)),
    ((55, 155), (56, 150), (57, 145)),
    ((60, 130), (62, 118), (63, 110)),
    ((62, 100), (62, 86), (58, 74)),
)

NECK = sym(
    (100, 40),
    ((96, 40), (91, 41), (90, 44)),
    ((90, 52), (89, 60), (86, 68)),
    ((92, 70), (97, 71), (100, 71)),
)

HEAD = ellipse(100, 29, 15.5, 21)
EAR = ellipse(84.5, 31, 3, 6)

SILHOUETTE = [
    {"d": BODY, "mirror": False},
    {"d": ARM, "mirror": True},
    {"d": NECK, "mirror": False},
    {"d": EAR, "mirror": True},
    {"d": HEAD, "mirror": False},
]

HAND = d("M33 217 C29 224 29 236 35 241 C41 245 48 242 49 234 C50 227 48 221 46 216 C42 217.5 37 217.5 33 217 Z")
FOOT = d("M77.5 371 C78 377 78 381 77 384 C73 388 70 393 75 396 C82 399 90 398 94 395 C96 389 94 380 93 371 Z")

# Haut ohne Muskeln (heller als die Fugen dazwischen): Kopf, Hände, Füße; mit Linien für Finger und Zehen.
SKIN = [
    {"d": EAR, "mirror": True, "lines": []},
    {"d": HEAD, "mirror": False, "lines": []},
    {
        "d": HAND,
        "mirror": True,
        "lines": [
            d("M34 225 C38 227.5 43 227.5 47.5 225"),
            d("M33 231 C37 233.5 43 233.5 48.5 231"),
            d("M34.5 237 C38 239 43 239 47.5 236.5"),
        ],
    },
    {"d": FOOT, "mirror": True, "lines": [d("M76 391 C80 392.5 86 392.5 93 390")]},
]

# ---------------------------------------------------------------------------------------------------------------
# Vorn

FRONT = [
    # Hals und Nacken
    muscle("sternocleidomastoid", None, d("M86 44 C88 44 90 48 92 54 C94 60 96 66 98 70 C96.5 71 95 71 93.5 70 C91 62 88 52 86 44 Z"), ("angle", 70)),
    muscle("trapsFront", "traps", d("M90 56 C88 63 80 68 64 72 C72 73 81 72 89 70 C91 66 91 61 90 56 Z"), ("angle", 160)),
    # Schulter
    muscle(
        "sideDeltFront",
        "sideDelts",
        d("M58 74 C49 76 44 86 44 98 C44 107 46 115 49 121 C50 110 52 98 55 89 C56 83 57 78 58 74 Z"),
        ("angle", 80),
    ),
    muscle(
        "frontDelt",
        "frontDelts",
        d("M58 74 C64 72 70 72 76 73 C72 80 66 89 62 98 C58 106 53 114 49 121 C50 110 52 98 55 89 C56 83 57 78 58 74 Z"),
        ("fan", 52, 120),
    ),
    # Brust
    muscle(
        "chest",
        "chest",
        d("M98.5 72 C90 70 83 71 76.5 73.5 C71 81 65 91 61 101 C63 105 65 109 67 112 C73 118 82 122 91 120 "
          "C95 119 97.5 117 98.5 114 Z"),
        ("fan", 60, 103),
        lines=[d("M77 74 C84 84 90 96 98 106")],
    ),
    # Seite des Rumpfs
    muscle(
        "serratus",
        None,
        d("M64 112 C68 116 73 120 78 124 C76 130 72 134 67 138 C65 130 64 121 64 112 Z"),
        ("angle", 145),
        lines=[d("M64.5 118 L74 123"), d("M65.5 125 L75 128"), d("M66 132 L72 132")],
    ),
    muscle(
        "obliques",
        "obliques",
        d("M67 138 C73 134 80 128 86.5 124 C86 148 87 172 90 198 C84 193 76 189 70 186 C71 172 71 160 68 150 "
          "C67 146 67 142 67 138 Z"),
        ("angle", 60),
    ),
    # Bauch (Mitte, nicht gespiegelt)
    muscle(
        "abs",
        "abs",
        d("M87.5 121 C92 119 96 119 100 120 C104 119 108 119 112.5 121 C113.5 142 113.5 170 111.5 190 "
          "C109.5 203 105 212 100 216 C95 212 90.5 203 88.5 190 C86.5 170 86.5 142 87.5 121 Z"),
        ("angle", 90),
        mirror=False,
        lines=[
            d("M100 121 L100 214"),
            d("M88 140 C92 142 96 141 100 140 C104 141 108 142 112 140"),
            d("M87.5 159 C92 161 96 160 100 159 C104 160 108 161 112.5 159"),
            d("M88 178 C92 180 96 179 100 178 C104 179 108 180 112 178"),
        ],
    ),
    # Arm
    muscle(
        "biceps",
        "biceps",
        d("M55 107 C49 113 45.5 123 45.5 134 C45.5 143 47 150 50 155 C54.5 152 58.5 144 60 134 "
          "C61 124 59.5 113 55 107 Z"),
        ("angle", 92),
        lines=[d("M53 112 C52 126 52 140 51 152")],
    ),
    muscle(
        "brachialis",
        None,
        d("M44 112 C43 124 42 136 41 147 C44 150 47 153 50 155 C47 150 45.5 143 45.5 134 C45.5 125 46.5 117 49 111 "
          "C47 110 45.5 110 44 112 Z"),
        ("angle", 95),
    ),
    muscle(
        "tricepsFront",
        "triceps",
        d("M60.5 116 C62 126 61 136 58.5 146 C57.5 149 56.5 151 55 153 C58 146 60 138 60.5 128 Z"),
        ("angle", 95),
    ),
    muscle(
        "brachioradialis",
        "forearms",
        d("M42 140 C38 151 35.5 166 34.5 184 C34 198 34 207 35 214 C38 200 41 185 44 171 C46.5 161 47.5 153 46 147 "
          "C45 144 43.5 141 42 140 Z"),
        ("angle", 96),
    ),
    muscle(
        "forearmFlexors",
        "forearms",
        d("M46 147 C50 152 53.5 156 55.5 158 C53.5 176 50 196 46 215 C42 216 38.5 216 35 214 C38 200 41 185 44 171 "
          "C46.5 161 47.5 153 46 147 Z"),
        ("angle", 100),
        lines=[d("M50 156 C47 172 44 190 41 214")],
    ),
    # Bein
    muscle(
        "tfl",
        None,
        d("M63 212 C63 202 66 194 72 190 C72 200 71 210 70 220 C68 214 66 212 63 212 Z"),
        ("angle", 100),
    ),
    muscle(
        "vastusLateralis",
        "quads",
        d("M63 214 C66 212 69 214 70 220 C70 240 72 262 75 282 C73 285 71 286 69 284 C65 268 62 248 62 232 "
          "C62 224 62.5 218 63 214 Z"),
        ("angle", 100),
    ),
    muscle(
        "rectusFemoris",
        "quads",
        d("M72 194 C77 206 82 222 84 236 C84 252 83 270 80 284 C78 286 76 285 75 282 C72 262 70 240 70 220 "
          "C70 210 71 200 72 194 Z"),
        ("angle", 93),
        lines=[d("M73.5 206 C77 226 79 252 78 278")],
    ),
    muscle(
        "sartorius",
        None,
        d("M72 192 C77 204 83 224 86 244 C88 258 89 272 89 286 L92 286 C93 272 92 258 90 244 C87 224 81 204 75 191 "
          "C74 190.5 73 191 72 192 Z"),
        ("angle", 76),
    ),
    muscle(
        "vastusMedialis",
        "quads",
        d("M84 236 C87 250 89 266 89 284 C86 289 82 288 80 284 C83 270 84 252 84 236 Z"),
        ("angle", 60),
    ),
    muscle(
        "adductors",
        "adductors",
        d("M75 191 C84 204 92 216 98 229 C96.5 244 95 258 93 272 C92 258 91 248 90 244 C87 224 81 204 75 191 Z"),
        ("angle", 55),
        lines=[d("M82 202 C88 216 92 226 96 236")],
    ),
    muscle("patella", None, ellipse(84, 293, 5.5, 6.5), plain=True),
    muscle("tibia", None, d("M80 302 C83 300 86 300 87 304 C86 326 86 348 87 370 L84.5 370 C83 350 81.5 326 80 302 Z"), plain=True),
    muscle(
        "peroneus",
        None,
        d("M67.5 308 C69 312 70.5 318 71.5 324 C73.5 336 75.5 348 77.5 360 C76.5 361 76 361 75.5 360 C71 346 67.5 332 67 320 "
          "C67 316 67.2 312 67.5 308 Z"),
        ("angle", 98),
    ),
    muscle(
        "tibialis",
        None,
        d("M70 300 C74 300 78 302 80 306 C81.5 326 83 348 84.5 370 C82 370 80 368 79 365 C76 348 73.5 334 71.5 322 "
          "C70.5 314 69.5 306 70 300 Z"),
        ("angle", 94),
    ),
    muscle(
        "calfInner",
        "calves",
        d("M91 291 C95 301 96 318 94.5 334 C93 344 90 352 88 358 C86.5 340 86.5 322 87 306 C88 299 89.5 294 91 291 Z"),
        ("angle", 100),
    ),
    muscle(
        "soleusFront",
        "calves",
        d("M88 359 C90.5 352 93 344 94.5 335 C94 347 93.5 359 93 371 C91 369 89 365 88 359 Z"),
        ("angle", 92),
    ),
]

# ---------------------------------------------------------------------------------------------------------------
# Hinten

BACK = [
    muscle(
        "traps",
        "traps",
        d("M100 46 C97 54 94 60 89 63 C81 67 71 70 62 74 C70 78 80 85 87 96 C92 108 96 122 100 136 "
          "C104 122 108 108 113 96 C120 85 130 78 138 74 C129 70 119 67 111 63 C106 60 103 54 100 46 Z"),
        ("fan", 100, 150),
        mirror=False,
        lines=[d("M100 50 L100 134")],
    ),
    muscle(
        "sideDeltBack",
        "sideDelts",
        d("M58 74 C49 76 44 86 44 98 C44 107 46 115 49 121 C50 110 52 98 55 89 C56 83 57 78 58 74 Z"),
        ("angle", 80),
    ),
    muscle(
        "rearDelt",
        "rearDelts",
        d("M58 74 C63 74 67 76 71 80 C68 90 61 102 49 121 C50 110 52 98 55 89 C56 83 57 78 58 74 Z"),
        ("fan", 50, 120),
    ),
    muscle(
        "infraspinatus",
        None,
        d("M71 80 C78 84 84 90 87 96 C86 102 84 106 81 109 C74 110 68 111 62 112 C60 108 58 106 57 104 "
          "C61 96 66 88 71 80 Z"),
        ("fan", 58, 104),
        lines=[d("M60 108 C67 104 74 101 85 100")],
    ),
    muscle(
        "lats",
        "lats",
        d("M62 112 C70 111 77 110 81 109 C85 106 87 101 88 97 C92 108 96 122 100 136 L100 160 C96 170 92 178 87 184 "
          "C80 178 74 170 70 160 C66 146 64 128 62 112 Z"),
        ("fan", 62, 112),
    ),
    muscle(
        "lowerBack",
        "lowerBack",
        d("M100 136 C103 150 108 166 113 182 C110 190 105 196 100 199 C95 196 90 190 87 182 C92 166 97 150 100 136 Z"),
        ("angle", 90),
        mirror=False,
        lines=[d("M100 140 L100 198")],
    ),
    muscle(
        "obliquesBack",
        "obliques",
        d("M67 150 C70 162 76 174 86 185 C80 188 73 188 69 186 C70 174 69 162 67 150 Z"),
        ("angle", 60),
    ),
    muscle(
        "gluteusMedius",
        None,
        d("M68 188 C74 186 82 187 88 190 C93 192 97 196 100 200 C92 198 82 198 74 200 C70 198 68 194 68 188 Z"),
        ("angle", 120),
    ),
    muscle(
        "glutes",
        "glutes",
        d("M74 200 C84 198 93 199 99.5 202 L99.5 228 C92 236 80 237 70 231 C65 222 65 210 74 200 Z"),
        ("angle", 140),
    ),
    # Arm
    muscle(
        "triceps",
        "triceps",
        d("M61 110 C62.5 122 61.5 136 58.5 148 C54 151 49.5 151 45.5 148 C43.5 136 43.5 122 45.5 112 "
          "C50 106 56 106 61 110 Z"),
        ("angle", 90),
        lines=[d("M52 108 C51 120 51 134 52 148"), d("M47 140 C51 136 55 136 58.5 140")],
    ),
    muscle(
        "forearmExtensors",
        "forearms",
        d("M42 142 C46 148 51 152 56 156 C54 176 50 196 46 215 C42 216 38.5 216 35 214 C34 198 34.5 184 36.5 168 "
          "C38 156 40 148 42 142 Z"),
        ("angle", 100),
        lines=[d("M47 152 C45 172 42 194 40.5 215")],
    ),
    # Bein
    muscle(
        "itBand",
        None,
        d("M64 214 C65 236 67 258 70 280 C68 282 67 282 66 280 C63 262 62 240 63 222 C63 218 63.5 216 64 214 Z"),
        ("angle", 95),
    ),
    muscle(
        "bicepsFemoris",
        "hamstrings",
        d("M66 230 C71 234 76 236 80.5 236 C80 252 80 268 81 284 C78 286 75 286 72 284 C69 266 67 248 66 230 Z"),
        ("angle", 98),
    ),
    muscle(
        "semitendinosus",
        "hamstrings",
        d("M80.5 236 C86 236 92 235 97 232 C96 250 93 268 89 285 C86 287 83.5 286.5 81 284 C80 268 80 252 80.5 236 Z"),
        ("angle", 85),
    ),
    muscle(
        "adductorsBack",
        "adductors",
        d("M97.5 232 C98 238 97.5 246 96 252 C95 262 93 272 91.5 278 C92.5 266 95 248 97.5 232 Z"),
        ("angle", 80),
    ),
    muscle(
        "gastrocLateral",
        "calves",
        d("M69 293 C73 289 78 289 81.5 292 C82 306 82 320 81 332 C77 340 73 341 70 336 C66.5 322 66.5 306 69 293 Z"),
        ("angle", 95),
    ),
    muscle(
        "gastrocMedial",
        "calves",
        d("M81.5 292 C85 288 90 289 93 293 C95 306 95 322 93 336 C90 343 85 342 81 332 C82 320 82 306 81.5 292 Z"),
        ("angle", 85),
    ),
    muscle(
        "soleus",
        "calves",
        d("M70 336 C73 341 77 340 81 332 C85 342 90 343 93 336 C92 348 91 360 90 372 L81 372 C79 360 75 348 70 336 Z"),
        ("angle", 90),
        lines=[d("M85.5 344 L85.5 372")],
    ),
]

HAIR = d("M84.6 30 C84 14 91 8 100 8 C109 8 116 14 115.4 30 C114 38 110 44 106 46.5 C102 45 98 45 94 46.5 "
         "C90 44 86 38 84.6 30 Z")

VIEWS = {"front": FRONT, "back": BACK}

# ---------------------------------------------------------------------------------------------------------------
# Ausgabe


def dart_string(text: str) -> str:
    return "'" + text + "'"


def write_dart(target: Path) -> None:
    out = []
    out.append("// GENERIERT von tool/body_map_art.py – nicht von Hand ändern.")
    out.append("// Eigene anatomische Zeichnung (vorn und hinten), Zeichenfläche 200 × 400, Körpermitte x = 100.")
    out.append("// dart format off")
    out.append("part of 'body_map.dart';")
    out.append("")
    for name, shapes in (("_silhouette", SILHOUETTE), ("_skin", SKIN)):
        out.append(f"const {name} = <_ArtShape>[")
        for shape in shapes:
            args = [dart_string(shape["d"])]
            if shape["mirror"]:
                args.append("mirror: true")
            if shape.get("lines"):
                args.append("lines: [" + ", ".join(dart_string(line) for line in shape["lines"]) + "]")
            out.append(f"  _ArtShape({', '.join(args)}),")
        out.append("];")
        out.append("")
    out.append(f"const _hair = {dart_string(HAIR)};")
    out.append("")
    for view, muscles in VIEWS.items():
        out.append(f"const _{view} = <_ArtMuscle>[")
        for m in muscles:
            args = [dart_string(m["name"]), "Muscle." + m["muscle"] if m["muscle"] else "null", dart_string(m["d"])]
            if m["fibre"]:
                if m["fibre"][0] == "angle":
                    args.append(f"fibre: _Fibre.angle({fmt(m['fibre'][1])})")
                else:
                    args.append(f"fibre: _Fibre.fan({fmt(m['fibre'][1])}, {fmt(m['fibre'][2])})")
            if not m["mirror"]:
                args.append("mirror: false")
            if m["plain"]:
                args.append("plain: true")
            if m["lines"]:
                args.append("lines: [" + ", ".join(dart_string(line) for line in m["lines"]) + "]")
            out.append(f"  _ArtMuscle({', '.join(args)}),")
        out.append("];")
        out.append("")
    target.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")


def mirrored(attr: str, mirror: bool) -> str:
    return f'transform="matrix(-1 0 0 1 {W} 0)" ' if mirror else ""


HEAT = {
    "chest": "#e8743b",
    "frontDelts": "#3d9be0",
    "sideDelts": "#3d9be0",
    "rearDelts": "#3d9be0",
    "traps": "#5cb8e6",
    "lats": "#e0533f",
    "lowerBack": "#3157d6",
    "biceps": "#e8743b",
    "abs": "#2ebd85",
    "obliques": "#3157d6",
}


def write_preview(target: Path) -> None:
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {2 * W + 20} {H}" width="{(2 * W + 20) * 2}" '
           f'height="{H * 2}" style="background:#fff">']
    out.append("<defs>")
    out.append('<radialGradient id="g" cx="0.5" cy="0.45" r="0.65"><stop offset="0" stop-color="#efefef"/>'
               '<stop offset="1" stop-color="#ababab"/></radialGradient>')
    out.append('<radialGradient id="skin" cx="0.5" cy="0.4" r="0.7"><stop offset="0" stop-color="#f1f1f1"/>'
               '<stop offset="1" stop-color="#c9c9c9"/></radialGradient>')
    for key, color in HEAT.items():
        out.append(f'<radialGradient id="h_{key}" cx="0.5" cy="0.45" r="0.65"><stop offset="0" stop-color="{color}" '
                   f'stop-opacity="0.75"/><stop offset="1" stop-color="{color}"/></radialGradient>')
    out.append("</defs>")
    clip_id = 0
    for index, (view, muscles) in enumerate(VIEWS.items()):
        out.append(f'<g transform="translate({index * (W + 20)} 0)">')
        for shape in SILHOUETTE:
            for flip in [False, True] if shape["mirror"] else [False]:
                out.append(f'<path d="{shape["d"]}" {mirrored("", flip)}fill="#ddd" stroke="#2a2a2a" '
                           f'stroke-width="1.1"/>')
        for shape in SILHOUETTE:
            for flip in [False, True] if shape["mirror"] else [False]:
                out.append(f'<path d="{shape["d"]}" {mirrored("", flip)}fill="#c4c4c4"/>')
        for shape in SKIN:
            for flip in [False, True] if shape["mirror"] else [False]:
                tr = mirrored("", flip)
                out.append(f'<path d="{shape["d"]}" {tr}fill="url(#skin)" stroke="#1e1e1e" stroke-opacity="0.5" '
                           f'stroke-width="0.45"/>')
                for line in shape["lines"]:
                    out.append(f'<path d="{line}" {tr}fill="none" stroke="#000" stroke-opacity="0.35" '
                               f'stroke-width="0.45"/>')
        if view == "back":
            out.append(f'<path d="{HAIR}" fill="#8a8a8a" stroke="#1e1e1e" stroke-opacity="0.4" stroke-width="0.45"/>')
        for m in muscles:
            for flip in [False, True] if m["mirror"] else [False]:
                clip_id += 1
                fill = f"url(#h_{m['muscle']})" if m["muscle"] in HEAT else "url(#g)"
                if m["plain"]:
                    fill = "#d4d4d4"
                tr = mirrored("", flip)
                out.append(f'<clipPath id="c{clip_id}"><path d="{m["d"]}" {tr}/></clipPath>')
                out.append(f'<path d="{m["d"]}" {tr}fill="{fill}"/>')
                if m["fibre"]:
                    out.append(f'<g clip-path="url(#c{clip_id})"><g {tr}stroke="#000" stroke-opacity="0.16" '
                               f'stroke-width="0.35">')
                    out.extend(fibre_lines(m))
                    out.append("</g></g>")
                for line in m["lines"]:
                    out.append(f'<path d="{line}" {tr}fill="none" stroke="#000" stroke-opacity="0.35" '
                               f'stroke-width="0.5"/>')
                out.append(f'<path d="{m["d"]}" {tr}fill="none" stroke="#1e1e1e" stroke-opacity="0.55" '
                           f'stroke-width="0.45"/>')
        out.append("</g>")
    out.append("</svg>")
    target.write_text("\n".join(out), encoding="utf-8")


def fibre_lines(m) -> list[str]:
    lines = []
    if m["fibre"][0] == "angle":
        angle = math.radians(m["fibre"][1])
        dx, dy = math.cos(angle), math.sin(angle)
        nx, ny = -dy, dx
        for step in range(-200, 200):
            offset = step * 1.6
            cx, cy = 100 + nx * offset, 200 + ny * offset
            lines.append(f'<line x1="{cx - dx * 400:.1f}" y1="{cy - dy * 400:.1f}" x2="{cx + dx * 400:.1f}" '
                         f'y2="{cy + dy * 400:.1f}"/>')
    else:
        _, fx, fy = m["fibre"]
        for step in range(0, 360, 5):
            a = math.radians(step)
            lines.append(f'<line x1="{fx + math.cos(a) * 1:.1f}" y1="{fy + math.sin(a) * 1:.1f}" '
                         f'x2="{fx + math.cos(a) * 300:.1f}" y2="{fy + math.sin(a) * 300:.1f}"/>')
    return lines


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.preview:
        write_preview(args.preview)
    else:
        write_dart(root / "lib/ui/body_map_art.dart")


if __name__ == "__main__":
    main()
