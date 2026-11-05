"""
Smoke X4 smart bridge - enclosure v2 (parametric, CadQuery).

A thinner, stronger, nicer-to-hold take on the v1 Heltec V3 case in
`enclosure/docs/reference`.

Design/print axes used below (all millimetres):

    +Z  ......... into the case (front face is z=0; back of device is z=T)
    +Y  ......... top of the device (USB-C end)
    +X  ......... right (looking at the front)

The front housing is printed front-face-down as modelled.  The lid and the
button bar are exported in print orientation (see `main`).

Run:
    python enclosure/cad/case_v2.py            # build + export everything
    python enclosure/cad/case_v2.py --no-export
"""

from __future__ import annotations

import argparse
import json
import os
from dataclasses import asdict, dataclass

import cadquery as cq
from cadquery import exporters

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "out"))


# --------------------------------------------------------------------------
# parameters
# --------------------------------------------------------------------------
@dataclass(frozen=True)
class Params:
    # ---- envelope -------------------------------------------------------
    W: float = 38.8          # v1: 39.65
    L: float = 75.0          # v1: 75.46
    T: float = 22.6          # v1: 27.0  (-4.4 mm)
    seam: float = 10.6       # front housing height (z of the hidden joint face)
    r_side: float = 5.5      # corner radius in plan view
    r_front: float = 1.0     # round-over on the front face
    r_back: float = 3.0      # round-over on the back face (keeps 1.2 wall intact)

    # ---- walls ----------------------------------------------------------
    wall: float = 1.2        # front housing wall (PETG/ASA, 3 perimeters)
    lid_wall: float = 1.2    # lid wall / battery pocket wall
    tongue_step: float = 1.35  # radial inset of the joint tongue
    # The visible front wall must clear the 1.0 mm front round-over and the
    # 6.5 mm antenna hole.  A slightly shorter tongue moves the visible seam
    # up 1 mm while keeping the 22.6 mm overall thickness and the battery
    # pocket depth unchanged.
    tongue_h: float = 2.2    # how far the tongue reaches into the lid
    joint_clear: float = 0.15  # radial clearance tongue -> lid cavity
    seam_gap: float = 0.0    # parting line is closed; chamfer = shadow line

    # ---- display --------------------------------------------------------
    win_w: float = 14.09     # reference window width (aligned to the OLED)
    win_h: float = 26.28     # reference window height
    win_cy: float = 4.40     # reference window centre in Y (case centre = 0)
    win_r: float = 0.0       # through-window corner radius (0 = square)
    win_chamfer: float = 0.5

    # ---- buttons --------------------------------------------------------
    # The two PCB switches are not symmetric about the board centre: they
    # straddle the USB-C shell, which sits 1.46 mm right of centre.
    btn_rst_x: float = -6.47  # reference bore centre, left of centre
    btn_prg_x: float = 9.53   # reference bore centre, right of centre
    btn_cy: float = 32.38     # reference switch/bore centre in Y
    # The right-hand (PRG) switch is close to the USB end wall.  A 7 mm cap
    # left only ~0.2 mm of front wall there, which prints as a notch.  Keep
    # the reference-sized cap (the v1 cap head was 6.12 mm) so the wall stays
    # printable and the cap still has a comfortable press area.
    btn_cap_d: float = 6.2    # TPU cap OD (v1 reference head: 6.12)
    btn_bore: float = 6.4     # front bore
    btn_recess: float = 0.5  # dog-bone recess depth in the front face
    btn_lip_d: float = 6.65   # retention lip on the cap (snaps behind wall)
    btn_len: float = 5.02    # cap length: top -0.4 -> switch plane 4.62
    btn_web_w: float = 5.0
    btn_web_t: float = 0.5
    btn_protrude: float = 0.4
    label_depth: float = 0.35
    label_size: float = 2.30
    label_font: str = "Arial"

    # ---- board (Heltec WiFi LoRa 32 V3) ---------------------------------
    board_l: float = 51.69
    board_w: float = 25.4
    board_t: float = 1.12
    board_usb_tip: float = -1.27  # board-local X of the PCB's USB end
    # The USB-C shell is on the component side and sits 1.65 mm above the
    # PCB face.  These values put its centre at z=4.97, matching the
    # reference USB opening instead of clipping the port against the wall.
    board_pcb_top: float = 6.62  # z of the component-side PCB face
    board_pcb_bot: float = 7.74
    board_switch_x: float = 2.2  # board-local distance from USB tip
    board_switch_y: float = 8.0  # board-local +/- from the USB centreline
    board_usb_front: float = -1.6  # board-local x of the USB tip
    board_switch_dZ: float = 2.0   # switch top above PCB top
    board_cy: float = 32.38      # case Y of the switch centres (reference;
                                 # seats the USB-C tip in the end-wall pocket)

    # ---- battery (Heltec PL103665 3000 mAh LiPo) ------------------------
    bat_l: float = 65.0
    bat_w: float = 36.0
    bat_t: float = 10.3
    bat_y_top: float = 32.8      # top edge in Y (lid battery pocket)
    bat_gap_front: float = 0.3   # battery to front-housing seam
    bat_gap_back: float = 0.2    # battery to lid back wall

    # ---- ports ----------------------------------------------------------
    usb_x: float = 1.46          # USB-C centre, offset like the PCB connector
    usb_w: float = 9.13
    usb_h: float = 3.43
    usb_z0: float = 3.27         # bottom of the USB opening
    usb_pocket_w: float = 18.2   # inner counterbore for the connector body
    usb_pocket_h: float = 5.25   # top at z=7.4, below the tongue step
    usb_pocket_z0: float = 2.15
    usb_pocket_depth: float = 0.6
    usb_pocket_r: float = 2.0

    # The reference SMA is at x=-11.88, but that is inside the v2 corner
    # round-over. Move the hole just far enough inboard to sit in the flat
    # end wall. build_front thickens that end wall so the nut has a flat
    # seat and the outside keeps the original rounded shape.
    ant_x: float = -10.20        # in the flat end wall, left of centre
    # Sit the hole between the 1.0 mm front round-over and the tongue step:
    # bottom 1.45, top 7.95, with 0.45 mm clearance at each end.
    ant_z: float = 4.70
    ant_d: float = 6.5
    ant_seat_d: float = 10.0     # kept for reference; no exterior pad
    ant_seat_depth: float = 0.0

    # ---- details --------------------------------------------------------
    snap_bump: float = 0.30
    snap_groove: float = 0.36


