import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/github_release.dart';
import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

/// Downloads a sysupgrade image from GitHub and flashes it on the router.
class FirmwareScreen extends ConsumerStatefulWidget {
  const FirmwareScreen({super.key});

  @override
  ConsumerState<FirmwareScreen> createState() => _FirmwareScreenState();
}

class _FirmwareScreenState extends ConsumerState<FirmwareScreen> {
  List<GithubAsset> _images = const [];
  String? _error;
  bool _loading = true;
  bool _keepSettings = true;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final images = await GithubReleases.firmwareImages();
      if (!mounted) return;
      setState(() {
        _images = images;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _flash(GithubAsset image) async {
    if (_busy) return;
    if (!isRicheeGithubUrl(image.url)) {
      await showRtwrtResult(
        context,
        action: 'Firmware',
        ok: false,
        detail: 'That image is not on the RTWRT GitHub.',
      );
      return;
    }
    final keep = _keepSettings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update firmware'),
        content: Text(
          keep
              ? 'Install ${image.name} and keep this router’s settings. The router reboots.'
              : 'Install ${image.name} and do not keep settings. Wi-Fi names and passwords are cleared. The router reboots.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = _client();
    if (api == null) {
      await showRtwrtResult(
        context,
        action: 'Firmware',
        ok: false,
        detail: 'Not connected to the router.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Downloading the image on the router.';
    });
    final flag = keep ? '' : '-n ';
    final url = image.url.replaceAll("'", '');
    try {
      final fetched = await api.shell('''
rm -f /tmp/rtwrt-firmware.bin
if command -v curl >/dev/null 2>&1; then
  curl -fL --retry 2 -o /tmp/rtwrt-firmware.bin '$url'
elif command -v wget >/dev/null 2>&1; then
  wget -O /tmp/rtwrt-firmware.bin '$url'
else
  echo NO_DOWNLOAD
  exit 0
fi
echo DOWNLOAD:\$?
sysupgrade -T /tmp/rtwrt-firmware.bin
echo TEST:\$?
''');
      if (!mounted) return;
      if (fetched.contains('NO_DOWNLOAD') || !fetched.contains('DOWNLOAD:0')) {
        await showRtwrtResult(
          context,
          action: 'Firmware',
          ok: false,
          detail: fetched.trim().isEmpty
              ? 'The router could not download the image.'
              : fetched.trim(),
        );
        return;
      }
      if (!fetched.contains('TEST:0')) {
        await showRtwrtResult(
          context,
          action: 'Firmware',
          ok: false,
          detail: 'The router rejected this image.\n\n${fetched.trim()}',
        );
        return;
      }
      setState(() => _status = 'Installing. The router will reboot.');
      try {
        await api.shell('sysupgrade $flag/tmp/rtwrt-firmware.bin');
      } catch (e) {
        // The link drops when the reboot starts. That is the install.
        if (!mounted) return;
        await showRtwrtResult(
          context,
          action: 'Firmware',
          ok: true,
          detail:
              'The update was sent. The router reboots and may be offline for a few minutes.',
        );
        return;
      }
      if (!mounted) return;
      await showRtwrtResult(
        context,
        action: 'Firmware',
        ok: true,
        detail: 'The router is installing the image and will reboot.',
      );
    } catch (e) {
      if (!mounted) return;
      await showRtwrtResult(
        context,
        action: 'Firmware',
        ok: false,
        detail: RtwrtApi.explain(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Firmware',
        showBack: true,
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep settings'),
            subtitle: Text(
              _keepSettings
                  ? 'Names, passwords, and packages stay.'
                  : 'The router starts clean.',
            ),
            value: _keepSettings,
            onChanged: _busy
                ? null
                : (value) => setState(() => _keepSettings = value),
          ),
          const SizedBox(height: 8),
          const Text(
            'Images are the sysupgrade files published on your GitHub.',
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_status),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!)
          else if (_images.isEmpty)
            const Text(
              'No firmware image is published on GitHub yet. Attach a .bin to a release, or add it to firmware.json.',
            )
          else
            for (final image in _images)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(image.name),
                subtitle: Text(
                  image.note.isEmpty ? image.url : image.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                enabled: !_busy,
                trailing: const Icon(Icons.system_update_alt),
                onTap: _busy ? null : () => _flash(image),
              ),
        ],
      ),
    );
  }
}
