import 'dart:io';

import 'package:yaml/yaml.dart';

/// Scalar wire types. `char` is a byte interpreted as UTF-8 text by readers.
enum WireType {
  u8(1, false),
  i8(1, true),
  u16(2, false),
  i16(2, true),
  u32(4, false),
  i32(4, true),
  u64(8, false),
  i64(8, true),
  char(1, false);

  const WireType(this.size, this.signed);
  final int size;
  final bool signed;

  static WireType parse(String s) => WireType.values.firstWhere(
    (t) => t.name == s,
    orElse: () => throw SpecException('unknown type "$s"'),
  );
}

class SpecException implements Exception {
  SpecException(this.message);
  final String message;
  @override
  String toString() => 'records.yaml: $message';
}

/// One contiguous byte range `[start, end]` (inclusive) of a CRC coverage spec.
class CrcRange {
  CrcRange(this.start, this.end);
  final int start;
  final int end;
}

class CrcSpec {
  CrcSpec(this.kind, this.ranges);
  final String kind; // crc16 | crc32
  final List<CrcRange> ranges;

  static CrcSpec parse(Map<dynamic, dynamic> m) {
    final kind = m['kind'] as String;
    if (kind != 'crc16' && kind != 'crc32') {
      throw SpecException('crc kind must be crc16|crc32, got $kind');
    }
    final ranges = <CrcRange>[];
    for (final part in (m['over'] as String).split(',')) {
      final ends = part.trim().split('..');
      if (ends.length != 2) throw SpecException('bad crc range "$part"');
      ranges.add(CrcRange(int.parse(ends[0]), int.parse(ends[1])));
    }
    return CrcSpec(kind, ranges);
  }
}

class FieldSpec {
  FieldSpec({
    required this.name,
    required this.type,
    this.count = 1,
    this.rows = 1,
    this.constValue,
    this.bits,
    this.sentinel,
    this.crc,
    this.varLenField,
    this.varLenImplicit = false,
    this.max,
    this.reserved = false,
    this.enumName,
    this.doc,
  });

  final String name;
  final WireType type;
  final int count; // elements per row (fixed) or max elements (variable)
  final int rows; // only >1 for char matrices (probe_name[4][12])
  final Object? constValue; // int, or String for char magic
  final List<String>? bits; // bit names, LSB first, exactly 8 for a u8
  final Map<int, String>? sentinel;
  final CrcSpec? crc;
  final String? varLenField; // name of the u8 field holding the element count
  final bool varLenImplicit; // length = remainder of the buffer
  final int? max; // max elements when variable
  final bool reserved;
  final String? enumName;
  final String? doc;

  bool get isVariable => varLenField != null || varLenImplicit;

  /// Wire size in bytes; for variable fields, the maximum.
  int get maxByteSize => type.size * (isVariable ? (max ?? 0) : count) * rows;

  /// Offset is only meaningful for fields before the first variable field.
  int? offset;
}

class RecordSpec {
  RecordSpec({
    required this.name,
    required this.fields,
    this.declaredSize,
    this.declaredMaxSize,
    this.isControlBody = false,
  });

  final String name;
  final List<FieldSpec> fields;
  final int? declaredSize; // fixed records
  final int? declaredMaxSize; // variable payloads
  final bool isControlBody;

  bool get isFixed => declaredSize != null;
  bool get hasVariableFields => fields.any((f) => f.isVariable);
}

class ProtocolSpec {
  ProtocolSpec({
    required this.constants,
    required this.enums,
    required this.records,
    required this.crc16,
    required this.crc32,
  });

  final Map<String, Object> constants;
  final Map<String, Map<String, int>> enums;
  final List<RecordSpec> records;
  final Map<String, int> crc16;
  final Map<String, int> crc32;

  static ProtocolSpec load(String path) {
    final doc = loadYaml(File(path).readAsStringSync()) as YamlMap;

    final meta = doc['meta'] as YamlMap;
    if (meta['endianness'] != 'little') {
      throw SpecException('only little-endian is supported');
    }

    Map<String, int> crcParams(String key) {
      final m = meta[key] as YamlMap;
      return {
        'poly': m['poly'] as int,
        'init': m['init'] as int,
        'refin': (m['refin'] as bool) ? 1 : 0,
        'refout': (m['refout'] as bool) ? 1 : 0,
        'xorout': m['xorout'] as int,
      };
    }

    final constants = <String, Object>{};
    (doc['constants'] as YamlMap).forEach((k, v) {
      constants[k as String] = v as Object;
    });

    final enums = <String, Map<String, int>>{};
    (doc['enums'] as YamlMap).forEach((name, values) {
      enums[name as String] = {
        for (final e in (values as YamlMap).entries)
          e.key as String: e.value as int,
      };
    });

    final records = <RecordSpec>[];
    void addSection(String section, {bool control = false}) {
      final m = doc[section];
      if (m == null) return;
      (m as YamlMap).forEach((name, body) {
        records.add(
          _parseRecord(name as String, body as YamlMap, control: control),
        );
      });
    }

    addSection('records');
    addSection('ble_payloads');
    addSection('control_bodies', control: true);

    final spec = ProtocolSpec(
      constants: constants,
      enums: enums,
      records: records,
      crc16: crcParams('crc16'),
      crc32: crcParams('crc32'),
    );
    spec._validate();
    return spec;
  }

