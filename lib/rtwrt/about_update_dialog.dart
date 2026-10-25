import 'package:flutter/material.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/rtwrt/apk_install.dart';
import 'package:luci_mobile/rtwrt/github_release.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// About box. Update downloads the newer APK from GitHub and opens the installer.
class AboutUpdateDialog extends StatefulWidget {
  const AboutUpdateDialog({super.key});

  @override
  State<AboutUpdateDialog> createState() => _AboutUpdateDialogState();
}

class _AboutUpdateDialogState extends State<AboutUpdateDialog> {
  PackageInfo? _info;
  String _status = 'Checking GitHub for an update.';
  String? _apkUrl;
  bool _newer = false;
  bool _busy = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _info = info);
    try {
      final release = await GithubReleases.latest(AppConfig.githubRepo);
      GithubAsset? apk;
      GithubAsset? meta;
      for (final asset in release.assets) {
        if (asset.name.toLowerCase().endsWith('.apk')) apk = asset;
        if (asset.name == 'version.json') meta = asset;
      }
      var remoteCode = 0;
      if (meta != null) {
        try {
          final json = await GithubReleases.readJson(meta.url);
          final code = json['versionCode'];
          remoteCode = code is int ? code : int.tryParse('$code') ?? 0;
        } catch (_) {
          remoteCode = 0;
        }
      }
      final localCode = int.tryParse(info.buildNumber) ?? 0;
      final newer =
          (remoteCode > 0 && localCode > 0 && remoteCode > localCode) ||
          (remoteCode == 0 && isNewerVersion(release.tag, info.version));
      if (!mounted) return;
      setState(() {
        _apkUrl = apk?.url;
        _newer = newer && apk != null;
        _status = newer && apk != null
            ? 'Version ${release.tag} is on GitHub.'
            : 'This is the latest version.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Could not reach GitHub. $e');
    }
  }

  Future<void> _update() async {
    final url = _apkUrl;
    if (url == null || _busy) return;
    if (!await ApkInstall.canInstall()) {
      await ApkInstall.openInstallSettings();
      if (!mounted) return;
      setState(() {
        _status = 'Allow installs from RTWRT, then tap Update again.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Downloading the update.';
    });
    try {
      await ApkInstall.downloadAndInstall(
        url,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;
      setState(() => _status = 'Confirm the install on the next screen.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'The update did not install. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.router, size: 32),
          const SizedBox(width: 12),
          Text(context.l10n.appTitle),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            info == null
                ? context.l10n.versionLabel
                : context.l10n.version(info.version),
          ),
          const SizedBox(height: 16),
          Text(context.l10n.aboutDescription),
          const SizedBox(height: 16),
          Text(context.l10n.openSourceDescription),
          const SizedBox(height: 16),
          Text(_status),
          if (_progress != null && _busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          ],
          const SizedBox(height: 16),
          InkWell(
            onTap: () => launchUrlString(
              AppConfig.githubRepositoryUrl,
              mode: LaunchMode.externalApplication,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.link,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.githubRepository,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _newer && !_busy ? _update : null,
          child: const Text('Update'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
