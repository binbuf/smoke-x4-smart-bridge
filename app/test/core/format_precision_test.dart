import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/core/format.dart';

void main() {
  test('one decimal, matching the Smoke X display', () {
    expect(formatTemp(818), '81.8°');       // the exact case reported
    expect(formatTemp(2431), '243.1°');
    expect(formatTemp(820), '82.0°');       // a true .0 still shows it
    expect(formatTemp(null), '—');          // detached is never a number
    expect(formatTemp(818, celsius: true), '27.7°');
  });
  test('setpoints stay clean unless a tenth was set', () {
    expect(formatSetpoint(2030), '203°');
    expect(formatSetpoint(2035), '203.5°');
    expect(formatSetpoint(null), '—');
  });
}
