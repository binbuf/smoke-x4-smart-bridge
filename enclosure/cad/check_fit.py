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
    tpu_buttons = model.build_buttons(tpu=True)
    for name, part in (("front", front), ("lid", lid),
                        ("buttons_rigid", buttons), ("buttons_tpu", tpu_buttons)):
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
    pcb = (cq.Workplane("XY").workplane(offset=p.board_pcb_top)
           .center(p.board_x, (board_y0 + board_y1) / 2)
           .rect(p.board_w, p.board_l).extrude(p.board_t))
    usb_body = model.cutters_along_y(
        p.usb_w, p.usb_h, p.usb_h / 2 - 0.001, p.btn_cy - 4, p.L / 2
    ).translate((p.usb_x, 0, p.usb_z0 + p.usb_h / 2))
    for name, pair in (("rigid", buttons), ("TPU", tpu_buttons)):
        require_clear(front, name + " buttons", pair)
        require_clear(front, name + " buttons at 0.4 mm travel", pair.translate((0, 0, 0.4)))
        for offset in (0.25, 0.5, 1, 1.5, 2, 3, 5, 10, p.seam + 1):
            require_clear(front, name + " rear installation path", pair.translate((0, 0, offset)))
        for travel in ((0.4, 0.0), (0.0, 0.4), (0.4, 0.4)):
            pose = model.build_buttons(tpu=name == "TPU", travel=travel)
            if len(pose.solids().vals()) != 1 or not pose.val().isValid():
                raise ValueError(name + " buttons separate during the clearance pose")
            require_clear(front, name + " independent button travel", pose)
            require_clear(lid, name + " button/lid clearance", pose)
            require_clear(pcb, name + " button/PCB clearance", pose)
            require_clear(usb_body, name + " button/USB clearance", pose)
        if front.intersect(pair.translate((0, 0, -0.25))).val().Volume() < 1e-6:
            raise ValueError(name + " buttons can escape through the front")
        contact_z = model.bbox(pair)["z1"]
        switch_z = p.board_pcb_top - p.board_switch_dZ
        if abs(switch_z - contact_z - p.btn_switch_gap) > 1e-6:
            raise ValueError(name + " buttons have the wrong switch clearance")
    # The link should lie on the bed (recess 0) or stay behind the finger
    # faces; it must never finish behind the case front.
    if not (0 <= p.btn_link_recess < p.btn_protrude):
        raise ValueError("The button link is outside the printable face plane")
    require_clear(front, "antenna hole", model.antenna_cutter())
    flange = model.antenna_flange_cutter()
    require_clear(front, "antenna connector lip", flange)
    require_clear(lid, "antenna connector lip in the lid skirt", flange)
    battery = model.rr_slot(p.bat_w, p.bat_l, p.bat_t, 0, 0,
                            p.bat_y_top - p.bat_l / 2, p.bat_z0)
    require_clear(front, "battery", battery)
    require_clear(lid, "battery", battery)
    usb = model.cutters_along_y(
        p.usb_w, p.usb_h, p.usb_h / 2 - 0.001,
        p.L / 2 - 1.5, p.L / 2 + 1,
    ).translate((p.usb_x, 0, p.usb_z0 + p.usb_h / 2))
    require_clear(front, "USB opening", usb)
    screen = model.rr_slot(
        p.win_w, p.win_h, p.face_t + 0.5, 0, 0, p.win_cy, -0.1)
    require_clear(front, "screen throat", screen)

    # Inner contact planes measured from the centred original front 3MF.
    planes = ((-11.43, 1), (14.351, -1))
    for x, nx in planes:
        for y in p.board_guide_y:
            for z in (2, 6, 9.5):
                for side in (-1, 1):
                    point = (x + nx * side * 0.01, y, z)
                    if front.val().isInside(point) != (side < 0):
                        raise ValueError(f"Original guide plane differs at {point}")

    # The original antenna position and mounting plane preserve its lip's
    # vertical space. The floor is thinner, adding clearance beneath the lip.
    if (abs(p.ant_z - 6.3627) > 0.001 or abs(p.ant_x + 11.8745) > 0.001
            or abs(p.ant_seat_y + 36.1315) > 0.001):
        raise ValueError("Antenna mounting datums differ from the original case")
    if p.ant_z - (p.ant_flange_d / 2 + p.ant_flange_clear) <= p.face_t:
        raise ValueError("The connector lip's clearance reaches the front floor")

    # At the socket, the opening must grow outward in the print direction.
    # Sample away from the detents and board rails.
    for z, thickness in ((p.joint_start - 0.1, p.wall),
                          (p.joint_start + 0.1, p.joint_wall)):
        inner_x = p.W / 2 - thickness
        if (not front.val().isInside((inner_x + 0.01, -25, z))
                or front.val().isInside((inner_x - 0.01, -25, z))):
            raise ValueError(f"Front socket differs from the thin-wall design at Z={z}")

    # A PCB can move .4 mm into each guide's outer face. The added material
    # must finish within 1.2 mm, leaving the original filled surround empty.
    for x in (-11.43, 14.351):
        direction = -1 if x < 0 else 1
        for y in p.board_guide_y:
            if not front.val().isInside((x + direction * 0.6, y, 5)):
                raise ValueError("Board guide is missing")
            if front.val().isInside((x + direction * 1.3, y, 5)):
                raise ValueError("Excess filled material remains around the board")
        for y in (0, 20, 34):
            if front.val().isInside((x + direction * 0.6, y, 5)):
                raise ValueError("A gap between guide sections is filled")
    for x in (0, 6, 13.8):
        for z in (2, 6, 9.5):
            if not front.val().isInside((x, p.board_pocket_y0 - 0.6, z)):
                raise ValueError("The straight antenna-end rail is missing")
            if front.val().isInside((x, p.board_pocket_y0 + 0.01, z)):
                raise ValueError("The antenna-end rail intrudes into the original PCB pocket")
    for point in ((-15, -11.5, 5), (14.8, -16.5, 5), (14.8, -14.5, 5)):
        if front.val().isInside(point):
            raise ValueError(f"A perpendicular rail return remains at {point}")
    if not lid.val().isInside((p.ant_x, p.ant_seat_y - 0.1, 10.5)):
        raise ValueError("The cancelled antenna skirt relief remains")
    print("Fit checks passed for one-piece buttons, rear installation, independent travel, "
          "PCB/USB/lid clearance, rails and openings.")


if __name__ == "__main__":
    main()
