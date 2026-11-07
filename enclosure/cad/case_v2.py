"""Thin Heltec V3 enclosure built from the original case's mounting datums.

All dimensions are millimetres. The front exterior is Z=0, the USB end is
positive Y, and the PCB is offset toward positive X. The front is printed
face down. STL exports place each part on the bed, with the lid back down.
The front exterior carries no recessed text: a label cut into that face
opens onto the build plate, so its roof has to bridge and is not reliable in
PLA or ASA. Labels belong on a vertical wall.

    python enclosure/cad/case_v2.py
    python enclosure/cad/check_fit.py
"""
from __future__ import annotations

import argparse
import json
import math
import os
from dataclasses import asdict, dataclass

import cadquery as cq
from cadquery import exporters

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "out"))


@dataclass(frozen=True)
class Params:
    # Original footprint and front/lid split, with the newer exterior radii.
    W: float = 39.6494
    L: float = 75.4634
    T: float = 22.6
    seam: float = 15.1892
    r_side: float = 5.5
    r_front: float = 1.0
    r_back: float = 3.0
    wall: float = 1.2
    face_t: float = 1.2
    lid_wall: float = 1.2
    joint_wall: float = 0.8
    tongue_wall: float = 0.7
    joint_clear: float = 0.1
    seam_gap: float = 0.15
    joint_start: float = 9.6012
    tongue_h: float = 5.08
    snap_bump: float = 0.2
    snap_z: float = 12.0

    # Original display throat and its rounded entrance, trimmed to the thin face.
    win_w: float = 12.446
    win_h: float = 24.638
    win_cy: float = 4.4069
    win_r: float = 0.0
    win_roundover: float = 1.1

    # Original switch centres, with guided rear-installed captive plungers.
    btn_rst_x: float = -6.477
    btn_prg_x: float = 9.525
    btn_cy: float = 32.385
    btn_bore: float = 6.5
    btn_cap_d: float = 6.0
    btn_tpu_cap_d: float = 5.85
    btn_stem_d: float = 3.6
    btn_tpu_stem_d: float = 4.0
    btn_lip_d: float = 7.9
    btn_lip_t: float = 0.6
    btn_collar_d: float = 9.4
    btn_collar_z: float = 2.1
    btn_seat_d: float = 8.2
    # Finger faces sit 1.4 mm proud of the front. The link is kept on the
    # build plate so it prints as solid material from the ground instead of
    # needing slicer support. The cap height is not added to the ligament.
    btn_protrude: float = 1.4
    btn_link_recess: float = 0.0
    # Keep the stem clear of the switch when the PCB seats fully forward in
    # the USB-C opening. The old 0.15 mm gap could be consumed by that play
    # before the case was closed.
    btn_switch_gap: float = 0.6
    btn_link_w: float = 0.8
    btn_link_t: float = 0.88
    btn_tpu_link_w: float = 1.0
    btn_tpu_link_t: float = 1.04
    btn_link_amplitude: float = 1.8
    btn_link_clear: float = 0.2

    # Straight contact faces measured from the centred original front mesh.
    board_l: float = 51.69
    board_w: float = 25.4
    board_t: float = 1.12
    board_x: float = 1.4605
    board_clear: float = 0.1905
    board_pocket_y0: float = -15.9639
    board_pocket_y1: float = 36.1315
    board_left_y0: float = -10.8839
    board_end_x0: float = -5.5245
    board_guide_top: float = 9.6012
    board_guide_len: float = 5.0
    board_guide_y: tuple[float, ...] = (-5.0, 12.0, 29.0)
    board_usb_tip: float = -1.27
    board_pcb_top: float = 6.62
    board_pcb_bot: float = 7.74
    board_switch_x: float = 2.2
    board_switch_y: float = 8.0
    board_usb_front: float = -1.6
    board_switch_dZ: float = 2.0
    board_cy: float = 32.385

    bat_l: float = 65.0
    bat_w: float = 36.0
    bat_t: float = 10.3
    bat_z0: float = 10.4
    bat_y_top: float = 32.8
    bat_gap_front: float = 0.3
    bat_gap_back: float = 0.2

    usb_x: float = 1.4605
    usb_w: float = 9.144
    usb_h: float = 3.429
    usb_z0: float = 3.2512
    usb_pocket_w: float = 18.2
    usb_pocket_h: float = 5.25
    usb_pocket_z0: float = 2.15
    usb_pocket_depth: float = 0.6
    usb_pocket_r: float = 2.0

    # Original antenna centre and inside mounting plane. The original front
    # provides 4.7625 mm from this centre to its floor, allowing a 9.525 mm lip.
    ant_x: float = -11.8745
    ant_z: float = 6.3627
    ant_d: float = 6.8
    ant_seat_y: float = -36.1315
    ant_flange_d: float = 9.525
    ant_flange_clear: float = 0.2  # additional radial clearance
    ant_pad_d: float = 11.0


