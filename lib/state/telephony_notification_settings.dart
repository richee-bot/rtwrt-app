import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class TelephonyNotificationSettings {
  final bool calls;
  final bool sms;

  const TelephonyNotificationSettings({
    this.calls = true,
    this.sms = true,
  });

  TelephonyNotificationSettings copyWith({bool? calls, bool? sms}) {
    return TelephonyNotificationSettings(
      calls: calls ?? this.calls,
      sms: sms ?? this.sms,
    );
  }
}

class TelephonyNotificationSettingsNotifier
    extends Notifier<TelephonyNotificationSettings> {
  static const _keyCalls = 'rtwrt_notify_calls';
  static const _keySms = 'rtwrt_notify_sms';

  @override
  TelephonyNotificationSettings build() {
    _load();
    return const TelephonyNotificationSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = TelephonyNotificationSettings(
      calls: prefs.getBool(_keyCalls) ?? true,
      sms: prefs.getBool(_keySms) ?? true,
    );
  }

  Future<void> setCalls(bool enabled) async {
    state = state.copyWith(calls: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCalls, enabled);
  }

  Future<void> setSms(bool enabled) async {
    state = state.copyWith(sms: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySms, enabled);
  }
}

final telephonyNotificationSettingsProvider = NotifierProvider<
    TelephonyNotificationSettingsNotifier, TelephonyNotificationSettings>(
  TelephonyNotificationSettingsNotifier.new,
);
