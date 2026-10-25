import 'dart:convert';

import 'package:crypto/crypto.dart';

/// SHA-256 of the token stored in the RTWRT APP folder as app-token.txt.
/// The token itself stays out of this source.
const appTokenSha256 =
    'e1f66cb08d833818adc2b50f020d9d7b5180fef127d5b4fc7c9067289d7fa77e';

bool appTokenMatches(String token) {
  final digest = sha256.convert(utf8.encode(token.trim()));
  return digest.toString() == appTokenSha256;
}

/// Telegram username without @. Letters, digits, and underscore only.
String normalizeTelegramUser(String raw) {
  var text = raw.trim();
  if (text.startsWith('@')) text = text.substring(1);
  final kept = text.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
  if (kept.length <= 32) return kept;
  return kept.substring(0, 32);
}
