"""
Two 2D technical figures for the v2 enclosure documentation.

    python enclosure/cad/figures.py

* case-v2-thickness.png : v1 vs v2 side section, aligned at the front face
* case-v2-joint.png     : lap/snap joint detail (0.15 mm/side)
"""
from __future__ import annotations

import os
import sys
import tempfile

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, FancyArrowPatch
import numpy as np
import trimesh
from cadquery import exporters

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import case_v2 as m  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
RENDERS = os.path.abspath(os.path.join(HERE, "..", "docs", "renders"))
REF = os.path.abspath(os.path.join(HERE, "..", "docs", "reference"))
os.makedirs(RENDERS, exist_ok=True)
P = m.P


def mesh_from_wp(wp):
    f = tempfile.NamedTemporaryFile(suffix=".stl", delete=False)
    f.close()
    exporters.export(wp, f.name, tolerance=0.01)
    return trimesh.load(f.name)


def loops(mesh, origin, normal):
    s = mesh.section(plane_origin=origin, plane_normal=normal)
    out = []
    if s is None:
        return out
    for ent in s.entities:
        pts = s.vertices[ent.points]
        out.append(pts)
    return out


def draw_loops(ax, ls, a, b, color, lw=1.2, alpha=1.0, ls_style="-"):
    for pts in ls:
        ax.plot(pts[:, a], pts[:, b], color=color, lw=lw, alpha=alpha,
                linestyle=ls_style)


def total_dim(ax, z0, z1, x, label, color="#33414d"):
    ax.annotate("", xy=(x, z1), xytext=(x, z0),
                arrowprops=dict(arrowstyle="<->", color=color, lw=1.2))
    ax.text(x + 0.6, (z0 + z1) / 2, label, rotation=90, va="center",
            ha="left", color=color, fontsize=9)


