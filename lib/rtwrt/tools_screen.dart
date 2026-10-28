import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';
import 'package:luci_mobile/rtwrt/bandix_screen.dart';
import 'package:luci_mobile/rtwrt/cpu_mode_screen.dart';
import 'package:luci_mobile/rtwrt/file_manager_screen.dart';
import 'package:luci_mobile/rtwrt/ftp_screen.dart';
import 'package:luci_mobile/rtwrt/netstat_screen.dart';
import 'package:luci_mobile/rtwrt/ping_test_screen.dart';
import 'package:luci_mobile/rtwrt/repo_keys_screen.dart';
import 'package:luci_mobile/rtwrt/storage_manager_screen.dart';
import 'package:luci_mobile/rtwrt/system_info_screen.dart';
import 'package:luci_mobile/rtwrt/ttl_switch_screen.dart';

class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  final _host = TextEditingController(text: '1.1.1.1');
  final _cron = TextEditingController();
  final _cmd = TextEditingController();
  String _output = '';
  bool _busy = false;

  @override
  void dispose() {
    _host.dispose();
    _cron.dispose();
    _cmd.dispose();
    super.dispose();
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _report(String action, bool ok, String detail) async {
    final text = detail.trim().isEmpty
        ? (ok ? 'Done.' : 'The router did not say why.')
        : detail.trim();
    if (!mounted) return;
    setState(() => _output = text);
    await showRtwrtResult(context, action: action, ok: ok, detail: text);
  }

  Future<void> _run(String action, String script) async {
    final api = _client();
    if (api == null) {
      await _report(action, false, 'Not connected to the router.');
      return;
    }
    setState(() => _busy = true);
    try {
      final text = await api.shell(script);
      if (!mounted) return;
      await _report(action, true, text);
    } catch (e) {
      if (!mounted) return;
      await _report(action, false, RtwrtApi.explain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _hostOk(String value) =>
      RegExp(r'^[A-Za-z0-9._:-]{1,253}$').hasMatch(value);

  Future<void> _backup() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.shell('sysupgrade -b /tmp/rtwrt-backup.tar.gz');
      final bytes = await api.readBase64File('/tmp/rtwrt-backup.tar.gz');
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rtwrt-backup.tar.gz');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await _report(
        'Save backup',
        true,
        'Backup saved on this phone.\n${file.path}',
      );
    } catch (e) {
      if (!mounted) return;
      await _report('Save backup', false, RtwrtApi.explain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore settings'),
        content: const Text(
          'This puts the last backup back on the router and reboots it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/rtwrt-backup.tar.gz');
      final bytes = await file.readAsBytes();
      await api.writeBase64File('/tmp/rtwrt-backup.tar.gz', bytes);
      final text = await api.shell('sysupgrade -r /tmp/rtwrt-backup.tar.gz');
      if (!mounted) return;
      await _report(
        'Restore backup',
        true,
        text.trim().isEmpty ? 'Restore started.' : text,
      );
    } catch (e) {
      if (!mounted) return;
      await _report('Restore backup', false, RtwrtApi.explain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  
  Future<void> _nav(Widget page) async {
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _wifiCode() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final values = await api.uciAll('wireless');
      if (!mounted) return;
      final nets = <Map<String, String>>[];
      for (final section in values.values) {
        final ssid = section['ssid']?.toString() ?? '';
        if (ssid.isEmpty || section['disabled']?.toString() == '1') continue;
        nets.add({
          'ssid': ssid,
          'key': section['key']?.toString() ?? '',
          'enc': section['encryption']?.toString() ?? '',
        });
      }
      setState(() => _busy = false);
      if (!mounted) return;
      if (nets.isEmpty) {
        await _report('Wi-Fi join code', false, 'No Wi-Fi name is turned on.');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final net in nets) ...[
              Text(
                net['ssid']!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Center(
                child: QrImageView(
                  data: _wifiPayload(net['ssid']!, net['key']!, net['enc']!),
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      );
    } catch (e) {
      if (mounted) await _report('Wi-Fi join code', false, RtwrtApi.explain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Tools', showBack: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_busy) const LinearProgressIndicator(),
          _heading('Mobile link'),
          _action(
            'Redial',
            'Start the modem connection again',
            () => _run(
              'Redial',
              '/etc/init.d/qmodem_network restart; echo The modem is dialing again.',
            ),
          ),
          _action(
            'Data use',
            'Today and this month on the mobile link',
            () => _run(
              'Data use',
              'vnstat -i wwan0_1; echo; vnstat -m -i wwan0_1',
            ),
          ),
          _action(
            'Speed check',
            'A short download through the router',
            () => _run(
              'Speed check',
              "curl -L -o /dev/null -w 'Downloaded %{size_download} bytes in %{time_total}s\\n' --max-time 20 http://speed.cloudflare.com/__down?bytes=5000000",
            ),
          ),
          _action(
            'TTL Switch (Hotspot Bypass)',
            'Presets: TTL 64, 65, 128, 129, 255',
            () => _nav(const TtlSwitchScreen()),
          ),
          _action(
            'Bandwidth & Bandix Monitor',
            'Real-time eBPF traffic stats and device rates',
            () => _nav(const BandixScreen()),
          ),
          _action(
            'Ping Test & Internet Status',
            'Live IPv4/IPv6 ping probes and packet loss',
            () => _nav(const PingTestScreen()),
          ),
          _heading('Check a site'),
          TextField(
            controller: _host,
            decoration: const InputDecoration(
              labelText: 'Site or address',
              hintText: '1.1.1.1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _chip('Ping', () {
                final host = _host.text.trim();
                if (!_hostOk(host)) {
                  return _report('Ping', false, 'Enter a site or address.');
                }
                return _run('Ping', 'ping -c 4 -W 2 ${_sh(host)}');
              }),
              _chip('Trace', () {
                final host = _host.text.trim();
                if (!_hostOk(host)) {
                  return _report('Trace', false, 'Enter a site or address.');
                }
                return _run('Trace', 'traceroute -w 2 -m 15 ${_sh(host)}');
              }),
              _chip('DNS', () {
                final host = _host.text.trim();
                if (!_hostOk(host)) {
                  return _report('DNS', false, 'Enter a site or address.');
                }
                return _run('DNS', 'nslookup ${_sh(host)}');
              }),
            ],
          ),
          _heading('Wi-Fi and backup'),
          _action('Wi-Fi join code', 'A code a guest can scan', _wifiCode),
          _action(
            'Save backup',
            'Keep a copy of the settings on this phone',
            _backup,
          ),
          _action(
            'Restore backup',
            'Put the last copy back and reboot',
            _restore,
          ),
          _heading('System & Storage Tools'),
          _action(
            'System Info',
            'Hardware model, CPU, kernel, load, and memory',
            () => _nav(const SystemInfoScreen()),
          ),
          _action(
            'Storage & Disk Manager',
            'Overlay space, RAM disk (/tmp), block devices, and mounts',
            () => _nav(const StorageManagerScreen()),
          ),
          _action(
            'File Manager',
            'Browse router filesystem, upload and download files',
            () => _nav(const FileManagerScreen()),
          ),
          _action(
            'Netstat (Open Ports)',
            'Inspection of listening ports and active sockets',
            () => _nav(const NetstatScreen()),
          ),
          _action(
            'Repository Public Keys',
            'Manage APK and OPKG signing verification keys',
            () => _nav(const RepoKeysScreen()),
          ),
          _action(
            'CPU Mode Scaling',
            'LowPower, Schedutil, and Performance scaling governors',
            () => _nav(const CpuModeScreen()),
          ),
          _action(
            'FTP File Server',
            'vsftpd status, start/stop, and controls',
            () => _nav(const FtpScreen()),
          ),
          _heading('Router Operations'),
          _action(
            'Free some memory',
            'Clear caches. The router stays online.',
            () => _run(
              'Free some memory',
              'sync; echo 3 > /proc/sys/vm/drop_caches; free -m',
            ),
          ),
          _action(
            'What is running',
            'Programs on the router right now',
            () => _run('What is running', 'ps w'),
          ),
          _action(
            'Routes',
            'Where traffic is sent',
            () => _run('Routes', 'ip route'),
          ),
          _action(
            'System log',
            'The latest messages',
            () => _run('System log', 'logread | tail -n 80'),
          ),
          _heading('Schedule'),
          TextField(
            controller: _cron,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Tasks, one per line',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _chip('Load', () async {
                final api = _client();
                if (api == null) {
                  await _report(
                    'Load tasks',
                    false,
                    'Not connected to the router.',
                  );
                  return;
                }
                setState(() => _busy = true);
                try {
                  final text = await api.shell(
                    'cat /etc/crontabs/root 2>/dev/null',
                  );
                  if (!mounted) return;
                  setState(() => _cron.text = text);
                  await _report(
                    'Load tasks',
                    true,
                    text.trim().isEmpty ? 'No tasks saved.' : 'Tasks loaded.',
                  );
                } catch (e) {
                  if (mounted) {
                    await _report('Load tasks', false, RtwrtApi.explain(e));
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              }),
              _chip(
                'Save',
                () => _run(
                  'Save tasks',
                  'mkdir -p /etc/crontabs; cat > /etc/crontabs/root << \'RTWRT_EOF\'\n${_cron.text}\nRTWRT_EOF\n/etc/init.d/cron restart; echo Saved.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Advanced command'),
            subtitle: const Text(
              'Runs on the router. Leave this closed for normal use.',
            ),
            children: [
              TextField(
                controller: _cmd,
                decoration: const InputDecoration(
                  labelText: 'Command',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final cmd = _cmd.text.trim();
                        if (cmd.isEmpty) {
                          await _report('Command', false, 'Enter a command.');
                          return;
                        }
                        await _run('Command', cmd);
                      },
                child: const Text('Run'),
              ),
            ],
          ),
          if (_output.isNotEmpty) ...[
            const SizedBox(height: 16),
            SelectableText(_output),
          ],
        ],
      ),
    );
  }

  Widget _heading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _action(
    String title,
    String subtitle,
    Future<void> Function() action,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      enabled: !_busy,
      trailing: const Icon(Icons.chevron_right),
      onTap: _busy
          ? null
          : () {
              action();
            },
    );
  }

  Widget _chip(String label, Future<void> Function() action) {
    return ActionChip(
      label: Text(label),
      onPressed: _busy
          ? null
          : () {
              action();
            },
    );
  }
}

String _sh(String value) => "'${value.replaceAll("'", "'\\''")}'";

String _wifiPayload(String ssid, String key, String enc) {
  final type = enc.contains('wpa') || key.isNotEmpty ? 'WPA' : 'nopass';
  String esc(String raw) => raw.replaceAll(r'\', r'\\').replaceAll(';', r'\;');
  return 'WIFI:T:$type;S:${esc(ssid)};P:${esc(key)};;';
}
