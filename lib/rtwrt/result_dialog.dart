import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows what just happened, and keeps the failure text for the next fix.
Future<void> showRtwrtResult(
  BuildContext context, {
  required String action,
  required bool ok,
  String detail = '',
}) async {
  final message = detail.trim().isEmpty
      ? (ok ? 'Done.' : 'The router did not say why.')
      : detail.trim();
  if (!ok) await RtwrtErrorLog.record(action, message);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(ok ? 'Success' : 'Not successful'),
      content: SingleChildScrollView(
        child: Text(ok ? message : '$action\n\n$message'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class RtwrtErrorLog {
  static const _key = 'rtwrt-error-log-v1';

  static Future<void> record(String action, String detail) async {
    final prefs = await SharedPreferences.getInstance();
    final lines = prefs.getStringList(_key) ?? <String>[];
    final stamp = DateTime.now().toIso8601String();
    lines.insert(0, '$stamp\n$action\n$detail');
    if (lines.length > 40) lines.removeRange(40, lines.length);
    await prefs.setStringList(_key, lines);
  }

  static Future<List<String>> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
