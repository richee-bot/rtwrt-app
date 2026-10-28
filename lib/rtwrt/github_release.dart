import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:luci_mobile/config/app_config.dart';

/// A file attached to a GitHub release, or listed in firmware.json.
class GithubAsset {
  const GithubAsset({required this.name, required this.url, this.note = ''});

  final String name;
  final String url;
  final String note;
}

class GithubRelease {
  const GithubRelease({required this.tag, required this.assets});

  final String tag;
  final List<GithubAsset> assets;
}

/// True when [remote] is a newer dotted version than [local].
bool isNewerVersion(String remote, String local) {
  List<int> parts(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^v'), '');
    final core = cleaned.split('+').first;
    return [for (final piece in core.split('.')) int.tryParse(piece) ?? 0];
  }

  final left = parts(remote);
  final right = parts(local);
  final count = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < count; i++) {
    final a = i < left.length ? left[i] : 0;
    final b = i < right.length ? right[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// Only richee-bot GitHub URLs are sent to the router or the installer.
bool isRicheeGithubUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  if (host != 'github.com' && host != 'raw.githubusercontent.com') {
    return false;
  }
  return uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'richee-bot';
}

/// One router package from opkg-packages.json.
class RouterPackage {
  const RouterPackage({
    required this.name,
    required this.note,
    required this.url,
  });

  final String name;
  final String note;
  final String url;

  bool get isApk => url.toLowerCase().endsWith('.apk');
  String get formatRemark => isApk ? 'APK' : 'IPK';
  String get id => '$name:${formatRemark.toLowerCase()}';

  String get label {
    final cleanNote = note.trim();
    final prefix = '[$formatRemark]';
    if (cleanNote.isEmpty) return '$prefix $name';
    if (cleanNote.toUpperCase().startsWith('[APK]') ||
        cleanNote.toUpperCase().startsWith('[IPK]') ||
        cleanNote.toUpperCase().startsWith('[APK / IPK]')) {
      return '$name — $cleanNote';
    }
    return '$prefix $name — $cleanNote';
  }
}

/// Release download for an .ipk or .apk on the firmware repo.
final RegExp routerPackageUrl = RegExp(
  r'^https://github\.com/richee-bot/rtwrt-aw1000-firmware/releases/download/[A-Za-z0-9._+%-]+/[A-Za-z0-9._+%-]+\.(?:ipk|apk)$',
);

/// Packages the Software screen can install. Invalid URLs are left out.
List<RouterPackage> routerPackagesFrom(Map<String, dynamic> json) {
  final raw = json['packages'];
  if (raw is! List) return const [];
  final out = <RouterPackage>[];
  final seen = <String>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final name = item['name']?.toString().trim() ?? '';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,80}$').hasMatch(name)) {
      continue;
    }
    final rawNote = item['note']?.toString().trim() ?? '';
    final apk = item['apk_url']?.toString().trim() ?? '';
    final ipk = item['ipk_url']?.toString().trim() ?? '';

    final hasApk = routerPackageUrl.hasMatch(apk);
    final hasIpk = routerPackageUrl.hasMatch(ipk);

    if (hasApk && seen.add('${name.toLowerCase()}:apk')) {
      final noteText = rawNote.replaceAll('[APK / IPK]', '[APK]');
      out.add(
        RouterPackage(
          name: name,
          note: noteText,
          url: apk,
        ),
      );
    }
    if (hasIpk && seen.add('${name.toLowerCase()}:ipk')) {
      final noteText = rawNote.replaceAll('[APK / IPK]', '[IPK]');
      out.add(
        RouterPackage(
          name: name,
          note: noteText,
          url: ipk,
        ),
      );
    }
  }
  return out;
}

class GithubReleases {
  static final Dio _dio = Dio(
    BaseOptions(
      headers: const {
        'User-Agent': 'RTWRT',
        'Accept': 'application/vnd.github+json',
      },
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<Map<String, dynamic>> readJson(String url) async {
    if (!isRicheeGithubUrl(url)) {
      throw const FormatException('That file is not on the RTWRT GitHub.');
    }
    final response = await _dio.get<dynamic>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final raw = response.data;
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('GitHub did not return JSON.');
  }

  static Future<GithubRelease> latest(String repo) async {
    final response = await _dio.get<dynamic>(
      'https://api.github.com/repos/$repo/releases/latest',
    );
    return _release(response.data);
  }

  static GithubRelease _release(dynamic data) {
    if (data is! Map) {
      throw const FormatException('GitHub did not return a release.');
    }
    final assets = <GithubAsset>[];
    final rawAssets = data['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map) continue;
        final name = item['name']?.toString() ?? '';
        final url = item['browser_download_url']?.toString() ?? '';
        if (name.isEmpty || !isRicheeGithubUrl(url)) continue;
        assets.add(GithubAsset(name: name, url: url));
      }
    }
    return GithubRelease(
      tag: data['tag_name']?.toString() ?? '',
      assets: assets,
    );
  }

  /// Sysupgrade images listed in firmware.json, then .bin release assets.
  static Future<List<GithubAsset>> firmwareImages() async {
    final images = <GithubAsset>[];
    final seen = <String>{};
    void add(GithubAsset asset) {
      if (!isRicheeGithubUrl(asset.url)) return;
      if (!asset.url.toLowerCase().contains('.bin')) return;
      if (seen.add(asset.url)) images.add(asset);
    }

    for (final repo in [AppConfig.githubRepo, AppConfig.firmwareRepo]) {
      try {
        final response = await _dio.get<dynamic>(
          'https://raw.githubusercontent.com/$repo/main/firmware.json',
          options: Options(responseType: ResponseType.plain),
        );
        final raw = response.data;
        final decoded = raw is String ? jsonDecode(raw) : raw;
        final list = decoded is Map ? decoded['images'] : null;
        if (list is! List) continue;
        for (final item in list) {
          if (item is! Map) continue;
          add(
            GithubAsset(
              name: item['name']?.toString() ?? 'Firmware',
              url: item['url']?.toString() ?? '',
              note: item['note']?.toString() ?? '',
            ),
          );
        }
      } catch (_) {
        // An empty or missing index is fine. Releases are checked next.
      }
    }

    try {
      final response = await _dio.get<dynamic>(
        'https://api.github.com/repos/${AppConfig.firmwareRepo}/releases',
        queryParameters: const {'per_page': 30},
      );
      final releases = response.data;
      if (releases is List) {
        for (final release in releases) {
          for (final asset in _release(release).assets) {
            final name = asset.name.toLowerCase();
            if (name.endsWith('.bin')) add(asset);
          }
        }
      }
    } catch (_) {
      // The curated list still stands when the release API is unavailable.
    }
    return images;
  }
}