P = Params()


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def rr_prism(w: float, l: float, h: float, r: float, z0: float = 0.0) -> cq.Workplane:
    """Rounded-rectangle prism centred on X=Y=0, from z0 to z0+h."""
    wp = cq.Workplane("XY").workplane(offset=z0).rect(w, l).extrude(h)
    if r > 0:
        wp = wp.edges("|Z").fillet(r)
    return wp


def rr_slot(w: float, l: float, h: float, r: float, x: float, y: float, z0: float) -> cq.Workplane:
    return rr_prism(w, l, h, r, z0).translate((x, y, 0))


def cutters_along_y(cross_w: float, cross_h: float, cross_r: float,
                    y0: float, y1: float) -> cq.Workplane:
    """A rounded-rect cross-section (in XZ) swept along Y."""
    wp = (
        cq.Workplane("XZ")
        .rect(cross_w, cross_h)
        .extrude(-(y1 - y0))
        .translate((0, y0, 0))
    )
    if cross_r > 0:
        wp = wp.edges("|Y").fillet(cross_r)
    return wp


def rounded_rect_wire(w: float, h: float, r: float, plane: str = "XY") -> cq.Workplane:
    """A 2D rounded rectangle wire on the given workplane."""
    wp = cq.Workplane(plane).rect(w, h).extrude(0.001)
    if r > 0:
        wp = wp.edges("|Z" if plane in ("XY",) else "|Y" if plane == "XZ" else "|X").fillet(r)
    return wp


def engrave_text(txt: str, size: float, depth: float, x: float, y: float,
                 z: float, font: str = "Arial", kind: str = "bold") -> cq.Workplane:
    """Text solid sitting on z and extruding +depth (for cutting into a face)."""
    t = (
        cq.Workplane("XY")
        .workplane(offset=z)
        .text(txt, size, depth, font=font, kind=kind, halign="center", valign="center")
        # text is read from -Z (the user's side): mirror in X, then place
        .mirror(mirrorPlane="YZ")
        .rotate((0, 0, 0), (0, 0, 1), 180)
    )
    return t.translate((x, y, 0.0))