P = Params()


def rr_prism(w: float, l: float, h: float, r: float, z0: float = 0.0) -> cq.Workplane:
    part = cq.Workplane("XY").workplane(offset=z0).rect(w, l).extrude(h)
    if r > 0:
        part = part.edges("|Z").fillet(r)
    return part


def rr_slot(w: float, l: float, h: float, r: float,
            x: float, y: float, z0: float) -> cq.Workplane:
    return rr_prism(w, l, h, r, z0).translate((x, y, 0))


def cutters_along_y(cross_w: float, cross_h: float, cross_r: float,
                    y0: float, y1: float) -> cq.Workplane:
    part = (cq.Workplane("XZ").rect(cross_w, cross_h)
            .extrude(-(y1 - y0)).translate((0, y0, 0)))
    if cross_r > 0:
        part = part.edges("|Y").fillet(cross_r)
    return part


def antenna_cutter(p: Params = P) -> cq.Workplane:
    return (cq.Workplane("XZ").center(p.ant_x, p.ant_z)
            .circle(p.ant_d / 2).extrude(-4)
            .translate((0, -p.L / 2 - 0.5, 0)))


def antenna_flange_cutter(p: Params = P) -> cq.Workplane:
    # Reserve the RF channel down to the board's end rail. This also relieves
    # the mating lid skirt wherever it enters the connector's circular space.
    depth = p.board_pocket_y0 - p.wall - p.ant_seat_y
    return (cq.Workplane("XZ").center(p.ant_x, p.ant_z)
            .circle(p.ant_flange_d / 2 + p.ant_flange_clear)
            .extrude(-depth).translate((0, p.ant_seat_y, 0)))


def button_link(p: Params = P, *, tpu: bool = False,
                clearance: float = 0.0, slot: bool = False) -> cq.Workplane:
    """Flat, gently curved ligament joining the two plungers.

    The link sits at the finger-face plane so it prints directly on the bed
    as solid material, with no support under its span. The matching
    through-slot lets the connected pair enter from the back.
    """
    width = (p.btn_tpu_link_w if tpu else p.btn_link_w) + 2 * clearance
    thickness = p.btn_tpu_link_t if tpu else p.btn_link_t
    x0 = p.btn_rst_x + 2.4
    x1 = p.btn_prg_x - 2.4
    upper, lower = [], []
    for index in range(65):
        fraction = index / 64
        angle = 2 * math.pi * fraction
        x = x0 + fraction * (x1 - x0)
        y = p.btn_cy + p.btn_link_amplitude * math.sin(angle)
        slope = p.btn_link_amplitude * 2 * math.pi / (x1 - x0) * math.cos(angle)
        normal_length = math.hypot(slope, 1)
        dx = -slope / normal_length * width / 2
        dy = width / (2 * normal_length)
        upper.append((x + dx, y + dy))
        lower.append((x - dx, y - dy))
    z0 = -0.1 if slot else -p.btn_protrude + p.btn_link_recess
    height = p.btn_collar_z + 0.2 if slot else thickness
    return (cq.Workplane("XY").workplane(offset=z0).moveTo(*upper[0])
            .spline(upper[1:], includeCurrent=True).lineTo(*lower[-1])
            .spline(list(reversed(lower[:-1])), includeCurrent=True)
            .close().extrude(height))