def fig_thickness():
    # ---- v1 (old) -----------------------------------------------------
    old_f = trimesh.load(os.path.join(REF, "heltecV3_case-front_v1.stl"))
    old_b = trimesh.load(os.path.join(REF, "heltecV3_case-back_v1r1.stl"))
    old_b.apply_translation([0, 0, 5.08])
    old_f.apply_translation([0, 0, 15.1892])
    old_b.apply_translation([0, 0, 15.1892])
    old_loops = loops(old_f, [0, 0, 0], [1, 0, 0]) + \
        loops(old_b, [0, 0, 0], [1, 0, 0])

    # ---- v2 (new) -----------------------------------------------------
    front = mesh_from_wp(m.build_front())
    lid = mesh_from_wp(m.build_lid())
    bar = mesh_from_wp(m.build_buttons())
    f_loops = loops(front, [0, 0, 0], [1, 0, 0])
    l_loops = loops(lid, [0, 0, 0], [1, 0, 0])
    b_loops = loops(bar, [0, 0, 0], [1, 0, 0])

    fig, ax = plt.subplots(figsize=(10.5, 7.4))
    draw_loops(ax, old_loops, 1, 2, "#b9bec3", lw=1.4, alpha=1.0)
    # old totals
    total_dim(ax, 0.0, 26.99, -(P.L / 2 + 6.0), "v1  27.0 mm", "#8f9499")

    # new shell
    for ls, c in ((f_loops, "#7f97aa"), (l_loops, "#c39a66"),
                  (b_loops, "#39454e")):
        draw_loops(ax, ls, 1, 2, c, lw=1.5)

    # board + battery stack
    board = Rectangle((-18.36, 1.35), 52.29, 7.77, facecolor="#4f9a6a",
                      edgecolor="#2c6343", alpha=0.55, lw=0.8)
    bat = Rectangle((P.bat_y_top - P.bat_l, 10.9), P.bat_l, P.bat_t,
                    facecolor="#4a6c93", edgecolor="#2d4765", alpha=0.55, lw=0.8)
    ax.add_patch(board)
    ax.add_patch(bat)
    ax.text(5.0, 5.0, "Heltec V3\n(7.8 mm)", ha="center", va="center",
            fontsize=8, color="#20452f")
    ax.text(-15.0, 15.6, "PL103665 3000 mAh\n(10.3 mm)", ha="center",
            va="center", fontsize=8, color="#1e3349")

    total_dim(ax, 0.0, P.T, (P.L / 2 + 6.0), "v2  22.6 mm", "#33414d")

    # wall call-outs
    ax.annotate("front wall 1.2", xy=(0, 0.6), xytext=(12, -3.6),
                fontsize=8, ha="center",
                arrowprops=dict(arrowstyle="->", lw=0.8, color="#33414d"))
    ax.annotate("lid back 1.2", xy=(0, P.T - 0.6), xytext=(12, P.T + 3.0),
                fontsize=8, ha="center",
                arrowprops=dict(arrowstyle="->", lw=0.8, color="#33414d"))
    ax.annotate("seam / lap joint", xy=(-19.1, 7.4), xytext=(-31, 3.0),
                fontsize=8, ha="center",
                arrowprops=dict(arrowstyle="->", lw=0.8, color="#33414d"))

    ax.set_aspect("equal")
    ax.set_xlim(-P.L / 2 - 10, P.L / 2 + 10)
    ax.set_ylim(-6, P.T + 6)
    ax.text(-P.L / 2 - 4.5, P.T + 2.0, "antenna end", fontsize=8, ha="center",
            color="#8f9499")
    ax.text(P.L / 2 + 4.5, P.T + 2.0, "USB end", fontsize=8, ha="center",
            color="#8f9499")
    ax.set_xlabel("Y (mm)  - antenna end (left) / USB end (right)")
    ax.set_ylabel("Z (mm)  - front face to back")
    ax.set_title("Enclosure thickness: v1 (grey) vs v2 (coloured), section at X=0")
    ax.grid(alpha=0.2)
    ax.legend(handles=[
        Rectangle((0, 0), 1, 1, color="#b9bec3", label="v1 shell (27.0 mm)"),
        Rectangle((0, 0), 1, 1, color="#7f97aa", label="v2 front"),
        Rectangle((0, 0), 1, 1, color="#c39a66", label="v2 lid"),
        Rectangle((0, 0), 1, 1, color="#4f9a6a", alpha=0.55, label="PCB/board"),
        Rectangle((0, 0), 1, 1, color="#4a6c93", alpha=0.55, label="battery"),
    ], loc="lower left", fontsize=8, framealpha=0.9)
    fig.tight_layout()
    fig.savefig(os.path.join(RENDERS, "case-v2-thickness.png"), dpi=180)
    plt.close(fig)


def fig_joint():
    front = mesh_from_wp(m.build_front())
    lid = mesh_from_wp(m.build_lid())
    f_loops = loops(front, [0, 18.0, 0], [0, 1, 0])
    l_loops = loops(lid, [0, 18.0, 0], [0, 1, 0])

    fig, ax = plt.subplots(figsize=(9.5, 6.4))
    draw_loops(ax, f_loops, 0, 2, "#2f6f95", lw=2.0)
    draw_loops(ax, l_loops, 0, 2, "#a86b2c", lw=2.0)
    ax.axhline(P.seam, color="#33414d", lw=0.7, ls=(0, (4, 3)))

    ax.annotate("", xy=(18.05, P.seam + 0.22), xytext=(17.05, P.seam + 0.22),
                arrowprops=dict(arrowstyle="<->", lw=0.8))
    ax.text(17.55, P.seam + 0.5, "1.0 tongue", ha="center", va="bottom",
            fontsize=8)
    ax.annotate("0.15 clearance/side", xy=(18.12, 9.9), xytext=(14.0, 11.4),
                fontsize=8, arrowprops=dict(arrowstyle="->", lw=0.8))
    ax.annotate("0.30 snap bump", xy=(18.35, 8.95), xytext=(14.2, 7.8),
                fontsize=8, arrowprops=dict(arrowstyle="->", lw=0.8))
    ax.annotate("3.2 mm overlap", xy=(18.5, 8.9), xytext=(15.0, 10.6),
                fontsize=8, arrowprops=dict(arrowstyle="->", lw=0.8))
    ax.annotate("lid wall 1.2", xy=(19.0, 11.3), xytext=(15.6, 12.4),
                fontsize=8, arrowprops=dict(arrowstyle="->", lw=0.8))
    ax.annotate("front wall 1.2", xy=(18.8, 5.8), xytext=(15.5, 4.6),
                fontsize=8, arrowprops=dict(arrowstyle="->", lw=0.8))

    ax.set_aspect("equal")
    ax.set_xlim(13.6, 19.6)
    ax.set_ylim(4.4, 13.0)
    ax.set_xlabel("X (mm)")
    ax.set_ylabel("Z (mm)")
    ax.set_title("Front/lid lap + snap joint (section at Y=18)")
    ax.grid(alpha=0.2)
    ax.legend(handles=[
        Rectangle((0, 0), 1, 1, color="#2f6f95", label="front housing"),
        Rectangle((0, 0), 1, 1, color="#a86b2c", label="lid"),
    ], loc="upper left", fontsize=8)
    fig.tight_layout()
    fig.savefig(os.path.join(RENDERS, "case-v2-joint.png"), dpi=180)
    plt.close(fig)




