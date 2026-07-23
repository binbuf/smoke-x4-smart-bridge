/// T4.1b: one invocation against the sim produces a .loralog the corpus
/// tooling accepts without hand-editing, and re-running is idempotent.
import 'dart:io';

import 'package:cookgen/cookgen.dart';
import 'package:lora/lora.dart';
import 'package:sim/sim.dart';
import 'package:test/test.dart';

void main() {
  late SimServer server;
  late Directory tmp;

  setUp(() async {
    var dir = Directory.current;
    while (!File('${dir.path}/protocol/records.yaml').existsSync()) {
      dir = dir.parent;
    }
    final smk = SmkFile.read('${dir.path}/protocol/fixtures/brisket-18h.smk');
    final cook = GeneratedCook(
      header: smk.header,
      samples: smk.samples,
      marks: smk.marks,
    );
    final endT = cook.samples.last.t;
    final state = SimState(
      cook: cook,
      nowMs: () => DateTime.now().millisecondsSinceEpoch + (endT + 10) * 1000,
    );
    server = SimServer(state);
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    tmp = Directory.systemTemp.createTempSync('pull_test');
  });

  tearDown(() async {
    await server.stop();
    tmp.deleteSync(recursive: true);
  });

  test(
    'pull stages a loralog the corpus tooling accepts; idempotent',
    () async {
      final r1 = await pull(
        host: '127.0.0.1',
        port: server.port,
        outDir: tmp.path,
        name: 'sim-pull',
        stamp: 'test',
      );
      expect(r1.packetCount, greaterThan(0));
      expect(File(r1.loralogPath).existsSync(), isTrue);
      expect(File(r1.noveltyPath!).existsSync(), isTrue);

      // The staged file round-trips through the corpus reader.
      final packets = readLoralog(File(r1.loralogPath).readAsStringSync());
      expect(packets.length, r1.packetCount);
      expect(packets.every((p) => p.messageClass == 'state26'), isTrue);

      // Re-running with the same stamp overwrites, never accumulates.
      final before = tmp.listSync(recursive: true).whereType<File>().length;
      final r2 = await pull(
        host: '127.0.0.1',
        port: server.port,
        outDir: tmp.path,
        name: 'sim-pull',
        stamp: 'test',
      );
      final after = tmp.listSync(recursive: true).whereType<File>().length;
      expect(after, before);
      expect(r2.packetCount, r1.packetCount);
    },
  );
}