def fillet_vertical(wp: cq.Workplane, r: float) -> cq.Workplane:
    return wp.edges("|Z").fillet(r)


def bbox(wp: cq.Workplane):
    b = wp.val().BoundingBox()
    return dict(x0=b.xmin, x1=b.xmax, y0=b.ymin, y1=b.ymax, z0=b.zmin, z1=b.zmax)


def describe(name: str, wp: cq.Workplane) -> dict:
    b = bbox(wp)
    vol = wp.val().Volume()
    return {
        "name": name,
        "bbox": {k: round(v, 3) for k, v in b.items()},
        "size": [round(b["x1"] - b["x0"], 3), round(b["y1"] - b["y0"], 3),
                 round(b["z1"] - b["z0"], 3)],
        "volume_mm3": round(vol, 1),
        "volume_cm3": round(vol / 1000.0, 3),
        "mass_g_petg": round(vol / 1000.0 * 1.27, 1),
        "mass_g_asa": round(vol / 1000.0 * 1.07, 1),
        "mass_g_tpu95": round(vol / 1000.0 * 1.21, 1),
    }



def antenna_cutter(p: Params = P) -> cq.Workplane:
    """Circular SMA bulkhead clearance hole (6.5 mm), through the end wall."""
    return (
        cq.Workplane("XZ").center(p.ant_x, p.ant_z)
        .circle(p.ant_d / 2.0).extrude(-4.0)
        .translate((0, -p.L / 2.0 - 0.5, 0))
    )


