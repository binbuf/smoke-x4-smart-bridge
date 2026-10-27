import 'package:flutter_test/flutter_test.dart';

import '../../protocol/gen/records.dart';

void main() {
  test('generated codec import works', () {
    expect(Info(protoMajor: 1, protoMinor: 0, deviceId: 'A4F2').encode().length, 32);
    expect(bleCharacteristics.length, 8);
  });
}
