import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/rtwrt/profile.dart';
import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/utils/url_parser.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

/// Phone path (Wi-Fi or Tailscale) and the Tailscale package on the router.
class VpnScreen extends ConsumerStatefulWidget {
  const VpnScreen({super.key});

  @override
  ConsumerState<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends ConsumerState<VpnScreen> {
  final _wifi = TextEditingController();
  final _host = TextEditingController();
  final _auth = TextEditingController();
  String _mode = 'wifi';
  String _output = 'Status loads when you open this page.';
  bool _busy = false;
  bool _showAuth = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _status();
    });
  }

  @override
  void dispose() {
    _wifi.dispose();
    _host.dispose();
    _auth.dispose();
    super.dispose();
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _load() async {
    final storage = SecureStorageService();
    final savedWifi = await storage.readValue(RtwrtProfile.wifiIpKey);
    final savedHost = await storage.readValue(RtwrtProfile.tailscaleKey);
    final savedMode = await storage.readValue(RtwrtProfile.connectModeKey);
    final router = ref.read(appStateProvider).selectedRouter;
    if (!mounted) return;
    setState(() {
      _wifi.text = (savedWifi != null && savedWifi.isNotEmpty)
          ? savedWifi
          : (router?.ipAddress ?? '192.168.1.1');
      _host.text = (savedHost != null && savedHost.isNotEmpty)
          ? savedHost
          : (router?.alternateAddress ?? '');
      _mode = savedMode == 'tailscale' ? 'tailscale' : 'wifi';
    });
  }

  Future<void> _run(String script, {required String action}) async {
    final api = _client();
    if (api == null) {
      await showRtwrtResult(
        context,
        action: action,
        ok: false,
        detail: 'Not connected to the router.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final text = await api.shell(script);
      if (!mounted) return;
      final detail = text.trim().isEmpty ? 'Done.' : text.trim();
      setState(() => _output = detail);
      final failed =
          detail.contains('NO_PKG') ||
          detail.contains('TS_FAIL') ||
          detail.contains('NOT_INSTALLED');
      await showRtwrtResult(
        context,
        action: action,
        ok: !failed,
        detail: detail.contains('NO_PKG')
            ? 'This router has no package tool, so Tailscale was not installed.'
            : detail,
      );
    } catch (e) {
      if (!mounted) return;
      final detail = RtwrtApi.explain(e);
      setState(() => _output = detail);
      await showRtwrtResult(context, action: action, ok: false, detail: detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _status() async {
    await _run(r'''
if command -v tailscale >/dev/null 2>&1; then
  tailscale status 2>&1
  echo ---
  tailscale ip -4 2>&1
else
  echo NOT_INSTALLED
fi
''', action: 'Tailscale status');
  }

  Future<void> _install() async {
    await _run(r'''
if ! command -v tailscale >/dev/null 2>&1; then
  if command -v apk >/dev/null 2>&1; then
    apk add tailscale || apk add tailscaled
  elif command -v opkg >/dev/null 2>&1; then
    opkg update
    opkg install tailscale || opkg install tailscaled
  else
    echo NO_PKG
  fi
fi
if [ -x /etc/init.d/tailscale ]; then
  /etc/init.d/tailscale enable
  /etc/init.d/tailscale start
elif [ -x /etc/init.d/tailscaled ]; then
  /etc/init.d/tailscaled enable
  /etc/init.d/tailscaled start
fi
if command -v tailscale >/dev/null 2>&1; then
  echo TS_OK
  tailscale status 2>&1
else
  echo TS_FAIL
fi
''', action: 'Install Tailscale');
  }

  Future<void> _up() async {
    final key = _auth.text.trim();
    if (key.isNotEmpty && !RegExp(r'^[A-Za-z0-9_.:-]{8,200}$').hasMatch(key)) {
      await showRtwrtResult(
        context,
        action: 'Tailscale login',
        ok: false,
        detail: 'The auth key has characters this app will not send.',
      );
      return;
    }
    final command = key.isEmpty
        ? 'tailscale up 2>&1'
        : "tailscale up --auth-key='$key' 2>&1";
    _auth.clear();
    await _run('''
if ! command -v tailscale >/dev/null 2>&1; then
  echo NOT_INSTALLED
  exit 0
fi
$command
echo EXIT:\$?
''', action: 'Tailscale login');
  }

  Future<void> _connect() async {
    final wifi = UrlParser.parse(_wifi.text.trim());
    if (!wifi.isValid) {
      await showRtwrtResult(
        context,
        action: 'VPN',
        ok: false,
        detail: 'Enter the Wi-Fi address.',
      );
      return;
    }
    final hostText = _host.text.trim();
    ParsedUrl? host;
    if (hostText.isNotEmpty) {
      host = UrlParser.parse(hostText);
      if (!host.isValid) {
        await showRtwrtResult(
          context,
          action: 'VPN',
          ok: false,
          detail: 'Enter the Tailscale host as a name or IP.',
        );
        return;
      }
    }
    if (_mode == 'tailscale' && host == null) {
      await showRtwrtResult(
        context,
        action: 'VPN',
        ok: false,
        detail: 'Enter the Tailscale host before using VPN.',
      );
      return;
    }
    final app = ref.read(appStateProvider);
    final router = app.selectedRouter;
    if (router == null) {
      await showRtwrtResult(
        context,
        action: 'VPN',
        ok: false,
        detail: 'Not connected to the router.',
      );
      return;
    }
    setState(() => _busy = true);
    final storage = SecureStorageService();
    await storage.writeValue(RtwrtProfile.wifiIpKey, wifi.hostWithPort);
    await storage.writeValue(
      RtwrtProfile.tailscaleKey,
      host?.hostWithPort ?? '',
    );
    await storage.writeValue(RtwrtProfile.connectModeKey, _mode);
    final next = router.copyWith(
      ipAddress: wifi.hostWithPort,
      alternateAddress: host?.hostWithPort,
      alternateUseHttps: host?.useHttps,
      activeAddressIndex: _mode == 'tailscale' ? 1 : 0,
      clearAlternate: host == null,
    );
    await app.updateRouter(next);
    if (!mounted) return;
    await app.selectRouter(next.id, context: context);
    if (!mounted) return;
    setState(() => _busy = false);
    final used = _mode == 'tailscale' ? host!.hostWithPort : wifi.hostWithPort;
    final session = ref.read(sessionProvider);
    final ok = session?.ipAddress == used;
    await showRtwrtResult(
      context,
      action: 'VPN',
      ok: ok,
      detail: ok
          ? 'This phone now uses $used.'
          : 'Saved $used. The router did not answer on that address.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'VPN / Tailscale', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('vpn|$_mode'),
            initialValue: _mode,
            decoration: const InputDecoration(
              labelText: 'Phone connection',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'wifi', child: Text('Wi-Fi')),
              DropdownMenuItem(value: 'tailscale', child: Text('Tailscale')),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _mode = value);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wifi,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi IP',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _host,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Tailscale host',
              helperText: 'MagicDNS name or Tailscale IP',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _connect,
            child: const Text('Use this connection'),
          ),
          const SizedBox(height: 24),
          const Text(
            'On the router, Tailscale is a package. Install it here, then log in. '
            'An empty auth key prints the login link.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _auth,
            enabled: !_busy,
            obscureText: !_showAuth,
            decoration: InputDecoration(
              labelText: 'Auth key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showAuth = !_showAuth),
                icon: Icon(_showAuth ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : _install,
                child: const Text('Install on router'),
              ),
              FilledButton(
                onPressed: _busy ? null : _up,
                child: const Text('Log in'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _status,
                child: const Text('Status'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          SelectableText(_output),
        ],
      ),
    );
  }
}