# --------------------------------------------------------------------------
# front housing
# --------------------------------------------------------------------------
def build_front(p: Params = P) -> cq.Workplane:
    z_step = p.seam - p.tongue_h          # 7.4: visible parting line / step
    z_land = p.board_pcb_bot + 0.18        # land level; also the back-shelf floor
    t_od_w = p.W - 2 * p.tongue_step
    t_od_l = p.L - 2 * p.tongue_step
    t_id_w = t_od_w - 2 * p.wall
    t_id_l = t_od_l - 2 * p.wall

    # --- outer body + hidden joint tongue --------------------------------
    lower = rr_prism(p.W, p.L, z_step, p.r_side)
    lower = lower.faces("<Z").edges().fillet(p.r_front)
    # 0.03 mm overlap so the boolean fuses into a single solid
    upper = rr_prism(t_od_w, t_od_l, p.tongue_h + 0.03,
                     p.r_side - p.tongue_step, z0=z_step - 0.03)
    front = lower.union(upper)

    # lead-in chamfer on the tongue's top outer edge (before the cavity cut)
    front = front.faces(cq.selectors.BoxSelector(
        (-p.W, -p.L, p.seam - 0.6),
        (p.W, p.L, p.seam + 0.1))).chamfer(0.5)

    # --- hollow it out ----------------------------------------------------
    # The antenna end wall is thickened to the same depth as the upper tongue
    # wall (tongue_step + wall).  The main and upper cavities then share one
    # flat inner end face, so the interior reads as a single unibody wall
    # instead of a local boss stuck onto the inside.
    ant_wall = p.tongue_step + p.wall
    c_main_l = p.L - p.wall - ant_wall
    c_main = (
        rr_prism(p.W - 2 * p.wall, c_main_l,
                 z_land - p.wall, p.r_side - p.wall, z0=p.wall)
        .translate((0, p.tongue_step / 2.0, 0))
    )
    # cavity 2: narrowed at the land, continues through the tongue to the top
    c_upper = rr_prism(t_id_w, t_id_l, p.seam - z_land + 0.4,
                       p.r_side - p.tongue_step - p.wall, z0=z_land)
    front = front.cut(c_main).cut(c_upper)

    # --- display window --------------------------------------------------
    front = front.cut(rr_slot(p.win_w, p.win_h, p.wall + 1.0, p.win_r,
                              0, p.win_cy, -0.5))
    # outside chamfer: loft from a slightly larger rect at the surface
    ch = (
        cq.Workplane("XY").workplane(offset=-0.01)
        .rect(p.win_w + 2 * p.win_chamfer, p.win_h + 2 * p.win_chamfer)
        .workplane(offset=p.win_chamfer + 0.01)
        .rect(p.win_w, p.win_h)
        .loft(combine=True)
        .translate((0, p.win_cy, 0))
    )
    front = front.cut(ch)

    # --- button dog-bone recess + bores ----------------------------------
    # The recess is a slot between the two bores; the shallow circular
    # recesses in the old model would have grazed the USB end wall.
    bone = rr_slot(p.btn_prg_x - p.btn_rst_x, p.btn_web_w + 0.6,
                   p.btn_recess + 0.05, 0.5,
                   (p.btn_prg_x + p.btn_rst_x) / 2.0, p.btn_cy, -0.05)
    front = front.cut(bone)
    for cap_x in (p.btn_rst_x, p.btn_prg_x):
        front = front.cut(
            cq.Workplane("XY").workplane(offset=-0.5)
            .center(cap_x, p.btn_cy)
            .circle(p.btn_bore / 2.0).extrude(p.wall + 1.0))
    # small lead-in chamfer on each bore
    for cap_x in (p.btn_rst_x, p.btn_prg_x):
        front = front.cut(
            cq.Workplane("XY").workplane(offset=-0.01)
            .center(cap_x, p.btn_cy)
            .circle(p.btn_bore / 2.0 + 0.15)
            .workplane(offset=0.26)
            .circle(p.btn_bore / 2.0)
            .loft(combine=True))

    # --- USB-C opening (top end) -----------------------------------------
    zc = p.usb_z0 + p.usb_h / 2.0
    usb = cutters_along_y(p.usb_w, p.usb_h, 0.8,
                          p.L / 2.0 - 2.0, p.L / 2.0 + 1.0)
    front = front.cut(usb.translate((p.usb_x, 0, zc)))
    # 0.5 mm lead-in chamfer on the outside of the USB opening
    front = front.edges(cq.selectors.BoxSelector(
        (p.usb_x - p.usb_w / 2.0 - 0.6, p.L / 2.0 - 0.05,
         zc - p.usb_h / 2.0 - 0.6),
        (p.usb_x + p.usb_w / 2.0 + 0.6, p.L / 2.0 + 0.4,
         zc + p.usb_h / 2.0 + 0.6),
    )).chamfer(0.5)
    # inner counterbore so the USB-C shell/body does not jack the board off
    # the cradle; leaves a 0.6 mm outer skin around the small opening.
    zp = p.usb_pocket_z0 + p.usb_pocket_h / 2.0
    pocket = cutters_along_y(p.usb_pocket_w, p.usb_pocket_h, p.usb_pocket_r,
                             p.L / 2.0 - p.wall,
                             p.L / 2.0 - p.wall + p.usb_pocket_depth)
    front = front.cut(pocket.translate((p.usb_x, 0, zp)))

    # --- board cradle: slim side guides + one small back shelf ------------
    # The board drops in from the back.  Two narrow tabs per side only set
    # the lateral position; the Z stack is handled by the button caps /
    # switches in front and the lid/battery behind.  One small shelf per
    # side stops the board being pushed backwards by the buttons.  There is
    # no front lip and no second rail tier around the PCB.
    board_top_y = p.board_cy + p.board_switch_x - p.board_usb_tip  # 35.85
    board_bot_y = board_top_y - p.board_l           # -15.84
    for sx in (-1, 1):
        for yc in (20.28, -3.72):
            # lateral guide: 0.8 mm thick, 3 mm long, just outside the PCB
            front = front.union(
                cq.Workplane("XY").workplane(offset=p.wall)
                .center(sx * 13.30, yc)
                .rect(0.8, 3.0)
                .extrude(p.board_pcb_bot + 0.2 - p.wall))
            # single back shelf: the board slides under it from the back
            front = front.union(
                cq.Workplane("XY").workplane(offset=p.board_pcb_bot + 0.18)
                .center(sx * 12.95, yc)
                .rect(1.5, 4.0)
                .extrude(0.3))
    for xc in (7.0, -2.0):
        front = front.union(
            cq.Workplane("XY").workplane(offset=p.wall)
            .center(xc, board_bot_y - 0.55)
            .rect(6.0, 0.8).extrude(p.board_pcb_bot - p.wall + 0.18))

    # --- antenna bulkhead: straight hole through the thick end wall --------
    # The end wall is already thickened to the tongue-wall depth above, so
    # there is no local boss: the hole passes through one continuous wall
    # and the nut seats on the same flat inner face.
    front = front.cut(antenna_cutter(p))

    # --- snap bumps on the tongue ---------------------------------------
    tx = p.W / 2.0 - p.tongue_step
    ty = p.L / 2.0 - p.tongue_step
    z_bump = z_step + 1.2
    bumps = []
    for sy in (-1, 1):
        for sx in (-1, 1):
            bumps.append(
                cq.Workplane("XY").workplane(offset=z_bump)
                .center(sx * (tx + p.snap_bump / 2.0 - 0.1), sy * 18.0)
                .rect(p.snap_bump + 0.2, 1.6).extrude(0.7))
    for sx in (-1, 1):
        bumps.append(
            cq.Workplane("XY").workplane(offset=z_bump)
            .center(sx * 8.0, ty + p.snap_bump / 2.0 - 0.1)
            .rect(1.6, p.snap_bump + 0.2).extrude(0.7))
    for b in bumps:
        front = front.union(b)

    return front.clean()


