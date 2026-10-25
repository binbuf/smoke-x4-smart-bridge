"""
Render the v2 enclosure from the parametric model.

    python enclosure/cad/render.py

Writes PNGs to enclosure/docs/renders and step_v2_assembly.step to
enclosure/out.  Uses pyvista off-screen; no GPU required.
"""
from __future__ import annotations

import os
import sys

import cadquery as cq
import numpy as np
import pyvista as pv
from cadquery import importers

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import case_v2 as m  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
RENDERS = os.path.abspath(os.path.join(HERE, "..", "docs", "renders"))
OUT = os.path.abspath(os.path.join(HERE, "..", "out"))
os.makedirs(RENDERS, exist_ok=True)
pv.OFF_SCREEN = True

P = m.P
C_BODY = "#96a4ad"
C_LID = "#8d9aa3"
C_BAR = "#333e46"
C_BOARD = "#2f7d4d"
C_BAT = "#35506e"
C_CUT = "#d8c8a8"


def to_pv(wp: cq.Workplane, tol: float = 0.02) -> pv.PolyData:
    v, f = wp.val().tessellate(tol, 0.18)
    verts = [(p.x, p.y, p.z) for p in v]
    faces = []
    for tri in f:
        faces.extend([3, int(tri[0]), int(tri[1]), int(tri[2])])
    return pv.PolyData(verts, faces)


def board_mesh() -> pv.PolyData:
    board = importers.importStep(
        os.path.join(HERE, "..", "docs", "reference", "heltec_v3_board.step"))
    board = (board.rotate((0, 0, 0), (0, 0, 1), 90)
             .rotate((0, 0, 0), (1, 0, 0), 180)
             .translate((0, P.board_cy + P.board_switch_x, P.board_pcb_top)))
    return to_pv(board, tol=0.15)


def battery_mesh() -> pv.PolyData:
    box = (cq.Workplane("XY").workplane(offset=10.9)
           .center(0, (P.bat_y_top + (P.bat_y_top - P.bat_l)) / 2)
           .rect(P.bat_w, P.bat_l).extrude(P.bat_t))
    # soften the corners a touch for the render
    box = box.edges("|Z").fillet(2.5)
    return to_pv(box)


def shot(mesh, name, view, up=(0, 1, 0), size=(1200, 1200), zoom=1.0,
         extra=(), ssao=True, edge=False):
    p = pv.Plotter(off_screen=True, window_size=size)
    p.add_mesh(mesh, color=C_BODY, smooth_shading=False, ambient=0.30,
               diffuse=0.68, specular=0.30)
    for (mm, cc, op) in extra:
        p.add_mesh(mm, color=cc, smooth_shading=False, ambient=0.30,
                   diffuse=0.68, specular=0.20, opacity=op)
    if ssao:
        p.enable_ssao()
    p.enable_parallel_projection()
    p.view_vector(view, viewup=up)
    p.camera.zoom(zoom)
    p.show(screenshot=os.path.join(RENDERS, name + ".png"))
    p.close()


def main():
    print("building ...")
    front = m.build_front()
    lid = m.build_lid()
    bar = m.build_buttons()
    fv, lv, bv = to_pv(front), to_pv(lid), to_pv(bar)
    bd = board_mesh()
    bt = battery_mesh()

    # ---- front / back / exploded -------------------------------------
    shot(fv, "case-v2-front", (0.65, -0.65, -1), up=(0, -1, 0), zoom=1.06)
    shot(lv, "case-v2-back", (0.65, -0.65, 1), up=(0, -1, 0), zoom=1.06)
    p = pv.Plotter(off_screen=True, window_size=(1600, 1100))
    p.add_mesh(fv, color=C_BODY, ambient=.3, diffuse=.7, specular=.3)
    p.add_mesh(bv.translate((0, 0, -8)), color=C_BAR, ambient=.3,
               diffuse=.65, specular=.25)
    p.add_mesh(bd.translate((52, 0, 12)), color=C_BOARD, ambient=.3,
               diffuse=.7, specular=.2)
    p.add_mesh(bt.translate((0, 0, 27)), color=C_BAT, ambient=.3,
               diffuse=.7, specular=.2)
    p.add_mesh(lv.translate((0, 0, 41)), color=C_LID, ambient=.3,
               diffuse=.7, specular=.3)
    p.enable_ssao()
    p.enable_parallel_projection()
    p.view_vector((0.75, -0.75, -0.45), viewup=(0, 0, 1))
    p.camera.zoom(0.8)
    p.show(screenshot=os.path.join(RENDERS, "case-v2-exploded.png"))
    p.close()

    # ---- full assembly, antenna up ------------------------------------
    asm = fv.copy().merge(lv).merge(bv)
    shot(asm, "case-v2-assembly", (0.65, -0.65, -1), up=(0, -1, 0), zoom=1.06)

    # ---- board cradle, viewed from the open back ----------------------
    shot(fv, "case-v2-cradle", (0.55, -0.5, 1), up=(0, -1, 0), zoom=1.02)

    # ---- button pod ---------------------------------------------------
    pod = asm.clip_box(bounds=(-16, 16, 23, 38, -1, 4), invert=False)
    shot(pod, "case-v2-buttons", (0.25, -0.5, -1), up=(0, -1, 0), zoom=1.0,
         size=(1200, 900))
    # straight on, for label check
    shot(pod, "case-v2-buttons-front", (0, -0.05, -1), up=(0, -1, 0), zoom=1.0,
         size=(1200, 900))

    # ---- ports --------------------------------------------------------
    top = asm.clip_box(bounds=(-16, 16, 32, 39, -1, 24), invert=False)
    shot(top, "case-v2-usb", (0.0, 1.0, -0.35), zoom=1.0, size=(1200, 900))
    bot = asm.clip_box(bounds=(-16, 16, -39, -30, -1, 24), invert=False)
    shot(bot, "case-v2-antenna", (0.0, -1.0, -0.35), zoom=1.0,
         size=(1200, 900))

    # ---- section through the stack (x = 0) ---------------------------
    p = pv.Plotter(off_screen=True, window_size=(1600, 900))
    for mesh, color, op in ((fv, C_BODY, 1.0), (bd, C_BOARD, 1.0),
                            (bt, C_BAT, 1.0), (lv, C_LID, 1.0),
                            (bv, C_BAR, 1.0)):
        c = mesh.clip(normal=(1, 0, 0), origin=(0, 0, 0))
        p.add_mesh(c, color=color, ambient=.35, diffuse=.7,
                   specular=.2, opacity=op)
    p.enable_ssao()
    p.enable_parallel_projection()
    p.view_vector((1, -0.15, 0.05), viewup=(0, 0, 1))
    p.show(screenshot=os.path.join(RENDERS, "case-v2-section.png"))
    p.close()

    # ---- assembly step -------------------------------------------------
    assy = cq.Assembly()
    assy.add(front, name="front", color=cq.Color(C_BODY))
    assy.add(lid, name="lid", color=cq.Color(C_LID))
    assy.add(bar, name="button_bar", color=cq.Color(C_BAR))
    assy.save(os.path.join(OUT, "case_v2_assembly.step"))
    print("renders + assembly written")


if __name__ == "__main__":
    main()
