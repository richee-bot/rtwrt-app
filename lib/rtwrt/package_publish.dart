import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:luci_mobile/config/app_config.dart';

/// Result of adding one package file to the firmware GitHub repo.
class PackagePublishResult {
  const PackagePublishResult(this.ok, this.message);

  final bool ok;
  final String message;
}

/// Package name from an OpenWrt `name_version_arch.ipk` file.
String? packageNameFromFile(String fileName) {
  final leaf = fileName.split(RegExp(r'[\\/]')).last;
  final lower = leaf.toLowerCase();
  if (!lower.endsWith('.ipk') && !lower.endsWith('.apk')) return null;
  var base = leaf.substring(0, leaf.length - 4);
  for (final arch in const [
    '_aarch64_cortex-a53',
    '_aarch64_generic',
    '_all',
  ]) {
    if (base.endsWith(arch)) {
      base = base.substring(0, base.length - arch.length);
      break;
    }
  }
  final split = base.lastIndexOf('_');
  final name = split > 0 ? base.substring(0, split) : base;
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,80}$').hasMatch(name)) {
    return null;
  }
  return name;
}

/// Safe asset name for a GitHub release URL.
String safePackageFileName(String fileName) {
  final leaf = fileName.split(RegExp(r'[\\/]')).last;
  final cleaned = leaf.replaceAll(RegExp(r'[^A-Za-z0-9._+-]'), '_');
  return cleaned;
}

/// Install command for a file already stored on the router.
String packageInstallLine(
  String path, {
  required bool apk,
  required bool force,
}) {
  if (apk) {
    final flags = force
        ? '--allow-untrusted --force-overwrite'
        : '--allow-untrusted';
    return 'apk add $flags $path';
  }
  final flags = force
      ? '--force-depends --force-overwrite --force-downgrade --force-reinstall '
      : '';
  return 'if command -v opkg >/dev/null 2>&1; then opkg install $flags$path; else echo NO_OPKG; fi';
}

/// Install command for a package name from the router feed.
String namedPackageInstall(String quotedName, {required bool force}) {
  if (force) {
    return 'if command -v apk >/dev/null 2>&1; then apk add --force-overwrite $quotedName; '
        'else opkg update; opkg install --force-depends --force-overwrite --force-downgrade --force-reinstall $quotedName; fi';
  }
  return 'if command -v apk >/dev/null 2>&1; then apk add $quotedName; '
      'else opkg update; opkg install $quotedName; fi';
}

/// Publishes an uploaded package on richee-bot/rtwrt-aw1000-firmware.
class PackagePublisher {
  static const tokenKey = 'rtwrt-github-token';
  static const _storage = FlutterSecureStorage();
  static final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'User-Agent': 'RTWRT',
        'Accept': 'application/vnd.github+json',
      },
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 3),
    ),
  );

  static Future<String?> readToken() => _storage.read(key: tokenKey);

  static Future<void> saveToken(String token) {
    return _storage.write(key: tokenKey, value: token.trim());
  }

  static Future<PackagePublishResult> publish({
    required String token,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final safe = safePackageFileName(fileName);
    final name = packageNameFromFile(safe);
    if (name == null ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,180}\.(?:ipk|apk)$',
          caseSensitive: false,
        ).hasMatch(safe)) {
      return const PackagePublishResult(
        false,
        'The file name is not an OpenWrt package.',
      );
    }
    final apk = safe.toLowerCase().endsWith('.apk');
    final tag = apk ? 'apk-$name' : 'ipk-$name';
    final repo = AppConfig.firmwareRepo;
    final headers = {'Authorization': 'Bearer $token'};
    try {
      final release = await _release(repo, tag, name, apk, headers);
      final id = release['id'];
      final assets = release['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is Map && asset['name'] == safe) {
            await _dio.delete<dynamic>(
              'https://api.github.com/repos/$repo/releases/assets/${asset['id']}',
              options: Options(headers: headers),
            );
          }
        }
      }
      await _dio.post<dynamic>(
        'https://uploads.github.com/repos/$repo/releases/$id/assets',
        queryParameters: {'name': safe},
        data: bytes,
        options: Options(
          headers: {...headers, 'Content-Type': 'application/octet-stream'},
        ),
      );
      final url = 'https://github.com/$repo/releases/download/$tag/$safe';
      await _catalog(repo, headers, name, url, apk);
      return PackagePublishResult(true, 'Added on GitHub as $tag.');
    } on DioException catch (e) {
      return PackagePublishResult(false, _gitError(e));
    }
  }

  static Future<Map<dynamic, dynamic>> _release(
    String repo,
    String tag,
    String name,
    bool apk,
    Map<String, String> headers,
  ) async {
    try {
      final created = await _dio.post<dynamic>(
        'https://api.github.com/repos/$repo/releases',
        data: {
          'tag_name': tag,
          'name': apk ? 'APK $name' : 'IPK $name',
          'body': 'Package $name for software installation.',
        },
        options: Options(headers: headers),
      );
      final data = created.data;
      if (data is Map) return data;
    } on DioException catch (e) {
      if (e.response?.statusCode != 422) rethrow;
    }
    final existing = await _dio.get<dynamic>(
      'https://api.github.com/repos/$repo/releases/tags/$tag',
      options: Options(headers: headers),
    );
    final data = existing.data;
    if (data is Map) return data;
    throw StateError('GitHub did not return the release.');
  }

  static Future<void> _catalog(
    String repo,
    Map<String, String> headers,
    String name,
    String url,
    bool apk,
  ) async {
    String? sha;
    Map<String, dynamic> catalog = {'packages': <dynamic>[]};
    try {
      final current = await _dio.get<dynamic>(
        'https://api.github.com/repos/$repo/contents/opkg-packages.json',
        options: Options(headers: headers),
      );
      final data = current.data;
      if (data is Map) {
        sha = data['sha']?.toString();
        final encoded = data['content']?.toString() ?? '';
        final text = utf8.decode(base64Decode(encoded.replaceAll('\n', '')));
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) catalog = decoded;
        if (decoded is Map) catalog = Map<String, dynamic>.from(decoded);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }
    final raw = catalog['packages'];
    final packages = raw is List ? [...raw] : <dynamic>[];
    var note = name;
    for (final item in packages) {
      if (item is Map && item['name']?.toString() == name) {
        final old = item['note']?.toString().trim() ?? '';
        if (old.isNotEmpty) note = old;
      }
    }
    packages.removeWhere(
      (item) => item is Map && item['name']?.toString() == name,
    );
    packages.add({
      'name': name,
      'note': note,
      if (apk) 'apk_url': url else 'ipk_url': url,
    });
    catalog['packages'] = packages;
    catalog['updated'] = _today();
    final body = jsonEncode(catalog);
    await _dio.put<dynamic>(
      'https://api.github.com/repos/$repo/contents/opkg-packages.json',
      data: {
        'message': 'Add $name for software installation',
        'sha': ?sha,
        'content': base64Encode(utf8.encode(body)),
      },
      options: Options(headers: headers),
    );
  }

  static String _today() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  static String _gitError(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    return error.message ?? 'GitHub did not accept the package.';
  }
}
