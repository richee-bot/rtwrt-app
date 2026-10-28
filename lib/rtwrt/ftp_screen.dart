import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class FtpScreen extends ConsumerStatefulWidget {
  const FtpScreen({super.key});

  @override
  ConsumerState<FtpScreen> createState() => _FtpScreenState();
}

class _FtpScreenState extends ConsumerState<FtpScreen> {
  bool _busy = false;
  bool _installed = false;
  bool _running = false;
  bool _enabledOnBoot = false;
  String _serviceOutput = '';
  final _portController = TextEditingController(text: '21');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFtpStatus());
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _checkFtpStatus() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final out = await api.shell(r'''
INSTALLED=0
which vsftpd >/dev/null 2>&1 && INSTALLED=1
RUNNING=0
pgrep vsftpd >/dev/null 2>&1 && RUNNING=1
ENABLED=0
[ -f /etc/rc.d/*vsftpd* ] && ENABLED=1
echo "INSTALLED=$INSTALLED"
echo "RUNNING=$RUNNING"
echo "ENABLED=$ENABLED"
/etc/init.d/vsftpd status 2>&1 || true
''');
      if (!mounted) return;
      final inst = RegExp(r'^INSTALLED=(.*)$', multiLine: true).firstMatch(out)?.group(1)?.trim() == '1';
      final run = RegExp(r'^RUNNING=(.*)$', multiLine: true).firstMatch(out)?.group(1)?.trim() == '1';
      final en = RegExp(r'^ENABLED=(.*)$', multiLine: true).firstMatch(out)?.group(1)?.trim() == '1';

      setState(() {
        _installed = inst;
        _running = run;
        _enabledOnBoot = en;
        _serviceOutput = out;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _control(String action, String cmd) async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final res = await api.shell(cmd);
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(
          context,
          action: 'FTP $action',
          ok: true,
          detail: res.trim().isEmpty ? '$action completed.' : res.trim(),
        );
        _checkFtpStatus();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showRtwrtResult(context, action: 'FTP $action', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  Future<void> _installFtp() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final res = await api.shell(r'''
if command -v apk >/dev/null 2>&1; then
  apk add --allow-untrusted vsftpd
else
  opkg update && opkg install vsftpd
fi
/etc/init.d/vsftpd enable 2>/dev/null || true
/etc/init.d/vsftpd start 2>/dev/null || true
''');
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(
          context,
          action: 'Install FTP',
          ok: res.contains('OK') || res.contains('Installing') || !res.contains('ERROR'),
          detail: res.trim(),
        );
        _checkFtpStatus();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showRtwrtResult(context, action: 'Install FTP', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'FTP File Server',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _checkFtpStatus,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.folder_shared, color: Color(0xFF00F0FF)),
                          SizedBox(width: 8),
                          Text('FTP Service Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (_running ? const Color(0xFF00FF9D) : Colors.redAccent).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _running ? const Color(0xFF00FF9D) : Colors.redAccent),
                        ),
                        child: Text(
                          !_installed ? 'NOT INSTALLED' : (_running ? 'RUNNING' : 'STOPPED'),
                          style: TextStyle(
                            color: _running ? const Color(0xFF00FF9D) : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (!_installed) ...[
                    const Text(
                      'vsftpd (Secure FTP Daemon) is not currently installed on the router. Tap below to install it.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Install vsftpd FTP Server'),
                      onPressed: _busy ? null : _installFtp,
                    ),
                  ] else ...[
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                          label: Text(_running ? 'Stop FTP' : 'Start FTP'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _running ? Colors.redAccent : const Color(0xFF00FF9D),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: _busy
                              ? null
                              : () => _control(
                                    _running ? 'Stop' : 'Start',
                                    _running ? '/etc/init.d/vsftpd stop' : '/etc/init.d/vsftpd start',
                                  ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Restart'),
                          onPressed: _busy ? null : () => _control('Restart', '/etc/init.d/vsftpd restart'),
                        ),
                        OutlinedButton.icon(
                          icon: Icon(_enabledOnBoot ? Icons.check_box : Icons.check_box_outline_blank),
                          label: Text(_enabledOnBoot ? 'Auto-start: ON' : 'Auto-start: OFF'),
                          onPressed: _busy
                              ? null
                              : () => _control(
                                    _enabledOnBoot ? 'Disable' : 'Enable',
                                    _enabledOnBoot ? '/etc/init.d/vsftpd disable' : '/etc/init.d/vsftpd enable',
                                  ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_installed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FTP Server Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'FTP Port',
                        hintText: '21',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.info_outline),
                      title: Text('FTP Default Directory: / (Root) or /tmp'),
                      subtitle: Text('Users can log in using router root username and password.'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Service Output & Diagnostics'),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.black26,
                child: SelectableText(
                  _serviceOutput,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
