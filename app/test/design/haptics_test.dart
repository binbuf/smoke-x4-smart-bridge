/// The haptic vocabulary (newapp §H.2).
///
/// §H.2 asks for *"a light impact for advisory, a distinct pattern for
/// critical"*, and before this the whole app had one call — `heavyImpact` —
/// which meant a target reached felt exactly like a pit crash. A buzz that
/// cannot be told apart from another buzz carries no information, and this app
/// is read through a coat pocket at 3 a.m. more often than it is looked at.
///
/// So these assertions are about *distinguishability*, not about which
/// constant is used: every intent must produce a different sequence of
/// platform calls, and `critical` must be the only two-event one.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';

/// The platform calls one intent produces, in order.
List<String> _capture(void Function() action) {
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      calls.add((call.arguments as String?) ?? 'vibrate');
    }
    return null;
  });
  action();
  messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every intent feels different from every other one', () {
    final byIntent = {
      for (final h in SmokeHaptic.values) h: _capture(() => SmokeHaptics.fire(h)),
    };

    for (final entry in byIntent.entries) {
      expect(
        entry.value,
        isNotEmpty,
        reason: '${entry.key} raised no haptic at all',
      );
    }
    expect(
      byIntent.values.map((c) => c.join('+')).toSet(),
      hasLength(SmokeHaptic.values.length),
      reason:
          'two intents produce the same buzz, so one of them is carrying no '
          'information',
    );
  });

  test('critical is the one two-event pattern, and it ends in a buzz', () {
    final critical = _capture(() => SmokeHaptics.fire(SmokeHaptic.critical));
    expect(critical, hasLength(2));
    expect(critical.first, 'HapticFeedbackType.heavyImpact');
    expect(
      critical.last,
      'vibrate',
      reason:
          'the tail is a longer buzz, not a harder tap — amplitude is not a '
          'channel a person can read through a pocket, texture is',
    );

    for (final h in SmokeHaptic.values.where((h) => h != SmokeHaptic.critical)) {
      expect(
        _capture(() => SmokeHaptics.fire(h)),
        hasLength(1),
        reason: '$h must stay a single event so critical stands alone',
      );
    }
  });

  test('crossing a target is advisory-light, not an alarm', () {
    // §H.2: "a light impact for advisory". The pull tick and a band re-entry
    // are things you may want to know, not a summons.
    expect(
      _capture(SmokeHaptics.thresholdCrossed),
      ['HapticFeedbackType.lightImpact'],
    );
    // §14.6.6 pins the target itself at a medium impact — the ring closing is
    // a completion, and it earns more than an advisory and less than an alarm.
    expect(
      _capture(SmokeHaptics.targetReached),
      ['HapticFeedbackType.mediumImpact'],
    );
  });

  test('the buzz agrees with the border it is drawn beside', () {
    // One table, not two: chrome picks a StatusRole, and the haptic is
    // derived from it, so a banner cannot say critical while the phone says
    // advisory.
    expect(SmokeHaptics.forRole(StatusRole.critical), SmokeHaptic.critical);
    expect(SmokeHaptics.forRole(StatusRole.warning), SmokeHaptic.warning);
    expect(SmokeHaptics.forRole(StatusRole.info), SmokeHaptic.advisory);
  });

  test('transport health is silent — green is not an event', () {
    // A link coming back is not worth waking anyone for, and `pit` is an
    // accent rather than a state at all.
    expect(SmokeHaptics.forRole(StatusRole.positive), isNull);
    expect(SmokeHaptics.forRole(StatusRole.pit), isNull);
    expect(_capture(() => SmokeHaptics.fireForRole(StatusRole.positive)), isEmpty);
    expect(_capture(() => SmokeHaptics.fireForRole(StatusRole.pit)), isEmpty);
  });
}
