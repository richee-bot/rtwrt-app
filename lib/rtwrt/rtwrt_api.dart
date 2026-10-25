import 'dart:convert';
import 'dart:typed_data';

import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/state/router_session.dart';

/// Shell and UCI helpers for the connected router.
class RtwrtApi {
  const RtwrtApi(this.api, this.session);

  final IApiService api;
  final RouterSession session;

  Future<String> shell(String script) async {
    final result = await api.call(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      object: 'file',
      method: 'exec',
      params: {
        'command': '/bin/sh',
        'params': ['-c', script],
      },
    );
    return _text(result);
  }

  /// Turns the router's permission refusal into one plain sentence.
  static String explain(Object error) {
    final text = error.toString();
    if (text.contains('does not have permission') ||
        text.contains('access denied') ||
        text.contains('Access denied')) {
      return 'The router blocked this command. Log out of the app, then sign in again as root.';
    }
    return text;
  }

  Future<Map<String, Map<String, dynamic>>> uciAll(String config) async {
    final result = await api.call(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      object: 'uci',
      method: 'get',
      params: {'config': config},
    );
    final data = _map(result);
    final values = data['values'];
    final out = <String, Map<String, dynamic>>{};
    if (values is Map) {
      for (final entry in values.entries) {
        final value = entry.value;
        out[entry.key.toString()] = value is Map
            ? Map<String, dynamic>.from(value)
            : <String, dynamic>{};
      }
    }
    return out;
  }

  Future<List<String>> configs() async {
    final result = await api.call(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      object: 'uci',
      method: 'configs',
    );
    final data = _map(result);
    final raw = data['configs'] ?? data['result'];
    if (raw is List) return raw.map((e) => e.toString()).toList()..sort();
    if (result is List && result.length > 1 && result[1] is List) {
      return (result[1] as List).map((e) => e.toString()).toList()..sort();
    }
    return const [];
  }

  Future<void> uciSet(
    String config,
    String section,
    Map<String, Object> values,
  ) async {
    await api.uciSet(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      config: config,
      section: section,
      values: values,
    );
    await api.uciCommit(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      config: config,
    );
  }

  Future<Uint8List> readBase64File(String path) async {
    final text = await shell('base64 "$path"');
    final clean = text.replaceAll(RegExp(r'\s+'), '');
    return Uint8List.fromList(base64Decode(clean));
  }

  Future<void> writeBase64File(String path, Uint8List bytes) async {
    final encoded = base64Encode(bytes);
    await api.call(
      session.ipAddress,
      session.sysauth,
      session.useHttps,
      object: 'file',
      method: 'write',
      params: {'path': path, 'data': encoded, 'base64': true},
    );
  }

  static String _text(dynamic result) {
    final data = _map(result);
    final out = (data['stdout'] ?? '').toString();
    final err = (data['stderr'] ?? '').toString();
    if (out.trim().isNotEmpty) return out;
    return err;
  }

  static Map<String, dynamic> _map(dynamic result) {
    if (result is List && result.length > 1 && result[1] is Map) {
      return Map<String, dynamic>.from(result[1] as Map);
    }
    if (result is Map) return Map<String, dynamic>.from(result);
    return const {};
  }
}

/// Best-effort read of a Quectel `AT+QENG="servingcell"` reply.
class ServingCell {
  const ServingCell({
    required this.raw,
    this.rat,
    this.band,
    this.pci,
    this.arfcn,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.rssi,
  });

  final String raw;
  final String? rat;
  final String? band;
  final String? pci;
  final String? arfcn;
  final String? rsrp;
  final String? rsrq;
  final String? sinr;
  final String? rssi;

  static ServingCell parse(String raw) {
    final line = raw
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.contains('+QENG:'), orElse: () => raw.trim());
    final parts = line.split(',').map((p) => p.trim()).toList();
    String at(int i) =>
        i >= 0 && i < parts.length ? parts[i].replaceAll('"', '') : '';
    final rat = at(2);
    if (rat.contains('NR5G')) {
      return ServingCell(
        raw: raw.trim(),
        rat: rat,
        pci: at(7),
        arfcn: at(9),
        band: at(10),
        rsrp: at(12),
        rsrq: at(13),
        sinr: at(14),
      );
    }
    if (rat == 'LTE') {
      return ServingCell(
        raw: raw.trim(),
        rat: rat,
        pci: at(7),
        arfcn: at(8),
        band: at(9),
        rsrp: at(13),
        rsrq: at(14),
        rssi: at(15),
        sinr: at(16),
      );
    }
    return ServingCell(raw: raw.trim(), rat: rat.isEmpty ? null : rat);
  }
}