def build_front(p: Params = P) -> cq.Workplane:
    outer = rr_prism(p.W, p.L, p.seam, p.r_side)
    outer = outer.faces("<Z").edges().fillet(p.r_front)
    cavity = rr_prism(p.W - 2 * p.wall, p.L - 2 * p.wall,
                      p.seam + 0.1 - p.face_t, p.r_side - p.wall, p.face_t)
    # Original female joint. The opening grows toward the top of the print,
    # so the front has no inward shelf or unsupported continuous lip.
    socket = rr_prism(p.W - 2 * p.joint_wall, p.L - 2 * p.joint_wall,
                      p.seam + 0.1 - p.joint_start,
                      p.r_side - p.joint_wall, p.joint_start)
    front = outer.cut(cavity).cut(socket)
    for side in (-1, 1):
        for y in (-18, 18):
            x = side * (p.W / 2 - p.joint_wall - p.snap_bump / 2 + 0.01)
            detent = (cq.Workplane("XY").workplane(offset=p.snap_z)
                      .center(x, y).rect(p.snap_bump + 0.02, 4).extrude(0.6))
            front = front.union(detent)

    left = p.board_x - p.board_w / 2 - p.board_clear
    right = p.board_x + p.board_w / 2 + p.board_clear
    # Three separate guides per side and the original straight antenna-end
    # cross-rail. Its ends have no right-angle returns into the side guides.
    for x in (left - p.wall / 2, right + p.wall / 2):
        for y in p.board_guide_y:
            guide = (cq.Workplane("XY").workplane(offset=p.face_t - 0.01)
                     .center(x, y).rect(p.wall, p.board_guide_len)
                     .extrude(p.board_guide_top - p.face_t + 0.01))
            front = front.union(guide)
    end_guide = (cq.Workplane("XY").workplane(offset=p.face_t - 0.01)
                 .center((p.board_end_x0 + right) / 2, p.board_pocket_y0 - p.wall / 2)
                 .rect(right - p.board_end_x0, p.wall)
                 .extrude(p.board_guide_top - p.face_t + 0.01))
    front = front.union(end_guide)

    # A small local pad retains the original flat mounting plane without
    # thickening the entire antenna end wall.
    pad = (cq.Workplane("XZ").center(p.ant_x, p.ant_z)
           .circle(p.ant_pad_d / 2).extrude(-(p.ant_seat_y + p.L / 2 + 0.5))
           .translate((0, -p.L / 2 - 0.5, 0)).intersect(outer))
    pad = pad.intersect(cq.Workplane("XY").rect(p.W + 2, p.L + 2)
                        .extrude(p.joint_start))
    front = front.union(pad).cut(antenna_flange_cutter(p)).cut(antenna_cutter(p))

    front = front.cut(rr_slot(p.win_w, p.win_h, p.face_t + 1,
                              p.win_r, 0, p.win_cy, -0.5))
    front = front.edges(cq.selectors.BoxSelector(
        (-p.win_w / 2 - 0.01, p.win_cy - p.win_h / 2 - 0.01, -0.01),
        (p.win_w / 2 + 0.01, p.win_cy + p.win_h / 2 + 0.01, 0.01),
    )).fillet(p.win_roundover)

    seat_rise = (p.btn_seat_d - p.btn_bore) / 2
    for x in (p.btn_rst_x, p.btn_prg_x):
        collar = (cq.Workplane("XY").workplane(offset=p.face_t - 0.01)
                  .center(x, p.btn_cy).circle(p.btn_collar_d / 2)
                  .extrude(p.btn_collar_z - p.face_t + 0.01))
        front = front.union(collar)
        front = front.cut(cq.Workplane("XY").workplane(offset=-0.1)
                          .center(x, p.btn_cy).circle(p.btn_bore / 2)
                          .extrude(p.btn_collar_z + 0.2))
        seat = (cq.Workplane("XY").workplane(offset=p.btn_collar_z - seat_rise)
                .center(x, p.btn_cy).circle(p.btn_bore / 2)
                .workplane(offset=seat_rise).circle(p.btn_seat_d / 2).loft())
        front = front.cut(seat)
        bezel = (cq.Workplane("XY").workplane(offset=-0.01)
                 .center(x, p.btn_cy).circle(p.btn_bore / 2 + 0.15)
                 .workplane(offset=0.16).circle(p.btn_bore / 2).loft())
        front = front.cut(bezel)
    front = front.cut(button_link(p, tpu=True, clearance=p.btn_link_clear, slot=True))
    # No front-face text. This face is printed against the bed, so a recessed
    # label opens onto the build plate and its roof has to bridge/sag across
    # the letter cavities. The result is not reliable in PLA or ASA, and a
    # larger font only widens the unsupported span. Labels would need to move
    # to a vertical wall, or the front stays smooth.

    usb_z = p.usb_z0 + p.usb_h / 2
    usb = cutters_along_y(p.usb_w, p.usb_h, p.usb_h / 2 - 0.001,
                          p.L / 2 - 2, p.L / 2 + 1)
    front = front.cut(usb.translate((p.usb_x, 0, usb_z)))
    pocket = cutters_along_y(p.usb_pocket_w, p.usb_pocket_h, p.usb_pocket_r,
                             p.L / 2 - p.wall - 0.1,
                             p.L / 2 - p.wall + p.usb_pocket_depth)
    front = front.cut(pocket.translate((p.usb_x, 0,
                                        p.usb_pocket_z0 + p.usb_pocket_h / 2)))
    return front.clean()


