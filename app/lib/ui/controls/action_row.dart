/// A19.5 — ActionRow (design 14 §14.7).
///
/// The 3-up secondary grid under the cook dashboard: Mark · Test alarm · Export.
/// These are secondary by construction — never ember-filled, never competing
/// with the screen's one [PrimaryAction].
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

class ActionRowItem {
  const ActionRowItem({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

class ActionRow extends StatelessWidget {
  const ActionRow({super.key, required this.items});

  final List<ActionRowItem> items;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: InkWell(
              onTap: items[i].onTap,
              borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(
                    SmokeTokens.radiusControl,
                  ),
                  border: Border.all(color: t.hairline),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(items[i].icon, color: StatusPalette.pit, size: 22),
                    const SizedBox(height: SmokeTokens.s1),
                    Text(
                      items[i].label,
                      style: SmokeType.bodySm.copyWith(
                        color: t.textBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
