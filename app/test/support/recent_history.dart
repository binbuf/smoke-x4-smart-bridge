import 'codecs.dart';

const int recordProbe1Attached = 1 << 0;
const int recordProbe2Attached = 1 << 1;
const int recordProbe4Attached = 1 << 3;
const int recordClockValid = 1 << 5;

/// The T36 fake sync: 30 readings ending just before [now], P3 detached and a
/// 3 m 20 s hole between readings 14 and 15.
List<SampleRec> buildThirtyRecentRecords(DateTime now) {
  final start = now.subtract(const Duration(minutes: 13));
  return <SampleRec>[
    for (var index = 0; index < 30; index++)
      SampleRec(
        seq: 100 + index,
        unixS: start
            .add(Duration(seconds: index * 20))
            .add(index >= 15 ? const Duration(minutes: 3) : Duration.zero)
            .millisecondsSinceEpoch ~/
            1000,
        temp: <int>[
          1600 + index,
          1500 + index,
          tempDetached,
          2200 + index * 2,
        ],
        flags:
            recordProbe1Attached |
            recordProbe2Attached |
            recordProbe4Attached |
            recordClockValid,
      ),
  ];
}