def build_lid(p: Params = P) -> cq.Workplane:
    body_z = p.seam + p.seam_gap
    lid = rr_prism(p.W, p.L, p.T - body_z, p.r_side, body_z)
    lid = lid.faces(">Z").edges().fillet(p.r_back)
    # Shelling follows the back round-over and preserves wall thickness.
    lid = lid.faces("<Z").shell(-p.lid_wall)
    inset = p.joint_wall + p.joint_clear
    tongue_w = p.W - 2 * inset
    tongue_l = p.L - 2 * inset
    inner_w = tongue_w - 2 * p.tongue_wall
    inner_l = tongue_l - 2 * p.tongue_wall
    tongue_z = p.seam - p.tongue_h
    tongue = rr_prism(tongue_w, tongue_l, body_z - tongue_z + 0.01,
                       p.r_side - inset, tongue_z)
    tongue = tongue.cut(rr_prism(inner_w, inner_l, body_z - tongue_z + 0.03,
                                 p.r_side - inset - p.tongue_wall, tongue_z - 0.01))
    lid = lid.union(tongue)

    # A 45-degree transition supports the inside of the lid's tongue when
    # printing back down, with no abrupt inward lip at the skirt's root.
    rise = inset + p.tongue_wall - p.lid_wall
    transition = rr_prism(p.W - 2 * p.lid_wall + 0.02,
                          p.L - 2 * p.lid_wall + 0.02, rise + 0.01,
                          p.r_side - p.lid_wall + 0.01, body_z - 0.01)
    lower = rr_prism(inner_w, inner_l, 0.01,
                     p.r_side - inset - p.tongue_wall, body_z - 0.01)
    upper = rr_prism(p.W - 2 * p.lid_wall, p.L - 2 * p.lid_wall, 0.01,
                     p.r_side - p.lid_wall, body_z + rise)
    void = cq.Solid.makeLoft([lower.faces("<Z").wires().val(),
                             upper.faces("<Z").wires().val()], ruled=True)
    lid = lid.union(transition.cut(void))
    for side in (-1, 1):
        for y in (-18, 18):
            x = side * (p.W / 2 - p.joint_wall - p.snap_bump / 2)
            groove = (cq.Workplane("XY").workplane(offset=p.snap_z - 0.15)
                      .center(x, y).rect(p.snap_bump + 0.12, 4.4).extrude(0.9))
            lid = lid.cut(groove)
    return lid.cut(antenna_flange_cutter(p)).clean()


