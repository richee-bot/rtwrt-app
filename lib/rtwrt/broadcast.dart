import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/rtwrt/github_release.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One owner notice from broadcast.json.
class BroadcastMsg {
  const BroadcastMsg({
    required this.id,
    required this.title,
    required this.body,
  });

  final int id;
  final String title;
  final String body;

  String get fingerprint {
    final digest = sha256.convert(
      utf8.encode('$id|${title.trim()}|${body.trim()}'),
    );
    return digest.toString().substring(0, 16);
  }
}

/// Active notice, or null when the file is off, empty, or not a notice.
BroadcastMsg? broadcastFrom(Map<dynamic, dynamic> json) {
  if (json['active'] == false) return null;
  final rawId = json['id'];
  final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
  if (id <= 0) return null;
  final titleText = json['title']?.toString().trim() ?? '';
  var body = json['body']?.toString().trim() ?? '';
  if (body.isEmpty) body = json['message']?.toString().trim() ?? '';
  if (body.isEmpty) return null;
  return BroadcastMsg(
    id: id,
    title: titleText.isEmpty ? 'RTWRT notice' : titleText,
    body: body,
  );
}

/// Hide a notice only after this exact title and body were dismissed.
bool broadcastVisible({
  required BroadcastMsg msg,
  required String? dismissedFingerprint,
  required int dismissedId,
}) {
  final saved = dismissedFingerprint?.trim() ?? '';
  if (saved.isNotEmpty && saved == msg.fingerprint) return false;
  if (saved.isEmpty && dismissedId > 0 && msg.id <= dismissedId) return false;
  return true;
}

/// Loads the owner notice published on the firmware GitHub repo.
class BroadcastNotice {
  static const _fpKey = 'rtwrt-broadcast-fp';
  static const _idKey = 'rtwrt-broadcast-id';
  static final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'User-Agent': 'RTWRT',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  static Future<BroadcastMsg?> fetch() async {
    final url =
        '${AppConfig.broadcastUrl}?t=${DateTime.now().millisecondsSinceEpoch}';
    if (!isRicheeGithubUrl(url)) return null;
    try {
      final response = await _dio.get<dynamic>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = response.data;
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is Map) return broadcastFrom(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<bool> shouldShow(BroadcastMsg msg) async {
    final prefs = await SharedPreferences.getInstance();
    return broadcastVisible(
      msg: msg,
      dismissedFingerprint: prefs.getString(_fpKey),
      dismissedId: prefs.getInt(_idKey) ?? 0,
    );
  }

  static Future<void> dismiss(BroadcastMsg msg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fpKey, msg.fingerprint);
    await prefs.setInt(_idKey, msg.id);
  }
}
