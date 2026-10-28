import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/services/notification_service.dart';
import 'package:luci_mobile/services/telephony_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/notifications_notifier.dart';
import 'package:luci_mobile/utils/logger.dart';

@immutable
class TelephonyState {
  final TelephonyStatus status;
  final TelephonyIdentity identity;
  final List<TelephonyCallRecord> history;
  final List<Map<String, dynamic>> smsList;
  final bool busy;
  final String? lastError;

  const TelephonyState({
    this.status = const TelephonyStatus(),
    this.identity = const TelephonyIdentity(),
    this.history = const [],
    this.smsList = const [],
    this.busy = false,
    this.lastError,
  });

  String get ownDisplayNumber {
    if (identity.ownNumber.isNotEmpty) return identity.ownNumber;
    if (status.ownNumber.isNotEmpty) return status.ownNumber;
    return '+601169777617';
  }

  TelephonyState copyWith({
    TelephonyStatus? status,
    TelephonyIdentity? identity,
    List<TelephonyCallRecord>? history,
    List<Map<String, dynamic>>? smsList,
    bool? busy,
    String? lastError,
  }) {
    return TelephonyState(
      status: status ?? this.status,
      identity: identity ?? this.identity,
      history: history ?? this.history,
      smsList: smsList ?? this.smsList,
      busy: busy ?? this.busy,
      lastError: lastError,
    );
  }
}

class TelephonyNotifier extends Notifier<TelephonyState> {
  Timer? _timer;
  String _previousCallState = 'idle';
  int _previousSmsCount = -1;
  int _pollTick = 0;

  TelephonyService? get _service => ref.read(telephonyServiceProvider);
  NotificationService get _notifications => ref.read(notificationServiceProvider);

  @override
  TelephonyState build() {
    // Watch telephonyServiceProvider so when router session connects or switches,
    // this notifier re-initializes and begins polling live state immediately!
    final service = ref.watch(telephonyServiceProvider);

    ref.onDispose(() {
      _timer?.cancel();
    });

    if (service != null) {
      _startPolling();
    } else {
      _timer?.cancel();
    }

    return const TelephonyState();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    // Immediately fetch initial state
    Future.microtask(() => refresh());
  }

  Future<void> refresh() async {
    final s = _service;
    if (s == null) return;
    try {
      final id = await s.getIdentity();
      final stat = await s.getStatus();
      final hist = await s.getHistory();
      final sms = await s.getSmsList();
      
      _checkTransitions(stat, sms);
      
      state = state.copyWith(
        identity: id,
        status: stat,
        history: hist,
        smsList: sms,
      );
    } catch (e) {
      Logger.debug('TelephonyNotifier refresh error: $e');
    }
  }

  Future<void> _poll() async {
    final s = _service;
    if (s == null) return;
    _pollTick++;

    try {
      final stat = await s.getStatus();
      
      // Every 5 ticks (~10s), check for new incoming SMS
      List<Map<String, dynamic>> currentSms = state.smsList;
      if (_pollTick % 5 == 0) {
        final count = await s.getSmsCount();
        if (count != -1 && (count != state.smsList.length || _previousSmsCount == -1)) {
          currentSms = await s.getSmsList();
        }
      }

      // Check transitions: incoming call ring & incoming SMS
      _checkTransitions(stat, currentSms);

      // If active call or call state changed, also update history
      if (stat.isRinging || stat.isTalking || stat.state != _previousCallState) {
        final hist = await s.getHistory();
        state = state.copyWith(status: stat, history: hist, smsList: currentSms);
      } else {
        state = state.copyWith(status: stat, smsList: currentSms);
      }
    } catch (e) {
      Logger.debug('TelephonyNotifier poll error: $e');
    }
  }

  void _checkTransitions(TelephonyStatus newStatus, List<Map<String, dynamic>> currentSms) {
    // 1. Incoming Call Notification
    if (newStatus.state == 'ringing' && _previousCallState != 'ringing') {
      final caller = newStatus.peer.isNotEmpty ? newStatus.peer : 'Incoming Call';
      _notifications.showIncomingCall(callerNumber: caller);
    } else if (newStatus.state != 'ringing' && _previousCallState == 'ringing') {
      _notifications.cancelIncomingCall();
    }
    _previousCallState = newStatus.state;

    // 2. Incoming SMS Notification
    if (_previousSmsCount != -1 && currentSms.length > _previousSmsCount) {
      final newest = currentSms.last;
      final sender = newest['sender']?.toString() ?? 'Unknown';
      final content = newest['content']?.toString() ?? 'New Message';
      _notifications.showNewSms(sender: sender, message: content);
    }
    _previousSmsCount = currentSms.length;
  }

  Future<bool> dial(String number) async {
    final s = _service;
    if (s == null) return false;
    state = state.copyWith(busy: true, lastError: null);
    try {
      final ok = await s.dial(number);
      if (ok) {
        state = state.copyWith(
          status: TelephonyStatus(
            state: 'dialing',
            peer: number,
            ownNumber: state.ownDisplayNumber,
            volte: state.status.volte,
          ),
          busy: false,
        );
      } else {
        state = state.copyWith(busy: false, lastError: 'Could not place call.');
      }
      return ok;
    } catch (e) {
      state = state.copyWith(busy: false, lastError: e.toString());
      return false;
    }
  }

  Future<bool> answer() async {
    final s = _service;
    if (s == null) return false;
    state = state.copyWith(busy: true, lastError: null);
    try {
      final ok = await s.answer();
      await _notifications.cancelIncomingCall();
      state = state.copyWith(busy: false);
      await refresh();
      return ok;
    } catch (e) {
      state = state.copyWith(busy: false, lastError: e.toString());
      return false;
    }
  }

  Future<bool> hangup() async {
    final s = _service;
    if (s == null) return false;
    state = state.copyWith(busy: true, lastError: null);
    try {
      final ok = await s.hangup();
      await _notifications.cancelIncomingCall();
      state = state.copyWith(
        status: TelephonyStatus(
          state: 'idle',
          peer: '',
          ownNumber: state.ownDisplayNumber,
          volte: state.status.volte,
        ),
        busy: false,
      );
      await refresh();
      return ok;
    } catch (e) {
      state = state.copyWith(busy: false, lastError: e.toString());
      return false;
    }
  }

  Future<SmsSendResult> sendSms(String to, String message) async {
    final s = _service;
    if (s == null) {
      return const SmsSendResult(isSuccess: false, error: 'Not connected to router.');
    }
    state = state.copyWith(busy: true, lastError: null);
    try {
      final res = await s.sendSms(to, message);
      if (res.isSuccess) {
        state = state.copyWith(busy: false, lastError: null);
        await refresh();
      } else {
        state = state.copyWith(busy: false, lastError: res.error);
      }
      return res;
    } catch (e) {
      final err = e.toString();
      state = state.copyWith(busy: false, lastError: err);
      return SmsSendResult(isSuccess: false, error: err);
    }
  }

  Future<bool> deleteSms(int index) async {
    final s = _service;
    if (s == null) return false;
    final ok = await s.deleteSms(index);
    if (ok) await refresh();
    return ok;
  }
}

final telephonyServiceProvider = Provider<TelephonyService?>((ref) {
  final session = ref.watch(sessionProvider);
  final api = ref.watch(apiServiceProvider);
  if (session == null || api == null) return null;
  return TelephonyService(api, session);
});

final telephonyProvider =
    NotifierProvider<TelephonyNotifier, TelephonyState>(
  TelephonyNotifier.new,
);