def fig_seat():
    """End view: 10 mm washer seat, 6.5 mm hole, washer outline."""
    fig, ax = plt.subplots(figsize=(8.6, 6.6))
    # case end face (front half at the bottom, lid above the seam)
    ax.add_patch(Rectangle((-19.4, 0.0), 38.8, 22.6, facecolor="#b8b2a5",
                           edgecolor="#5f5a50", lw=1.2, alpha=0.55))
    ax.add_patch(Rectangle((-19.4, 7.4), 38.8, 15.2, facecolor="#c39a66",
                           edgecolor="#7a4b1e", lw=1.0, alpha=0.35))
    # seam and back round-over tangent
    ax.axhline(7.4, color="#5f5a50", lw=0.9, ls=(0, (4, 3)))
    ax.axhline(19.6, color="#7a4b1e", lw=0.7, ls=(0, (2, 4)))
    # washer and seat are both 10 mm; draw washer dashed, seat solid
    ax.add_patch(plt.Circle((P.ant_x, P.ant_z), P.ant_seat_d / 2.0,
                            facecolor="white", edgecolor="#7a4b1e", lw=1.4))
    ax.add_patch(plt.Circle((P.ant_x, P.ant_z), 4.75, fill=False,
                            edgecolor="#1f4d6b", lw=1.0, ls=(0, (3, 3))))
    ax.add_patch(plt.Circle((P.ant_x, P.ant_z), P.ant_d / 2.0,
                            facecolor="#2f6f95", edgecolor="#1f4d6b", lw=1.0))
    ax.annotate("10.0 mm dia washer seat\nflat floor, 0.3 mm deep",
                xy=(P.ant_x + 3.6, P.ant_z + 3.6), xytext=(-1.0, 20.8),
                fontsize=9, ha="left",
                arrowprops=dict(arrowstyle="->", lw=0.8))
    ax.annotate("6.5 mm through hole", xy=(P.ant_x + 2.2, P.ant_z - 2.2),
                xytext=(1.0, 10.2), fontsize=9,
                arrowprops=dict(arrowstyle="->", lw=0.8))
    ax.annotate("9.5-10 mm kit washer (dashed)", xy=(P.ant_x + 4.2, P.ant_z - 2.8),
                xytext=(-1.0, 4.6), fontsize=9,
                arrowprops=dict(arrowstyle="->", lw=0.8))
    ax.text(17.0, 8.2, "seam", fontsize=8, ha="right", color="#5f5a50")
    ax.text(17.0, 20.1, "back round-over starts", fontsize=8, ha="right",
            color="#7a4b1e")
    ax.set_aspect("equal")
    ax.set_xlim(-20.5, 20.5)
    ax.set_ylim(-1.0, 24.0)
    ax.set_xlabel("X (mm)  - 9.55 left of centre")
    ax.set_ylabel("Z (mm)  - front face at 0")
    ax.set_title("Antenna end view: 10 mm washer seat in the lid")
    ax.grid(alpha=0.15)
    fig.tight_layout()
    fig.savefig(os.path.join(RENDERS, "case-v2-antenna-seat.png"), dpi=180)
    plt.close(fig)


if __name__ == "__main__":
    fig_thickness()
    fig_joint()
    fig_seat()
    print("figures written")
