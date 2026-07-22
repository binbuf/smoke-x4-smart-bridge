/// Minimal mDNS responder (T3.6): advertises `_smokebridge._tcp` (and
/// `_http._tcp`) with the 05 §5.5 TXT records so app discovery — the `nsd`
/// path, a known Android trap — is exercisable against the sim from day one.
///
/// Hand-rolled because pub's mDNS packages resolve but do not advertise.
/// Uncompressed names only; answers PTR/SRV/TXT/A queries and sends an
/// unsolicited announcement on start.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class MdnsAdvertiser {
  MdnsAdvertiser({
    required this.instance,
    required this.port,
    required this.txt,
    this.hostname = 'smokebridge.local',
  });

  final String instance; // e.g. SmokeBridge-A4F2
  final int port;
  final Map<String, String> txt;
  final String hostname;

  static final InternetAddress _group = InternetAddress('224.0.0.251');
  static const int _mdnsPort = 5353;

  RawDatagramSocket? _socket;
  InternetAddress? _localAddress;

  static const services = ['_smokebridge._tcp.local', '_http._tcp.local'];

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _mdnsPort,
      reuseAddress: true,
      reusePort: !Platform.isWindows,
    );
    socket.joinMulticast(_group);
    socket.multicastLoopback = true;
    _socket = socket;
    _localAddress = await _pickLocalAddress();

    socket.listen((event) {
      if (event != RawSocketEvent.read) {
        return;
      }
      final dg = socket.receive();
      if (dg == null) {
        return;
      }
      _handleQuery(dg.data);
    });

    // Unsolicited announcement.
    _announce();
    Timer(const Duration(seconds: 1), _announce);
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }

  Future<InternetAddress> _pickLocalAddress() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (!a.isLoopback) {
            return a;
          }
        }
      }
    } on SocketException {
      // fall through
    }
    return InternetAddress.loopbackIPv4;
  }

  void _handleQuery(Uint8List data) {
    if (data.length < 12) {
      return;
    }
    final flags = (data[2] << 8) | data[3];
    if (flags & 0x8000 != 0) {
      return; // a response, not a query
    }
    final qdCount = (data[4] << 8) | data[5];
    var off = 12;
    var interested = false;
    for (var q = 0; q < qdCount; q++) {
      final (name, next) = _readName(data, off);
      if (next + 4 > data.length) {
        return;
      }
      off = next + 4;
      final lower = name.toLowerCase();
      if (services.contains(lower) ||
          lower == '_services._dns-sd._udp.local' ||
          lower == hostname ||
          lower == '$instance._smokebridge._tcp.local'.toLowerCase()) {
        interested = true;
      }
    }
    if (interested) {
      _announce();
    }
  }

  /// Reads a DNS name at [off]; returns (dotted name, offset after it).
  /// Follows one level of compression pointers, defensively.
  (String, int) _readName(Uint8List data, int off) {
    final labels = <String>[];
    var i = off;
    var end = -1;
    var hops = 0;
    while (i < data.length) {
      final len = data[i];
      if (len == 0) {
        if (end < 0) {
          end = i + 1;
        }
        break;
      }
      if (len & 0xC0 == 0xC0) {
        if (i + 1 >= data.length || ++hops > 4) {
          break;
        }
        if (end < 0) {
          end = i + 2;
        }
        i = ((len & 0x3F) << 8) | data[i + 1];
        continue;
      }
      if (i + 1 + len > data.length) {
        break;
      }
      labels.add(String.fromCharCodes(data, i + 1, i + 1 + len));
      i += 1 + len;
    }
    return (labels.join('.'), end < 0 ? data.length : end);
  }

  void _announce() {
    final socket = _socket;
    final addr = _localAddress;
    if (socket == null || addr == null) {
      return;
    }
    socket.send(_buildResponse(addr), _group, _mdnsPort);
  }

  Uint8List _buildResponse(InternetAddress addr) {
    final b = BytesBuilder();
    // Header: response, authoritative.
    final answers = <Uint8List>[];
    for (final service in services) {
      final instanceName = '$instance.$service';
      answers
        ..add(_record(service, 12, _nameBytes(instanceName))) // PTR
        ..add(
          _record(
            instanceName,
            33, // SRV
            Uint8List.fromList([
              0,
              0,
              0,
              0,
              (port >> 8) & 0xFF,
              port & 0xFF,
              ..._nameBytes(hostname),
            ]),
          ),
        )
        ..add(_record(instanceName, 16, _txtBytes())); // TXT
      answers.add(
        _record('_services._dns-sd._udp.local', 12, _nameBytes(service)),
      );
    }
    answers.add(_record(hostname, 1, Uint8List.fromList(addr.rawAddress)));

    b.add([0, 0, 0x84, 0x00, 0, 0, 0, answers.length, 0, 0, 0, 0]);
    for (final a in answers) {
      b.add(a);
    }
    return b.toBytes();
  }

  Uint8List _record(String name, int type, Uint8List rdata) {
    final b = BytesBuilder()
      ..add(_nameBytes(name))
      ..add([
        (type >> 8) & 0xFF, type & 0xFF,
        0x80, 0x01, // cache-flush + IN
        0, 0, 0, 120, // TTL 120 s
        (rdata.length >> 8) & 0xFF, rdata.length & 0xFF,
      ])
      ..add(rdata);
    return b.toBytes();
  }

  Uint8List _nameBytes(String name) {
    final b = BytesBuilder();
    for (final label in name.split('.')) {
      if (label.isEmpty) {
        continue;
      }
      final bytes = label.codeUnits;
      b.addByte(bytes.length);
      b.add(bytes);
    }
    b.addByte(0);
    return b.toBytes();
  }

  Uint8List _txtBytes() {
    final b = BytesBuilder();
    txt.forEach((k, v) {
      final entry = '$k=$v'.codeUnits;
      b.addByte(entry.length);
      b.add(entry);
    });
    return b.toBytes();
  }
}