# --------------------------------------------------------------------------
# lid
# --------------------------------------------------------------------------
def build_lid(p: Params = P) -> cq.Workplane:
    z0 = p.seam - p.tongue_h + p.seam_gap   # skirt bottom = parting line
    lid = rr_prism(p.W, p.L, p.T - z0, p.r_side, z0=z0)
    # big round-over on the back face
    lid = lid.faces(">Z").edges().fillet(p.r_back)
    # fine chamfer on the skirt's bottom outer edge (shadow line)
    lid = lid.faces("<Z").edges().chamfer(0.3)

    # cavity: wall = lid_wall, and it accepts the front tongue with
    # joint_clear on every side
    cavity = rr_prism(p.W - 2 * p.lid_wall, p.L - 2 * p.lid_wall,
                      p.T - z0 - p.lid_wall + 0.01, p.r_side - p.lid_wall,
                      z0=z0 - 0.1)
    lid = lid.cut(cavity)

    # The SMA bulkhead now lives in the front housing (see build_front), so
    # the lid is just the battery pocket and needs no antenna hole/boss.

    # snap grooves in the cavity side walls
    tx = p.W / 2.0 - p.tongue_step
    ty = p.L / 2.0 - p.tongue_step
    z_bump = p.seam - p.tongue_h + 1.2
    grooves = []
    for sy in (-1, 1):
        for sx in (-1, 1):
            grooves.append(
                cq.Workplane("XY").workplane(offset=z_bump - 0.15)
                .center(sx * (tx + p.snap_bump / 2.0 + 0.02), sy * 18.0)
                .rect(p.snap_groove, 1.8).extrude(0.85))
    for sx in (-1, 1):
        grooves.append(
            cq.Workplane("XY").workplane(offset=z_bump - 0.15)
            .center(sx * 8.0, ty + p.snap_bump / 2.0 + 0.02)
            .rect(1.8, p.snap_groove).extrude(0.85))
    for g in grooves:
        lid = lid.cut(g)

    # service notch at the bottom end: catch the lid edge with a fingernail
    return lid.clean()


