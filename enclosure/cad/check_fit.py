"""Check the original seating planes and the revised enclosure clearances.

Run with the CAD environment from the repository root
    python enclosure/cad/check_fit.py

The PCB check uses the nominal rectangular PCB envelope. Component heights
and printed ASA tolerances require a physical fit check.
"""
import cadquery as cq

import case_v2 as model


def require_clear(front: cq.Workplane, name: str, part: cq.Workplane) -> None:
    overlap = front.intersect(part).val().Volume()
    if overlap > 1e-6:
        raise ValueError(f"{name} intersects the front by {overlap:.6f} mm3")


def main() -> None:
    p = model.P
    front = model.build_front()
    lid = model.build_lid()
    buttons = model.build_buttons()
    for name, part in (("front", front), ("lid", lid), ("buttons", buttons)):
        if len(part.solids().vals()) != 1 or not part.val().isValid():
            raise ValueError(f"{name} must be one valid solid")

    board_y1 = p.board_cy + p.board_switch_x - p.board_usb_tip
    board_y0 = board_y1 - p.board_l
    insertion = (cq.Workplane("XY").workplane(offset=p.board_pcb_top)
                 .center(p.board_x, (board_y0 + board_y1) / 2)
                 .rect(p.board_w, p.board_l)
                 .extrude(p.seam + 1 - p.board_pcb_top))
    require_clear(front, "PCB and insertion path", insertion)
    require_clear(front, "lid", lid)
    require_clear(front, "button bar", buttons)
    require_clear(front, "antenna hole", model.antenna_cutter())
    usb = model.cutters_along_y(
        p.usb_w, p.usb_h, p.usb_h / 2 - 0.001,
        p.L / 2 - 1.5, p.L / 2 + 1,
    ).translate((p.usb_x, 0, p.usb_z0 + p.usb_h / 2))
    require_clear(front, "USB opening", usb)
    screen = model.rr_slot(
        p.win_w, p.win_h, p.face_t + 0.5, 0, 0, p.win_cy, -0.1)
    require_clear(front, "screen throat", screen)

    # Inner contact planes measured from the centred original front 3MF.
    planes = ((-11.43, 0, 1, 0), (14.351, 0, -1, 0),
              (0, -15.9639, 0, 1), (-15, -10.8839, 0, 1))
    for x, y, nx, ny in planes:
        for z in (2, 6, 9.5):
            for side in (-1, 1):
                point = (x + nx * side * 0.01, y + ny * side * 0.01, z)
                if front.val().isInside(point) != (side < 0):
                    raise ValueError(f"Original guide plane differs at {point}")

    ramp_bottom = p.seam - p.tongue_h - p.tongue_step
    for rise in (0.1, 0.4, 0.7, 1.0, 1.3):
        inner_x = p.W / 2 - p.wall - rise
        z = ramp_bottom + rise
        if (not front.val().isInside((inner_x + 0.01, 0, z))
                or front.val().isInside((inner_x - 0.01, 0, z))):
            raise ValueError(f"Inner transition differs from 45 degrees at Z={z}")
    print("Fit checks passed for the seating planes, insertion path, openings, buttons and lid.")


if __name__ == "__main__":
    main()
