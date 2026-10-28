import 'dart:convert';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/utils/logger.dart';

class TelephonyStatus {
  final String state; // idle, ringing, dialing, talking
  final String peer;
  final String ownNumber;
  final bool offhook;
  final int duration;
  final bool volte;
  final int signalCsq;

  const TelephonyStatus({
    this.state = 'idle',
    this.peer = '',
    this.ownNumber = '',
    this.offhook = false,
    this.duration = 0,
    this.volte = false,
    this.signalCsq = 0,
  });

  bool get isRinging => state == 'ringing';
  bool get isTalking => state == 'talking';
  bool get isDialing => state == 'dialing';
  bool get isIdle => state == 'idle';

  factory TelephonyStatus.fromJson(Map<String, dynamic> json) {
    return TelephonyStatus(
      state: json['state']?.toString() ?? 'idle',
      peer: json['peer']?.toString() ?? '',
      ownNumber: json['own_number']?.toString() ?? '',
      offhook: json['offhook'] == true,
      duration: json['duration'] is int ? json['duration'] as int : 0,
      volte: json['volte'] == true,
      signalCsq: json['signal_csq'] is int ? json['signal_csq'] as int : 0,
    );
  }
}

class TelephonyIdentity {
  final String ownNumber;
  final String imei;
  final String operator;

  const TelephonyIdentity({
    this.ownNumber = '',
    this.imei = '',
    this.operator = '',
  });

  factory TelephonyIdentity.fromJson(Map<String, dynamic> json) {
    return TelephonyIdentity(
      ownNumber: json['own_number']?.toString() ?? '',
      imei: json['imei']?.toString() ?? '',
      operator: json['operator']?.toString() ?? '',
    );
  }
}

class TelephonyCallRecord {
  final int time;
  final String event; // in, out, missed, blocked, failed
  final String number;

  const TelephonyCallRecord({
    required this.time,
    required this.event,
    required this.number,
  });

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(time * 1000);
}

class SmsSendResult {
  final bool isSuccess;
  final String? message;
  final String? error;

  const SmsSendResult({
    required this.isSuccess,
    this.message,
    this.error,
  });
}

class TelephonyService {
  final IApiService api;
  final RouterSession session;

  const TelephonyService(this.api, this.session);

  Future<TelephonyStatus> getStatus() async {
    try {
      final res = await api.call(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        object: 'rtwrt_telephony',
        method: 'status',
        params: {},
      );
      if (res is Map<String, dynamic>) {
        return TelephonyStatus.fromJson(res);
      }
      if (res is Map) {
        return TelephonyStatus.fromJson(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      Logger.debug('telephony.status call: $e');
    }
    return const TelephonyStatus();
  }

  Future<TelephonyIdentity> getIdentity() async {
    try {
      final res = await api.call(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        object: 'rtwrt_telephony',
        method: 'identity',
        params: {},
      );
      if (res is Map<String, dynamic>) {
        return TelephonyIdentity.fromJson(res);
      }
      if (res is Map) {
        return TelephonyIdentity.fromJson(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      Logger.debug('telephony.identity call: $e');
    }
    return const TelephonyIdentity();
  }

  Future<bool> dial(String number) async {
    try {
      final res = await api.call(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        object: 'rtwrt_telephony',
        method: 'dial',
        params: {'number': number.trim()},
      );
      if (res is Map && res['ok'] == true) return true;
    } catch (e, stack) {
      Logger.exception('Telephony dial failed', e, stack);
    }
    return false;
  }

  Future<bool> answer() async {
    try {
      final res = await api.call(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        object: 'rtwrt_telephony',
        method: 'answer',
        params: {},
      );
      if (res is Map && res['ok'] == true) return true;
    } catch (e, stack) {
      Logger.exception('Telephony answer failed', e, stack);
    }
    return false;
  }

  Future<bool> hangup() async {
    try {
      final res = await api.call(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        object: 'rtwrt_telephony',
        method: 'hangup',
        params: {},
      );
      if (res is Map && res['ok'] == true) return true;
    } catch (e, stack) {
      Logger.exception('Telephony hangup failed', e, stack);
    }
    return false;
  }

  Future<List<TelephonyCallRecord>> getHistory() async {
    try {
      final res = await api.call(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        object: 'fxs',
        method: 'calls',
        params: {},
      );
      if (res is Map && res['calls'] is List) {
        final list = <TelephonyCallRecord>[];
        for (final item in (res['calls'] as List)) {
          if (item is Map) {
            list.add(
              TelephonyCallRecord(
                time: item['time'] is int ? item['time'] as int : 0,
                event: item['event']?.toString() ?? '',
                number: item['number']?.toString() ?? '',
              ),
            );
          }
        }
        return list.reversed.toList();
      }
    } catch (e) {
      Logger.debug('Telephony getHistory: $e');
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> getSmsList() async {
    try {
      final raw = await _shell('/usr/bin/rtwrt-sms recv 2>&1');
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start != -1 && end > start) {
        final decoded = jsonDecode(raw.substring(start, end + 1));
        if (decoded is Map && decoded['msg'] is List) {
          return List<Map<String, dynamic>>.from(
            (decoded['msg'] as List).whereType<Map>(),
          );
        }
      }
    } catch (e) {
      Logger.debug('Telephony getSmsList: $e');
    }
    return const [];
  }

  Future<int> getSmsCount() async {
    try {
      final raw = await _shell('/usr/bin/rtwrt-sms status 2>&1');
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start != -1 && end > start) {
        final decoded = jsonDecode(raw.substring(start, end + 1));
        if (decoded is Map && decoded['used'] is int) {
          return decoded['used'] as int;
        }
      }
    } catch (e) {
      Logger.debug('Telephony getSmsCount: $e');
    }
    return -1;
  }

  Future<SmsSendResult> sendSms(String to, String message) async {
    try {
      final cleanTo = to.replaceAll("'", "").trim();
      final cleanMsg = message.replaceAll("'", "'\\''");
      final raw = await _shell("/usr/bin/rtwrt-sms send '$cleanTo' '$cleanMsg' 2>&1");
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start != -1 && end > start) {
        final decoded = jsonDecode(raw.substring(start, end + 1));
        if (decoded is Map) {
          if (decoded['status'] == 'success') {
            return SmsSendResult(
              isSuccess: true,
              message: decoded['message']?.toString() ?? 'SMS sent successfully',
            );
          } else {
            return SmsSendResult(
              isSuccess: false,
              error: decoded['detail']?.toString() ?? 'SMS failed to send',
            );
          }
        }
      }
      return SmsSendResult(isSuccess: false, error: raw.trim());
    } catch (e, stack) {
      Logger.exception('Telephony sendSms failed', e, stack);
      return SmsSendResult(isSuccess: false, error: e.toString());
    }
  }

  Future<bool> deleteSms(int index) async {
    try {
      await _shell('/usr/bin/rtwrt-sms delete $index 2>&1');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _shell(String script) async {
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
    if (result is Map && result['stdout'] != null) {
      return result['stdout'].toString();
    }
    return result.toString();
  }
}