def build_buttons(p: Params = P, *, tpu: bool = False,
                  travel: tuple[float, float] = (0.0, 0.0)) -> cq.Workplane:
    """One connected pair of captive plungers, printed finger faces down.

    The rear flange grows at 45 degrees and the link lies on the build plate,
    so the whole part prints without support. TPU uses a little more sliding
    clearance and a thicker contact stem. A matching countersink in the
    housing captures both versions from the front.
    """
    diameter = p.btn_tpu_cap_d if tpu else p.btn_cap_d
    stem_d = p.btn_tpu_stem_d if tpu else p.btn_stem_d
    top = -p.btn_protrude
    taper_z = p.btn_collar_z - (p.btn_lip_d - diameter) / 2
    contact_z = p.board_pcb_top - p.board_switch_dZ - p.btn_switch_gap
    parts = []
    for x, displacement in zip((p.btn_rst_x, p.btn_prg_x), travel):
        body = (cq.Workplane("XY").workplane(offset=top).center(x, p.btn_cy)
                .circle(diameter / 2).extrude(taper_z - top))
        body = body.faces("<Z").edges().fillet(0.25)
        taper = (cq.Workplane("XY").workplane(offset=taper_z).center(x, p.btn_cy)
                 .circle(diameter / 2).workplane(offset=p.btn_collar_z - taper_z)
                 .circle(p.btn_lip_d / 2).loft())
        flange = (cq.Workplane("XY").workplane(offset=p.btn_collar_z)
                  .center(x, p.btn_cy).circle(p.btn_lip_d / 2).extrude(p.btn_lip_t))
        stem = (cq.Workplane("XY").workplane(offset=p.btn_collar_z + p.btn_lip_t)
                .center(x, p.btn_cy).circle(stem_d / 2)
                .extrude(contact_z - p.btn_collar_z - p.btn_lip_t))
        plunger = body.union(taper).union(flange).union(stem).clean()
        parts.append(plunger.translate((0, 0, displacement)))
    link = button_link(p, tpu=tpu)
    if travel != (0.0, 0.0):
        # Clearance pose only. The affine shear spans the two cap movements,
        # without claiming to model the flexure's mechanical deformation.
        x0 = p.btn_rst_x + 2.4
        x1 = p.btn_prg_x - 2.4
        slope = (travel[1] - travel[0]) / (x1 - x0)
        transform = cq.Matrix([[1, 0, 0, 0], [0, 1, 0, 0],
                               [slope, 0, 1, travel[0] - slope * x0], [0, 0, 0, 1]])
        link = cq.Workplane(obj=link.val().transformGeometry(transform))
    return parts[0].union(parts[1]).union(link).clean()


def bbox(part: cq.Workplane) -> dict:
    b = part.val().BoundingBox()
    return dict(x0=b.xmin, x1=b.xmax, y0=b.ymin, y1=b.ymax, z0=b.zmin, z1=b.zmax)


def describe(name: str, part: cq.Workplane) -> dict:
    b = bbox(part)
    volume = part.val().Volume()
    return {"name": name, "bbox": b,
            "size": [round(b[axis + "1"] - b[axis + "0"], 4) for axis in "xyz"],
            "volume_mm3": round(volume, 3), "volume_cm3": round(volume / 1000, 3),
            "mass_g_petg": round(volume / 1000 * 1.27, 1),
            "mass_g_asa": round(volume / 1000 * 1.07, 1),
            "mass_g_tpu95": round(volume / 1000 * 1.21, 1)}


def export_part(part: cq.Workplane, name: str, *, rotate_print: bool = False,
                translate_print: float | None = None, step: bool = True) -> str:
    os.makedirs(OUT, exist_ok=True)
    printing = part
    if rotate_print:
        printing = printing.rotate((0, 0, 0), (1, 0, 0), 180)
    if translate_print is not None:
        printing = printing.translate((0, 0, translate_print))
    printing = printing.translate((0, 0, -bbox(printing)["z0"]))
    path = os.path.join(OUT, name + ".stl")
    exporters.export(printing, path, tolerance=0.02, angularTolerance=0.15)
    if step:
        exporters.export(part, os.path.join(OUT, name + ".step"))
    return path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-export", action="store_true")
    args = parser.parse_args()
    parts = {"front": build_front(), "lid": build_lid(),
             "buttons_rigid": build_buttons(), "buttons_tpu95a": build_buttons(tpu=True)}
    for name, part in parts.items():
        if len(part.solids().vals()) != 1 or not part.val().isValid():
            raise ValueError(f"{name} must be one valid solid")
    report = {"params": asdict(P), "parts": [describe(k, v) for k, v in parts.items()]}
    print(json.dumps(report["parts"], indent=2))
    if args.no_export:
        return
    assembly = cq.Assembly()
    for name, part in parts.items():
        export_part(part, "case_v2_" + name, rotate_print=name == "lid")
        if name != "buttons_tpu95a":
            assembly.add(part, name=name)
    assembly.export(os.path.join(OUT, "case_v2_assembly.step"))
    with open(os.path.join(OUT, "case_v2_report.json"), "w") as output:
        json.dump(report, output, indent=2)
    print("Wrote", OUT)


if __name__ == "__main__":
    main()