  static RecordSpec _parseRecord(
    String name,
    YamlMap body, {
    required bool control,
  }) {
    final fields = <FieldSpec>[];
    for (final raw in body['fields'] as YamlList) {
      final f = raw as YamlMap;
      final varLen = f['var_len'];
      Map<int, String>? sentinel;
      if (f['sentinel'] != null) {
        sentinel = {
          for (final e in (f['sentinel'] as YamlMap).entries)
            e.key as int: e.value as String,
        };
      }
      fields.add(
        FieldSpec(
          name: f['name'] as String,
          type: WireType.parse(f['type'] as String),
          count: (f['count'] as int?) ?? 1,
          rows: (f['rows'] as int?) ?? 1,
          constValue: f['const'],
          bits: (f['bits'] as YamlList?)?.cast<String>().toList(),
          sentinel: sentinel,
          crc: f['crc'] == null ? null : CrcSpec.parse(f['crc'] as YamlMap),
          varLenField: varLen is String && varLen != 'implicit' ? varLen : null,
          varLenImplicit: varLen == 'implicit',
          max: f['max'] as int?,
          reserved: (f['reserved'] as bool?) ?? false,
          enumName: f['enum'] as String?,
          doc: f['doc'] as String?,
        ),
      );
    }
    return RecordSpec(
      name: name,
      fields: fields,
      declaredSize: body['size'] as int?,
      declaredMaxSize: body['max_size'] as int?,
      isControlBody: control,
    );
  }

  void _validate() {
    final seen = <String>{};
    for (final r in records) {
      if (!seen.add(r.name)) throw SpecException('duplicate record ${r.name}');
      var offset = 0;
      var pastVariable = false;
      final fieldNames = <String>{};
      for (final f in r.fields) {
        if (!fieldNames.add(f.name)) {
          throw SpecException('${r.name}: duplicate field ${f.name}');
        }
        if (f.bits != null && (f.type != WireType.u8 || f.bits!.length != 8)) {
          throw SpecException(
            '${r.name}.${f.name}: bits requires u8 with exactly 8 names',
          );
        }
        if (f.isVariable) {
          if (f.max == null && !f.varLenImplicit) {
            throw SpecException('${r.name}.${f.name}: var field needs max');
          }
          if (f.varLenField != null &&
              !r.fields.any((o) => o.name == f.varLenField)) {
            throw SpecException(
              '${r.name}.${f.name}: unknown length field ${f.varLenField}',
            );
          }
          pastVariable = true;
        } else {
          if (!pastVariable) f.offset = offset;
          offset += f.type.size * f.count * f.rows;
        }
        if (f.enumName != null && !enums.containsKey(f.enumName)) {
          throw SpecException(
            '${r.name}.${f.name}: unknown enum ${f.enumName}',
          );
        }
      }
      if (r.declaredSize != null) {
        if (r.hasVariableFields) {
          throw SpecException('${r.name}: fixed record has variable fields');
        }
        if (offset != r.declaredSize) {
          throw SpecException(
            '${r.name}: declared size ${r.declaredSize} != field sum $offset',
          );
        }
      } else if (r.declaredMaxSize != null) {
        final maxSum = r.fields.fold<int>(0, (a, f) => a + f.maxByteSize);
        if (maxSum > r.declaredMaxSize!) {
          throw SpecException(
            '${r.name}: max field sum $maxSum exceeds declared max_size '
            '${r.declaredMaxSize}',
          );
        }
      } else if (!r.isControlBody) {
        throw SpecException('${r.name}: needs size or max_size');
      }
      // CRC ranges must be inside the record.
      final limit = r.declaredSize ?? r.declaredMaxSize ?? 0;
      for (final f in r.fields.where((f) => f.crc != null)) {
        for (final range in f.crc!.ranges) {
          if (range.start < 0 || (limit != 0 && range.end >= limit)) {
            throw SpecException('${r.name}.${f.name}: crc range out of bounds');
          }
        }
      }
    }
  }

  RecordSpec record(String name) => records.firstWhere((r) => r.name == name);
}
