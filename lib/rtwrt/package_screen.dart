import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

/// Install and remove packages. A new init script then shows on Services.
class PackageScreen extends ConsumerStatefulWidget {
  const PackageScreen({super.key});

  @override
  ConsumerState<PackageScreen> createState() => _PackageScreenState();
}

class _PackageScreenState extends ConsumerState<PackageScreen> {
  final _name = TextEditingController();
  String _output = 'Installed packages load when you open this page.';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _list());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _run(String script, {String? action}) async {
    final api = _client();
    if (api == null) {
      if (action != null && mounted) {
        await showRtwrtResult(
          context,
          action: action,
          ok: false,
          detail: 'Not connected to the router.',
        );
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final text = await api.shell(script);
      if (!mounted) return;
      final detail = text.trim().isEmpty ? 'Done.' : text.trim();
      setState(() => _output = detail);
      if (action != null) {
        await showRtwrtResult(context, action: action, ok: true, detail: detail);
      }
    } catch (e) {
      if (!mounted) return;
      final detail = RtwrtApi.explain(e);
      setState(() => _output = detail);
      await showRtwrtResult(
        context,
        action: action ?? 'Software',
        ok: false,
        detail: detail,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _list() {
    _run(r'''
if command -v apk >/dev/null 2>&1; then
  apk list -I
elif command -v opkg >/dev/null 2>&1; then
  opkg list-installed
else
  echo "No package tool found"
fi
''');
  }

  bool _pkgOk(String name) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,80}$').hasMatch(name);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Software',
        showBack: true,
        actions: [
          IconButton(
            onPressed: _busy ? null : _list,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Package name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final name = _name.text.trim();
                                if (!_pkgOk(name)) {
                                  await showRtwrtResult(
                                    context,
                                    action: 'Install',
                                    ok: false,
                                    detail: 'Enter a package name.',
                                  );
                                  return;
                                }
                                await _run(
                                  'if command -v apk >/dev/null 2>&1; then apk add ${_sh(name)}; '
                                  'else opkg update; opkg install ${_sh(name)}; fi',
                                  action: 'Install $name',
                                );
                              },
                        child: const Text('Install'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final name = _name.text.trim();
                                if (!_pkgOk(name)) {
                                  await showRtwrtResult(
                                    context,
                                    action: 'Remove',
                                    ok: false,
                                    detail: 'Enter a package name.',
                                  );
                                  return;
                                }
                                await _run(
                                  'if command -v apk >/dev/null 2>&1; then apk del ${_sh(name)}; '
                                  'else opkg remove ${_sh(name)}; fi',
                                  action: 'Remove $name',
                                );
                              },
                        child: const Text('Remove'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SelectableText(_output),
            ),
          ),
        ],
      ),
    );
  }
}

String _sh(String value) => "'${value.replaceAll("'", "'\\''")}'";