# --------------------------------------------------------------------------
# one-piece TPU button bar
# --------------------------------------------------------------------------
def build_buttons(p: Params = P) -> cq.Workplane:
    """Two caps joined by a flexible web, installed from the front.

    Print orientation: front face down (cap tops + web on the bed).
    Coordinate system matches the front: z=0 is the front face, the cap top
    is at -p.btn_protrude, the cap back (switch contact) at p.btn_len-... .
    """
    z_top = -p.btn_protrude
    z_back = z_top + p.btn_len            # 2.5 -> switch plane
    bar = None
    for cap_x in (p.btn_rst_x, p.btn_prg_x):
        cap = (
            cq.Workplane("XY").workplane(offset=z_top)
            .center(cap_x, p.btn_cy)
            .circle(p.btn_cap_d / 2.0).extrude(p.btn_len)
        )
        # soft top edge
        cap = cap.faces("<Z").edges().chamfer(0.35)
        # retention lip just behind the 1.2 mm front wall
        lip = (
            cq.Workplane("XY").workplane(offset=p.wall - 0.05)
            .center(cap_x, p.btn_cy)
            .circle(p.btn_lip_d / 2.0).extrude(0.45)
        )
        lip = lip.faces("<Z").edges().chamfer(0.15)
        lip = lip.faces(">Z").edges().chamfer(0.15)
        cap = cap.union(lip)
        bar = cap if bar is None else bar.union(cap)

    # web is flush with the cap tops so the whole part prints on the bed;
    # its centre follows the asymmetric cap pair (1.53 mm right of centre)
    bar_cx = (p.btn_prg_x + p.btn_rst_x) / 2.0
    bar_span = p.btn_prg_x - p.btn_rst_x
    web = (
        cq.Workplane("XY").workplane(offset=z_top)
        .center(bar_cx, p.btn_cy)
        .rect(bar_span, p.btn_web_w)
        .extrude(p.btn_web_t)
    )
    bar = bar.union(web)

    # a shallow cove where the web meets each cap (flex relief, both sides)
    for cap_x, direction in ((p.btn_rst_x, 1), (p.btn_prg_x, -1)):
        bar = bar.cut(
            cq.Workplane("XY").workplane(offset=z_top + p.btn_web_t - 0.05)
            .center(cap_x + direction * (p.btn_cap_d / 2.0 + 0.15), p.btn_cy)
            .circle(0.55)
            .extrude(1.6))

    # engraved labels on the cap tops; PRG is the +X switch, matching the
    # board. The text is oriented to read with the antenna end up.
    for label, cap_x in (("PRG", p.btn_prg_x), ("RST", p.btn_rst_x)):
        bar = bar.cut(
            engrave_text(label, p.label_size, p.label_depth + 0.02,
                         cap_x, p.btn_cy, z_top - 0.01,
                         p.label_font))

    return bar.clean()


# --------------------------------------------------------------------------
# export / report
# --------------------------------------------------------------------------
def export_part(wp: cq.Workplane, name: str, rotate_print: bool = False,
                translate_print: float | None = None, step: bool = True):
    os.makedirs(OUT, exist_ok=True)
    part = wp
    if rotate_print:
        part = part.rotate((0, 0, 0), (1, 0, 0), 180)
    if translate_print is not None:
        part = part.translate((0, 0, translate_print))
    b = bbox(part)
    part = part.translate((0, 0, -b["z0"]))
    stl = os.path.join(OUT, name + ".stl")
    exporters.export(part, stl, tolerance=0.02, angularTolerance=0.15)
    if step:
        exporters.export(wp, os.path.join(OUT, name + ".step"))
    return stl


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-export", action="store_true")
    args = ap.parse_args()

    print("building front ...")
    front = build_front()
    print("building lid ...")
    lid = build_lid()
    print("building buttons ...")
    buttons = build_buttons()

    report = {
        "params": asdict(P),
        "parts": [describe("front", front), describe("lid", lid),
                  describe("buttons", buttons)],
    }
    print(json.dumps(report["parts"], indent=2))
    report["parts"].append({
        "name": "assembly",
        "bbox": {"x0": -P.W / 2, "x1": P.W / 2, "y0": -P.L / 2,
                 "y1": P.L / 2, "z0": 0.0, "z1": P.T},
        "size": [P.W, P.L, P.T],
        "volume_mm3": round(sum(p["volume_mm3"] for p in report["parts"]), 1),
    })

    if not args.no_export:
        export_part(front, "case_v2_front")
        # lid: rotate 180 deg about X so its back sits on the bed, cavity up
        export_part(lid, "case_v2_lid", rotate_print=True, translate_print=P.T)
        export_part(buttons, "case_v2_button_bar")
        with open(os.path.join(OUT, "case_v2_report.json"), "w") as f:
            json.dump(report, f, indent=2)
        print("wrote", OUT)


if __name__ == "__main__":
    main()
