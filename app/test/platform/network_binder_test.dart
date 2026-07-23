/// A14.1: the binder contract — lifecycle, misuse, and the lost-network
/// path — against both the fake and the channel implementation (the
/// channel side backed by a mock MethodChannel answering the same
/// vectors A14.2's Kotlin must).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/platform/network_binder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FakeNetworkBinder (the contract double)', () {
    test('bind → unbind lifecycle with state stream', () async {
      final b = FakeNetworkBinder();
      final states = <BinderState>[];
      final sub = b.states.listen(states.add);

      expect(b.state, BinderState.unbound);
      await b.bind();
      expect(b.state, BinderState.bound);
      await b.unbind();
      expect(b.state, BinderState.unbound);
      await Future<void>.delayed(Duration.zero);
      expect(states, [BinderState.bound, BinderState.unbound]);
      await sub.cancel();
      await b.dispose();
    });

    test('misuse is defined behaviour, not platform luck', () async {
      final b = FakeNetworkBinder();
      await b.bind();
      // Double bind throws...
      await expectLater(b.bind(), throwsA(isA<BinderStateError>()));
      // ...and did not disturb the existing binding.
      expect(b.state, BinderState.bound);
      await b.unbind();
      // Unbind without bind throws.
      await expectLater(b.unbind(), throwsA(isA<BinderStateError>()));
      await b.dispose();
    });

    test('the lost-network path releases implicitly', () async {
      final b = FakeNetworkBinder();
      await b.bind();
      b.simulateLost();
      expect(b.state, BinderState.lost);
      // After lost, a fresh bind is legal (the binding is already gone).
      await b.bind();
      expect(b.state, BinderState.bound);
      await b.dispose();
    });

    test('joinAp implies the bind; dispose releases', () async {
      final b = FakeNetworkBinder();
      await b.joinAp('SmokeBridge-A4F2', 'Gk7mR2xQpT');
      expect(b.state, BinderState.bound);
      expect(b.calls, ['joinAp:SmokeBridge-A4F2']);
      await b.dispose();
      expect(b.calls.last, 'unbind'); // dispose is a guaranteed release
    });
  });

  group('ChannelNetworkBinder (the production state machine)', () {
    const channel = MethodChannel('smokebridge/network_binder');
    final log = <String>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            log.add(call.method);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    /// Delivers a platform→Dart callback the way Kotlin does.
    Future<void> platformCalls(String method) async {
      final data = const StandardMethodCodec().encodeMethodCall(
        MethodCall(method),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('smokebridge/network_binder', data, (_) {});
    }

    test('bind waits in binding until onBound arrives', () async {
      final b = ChannelNetworkBinder(channel: channel);
      await b.bind();
      expect(b.state, BinderState.binding); // filed, not yet available
      await platformCalls('onBound');
      expect(b.state, BinderState.bound);
      expect(log, ['bind']);
      await b.unbind();
      expect(b.state, BinderState.unbound);
      expect(log, ['bind', 'unbind']);
      await b.dispose();
    });

    test('onLost reflects the platform release; misuse still throws', () async {
      final b = ChannelNetworkBinder(channel: channel);
      await b.bind();
      await platformCalls('onBound');
      await platformCalls('onLost');
      expect(b.state, BinderState.lost);
      // The platform already released; binding again is legal.
      await b.bind();
      await expectLater(b.bind(), throwsA(isA<BinderStateError>()));
      await b.dispose();
      // Dispose released the in-flight binding.
      expect(log.last, 'unbind');
    });

    test('a platform failure resets to unbound and rethrows', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'unavailable');
          });
      final b = ChannelNetworkBinder(channel: channel);
      await expectLater(b.bind(), throwsA(isA<PlatformException>()));
      expect(b.state, BinderState.unbound);
      await b.dispose();
    });

    test('joinAp carries the credentials', () async {
      final args = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            args.add(call.arguments);
            return null;
          });
      final b = ChannelNetworkBinder(channel: channel);
      await b.joinAp('SmokeBridge-A4F2', 'Gk7mR2xQpT');
      expect(args.single, {'ssid': 'SmokeBridge-A4F2', 'psk': 'Gk7mR2xQpT'});
      await b.dispose();
    });
  });
}
