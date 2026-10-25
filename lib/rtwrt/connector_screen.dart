import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/connector_installer.dart';
import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

/// Installs the GitHub ubus connector on the router that is signed in.
class ConnectorScreen extends ConsumerStatefulWidget {
  const ConnectorScreen({super.key});

  @override
  ConsumerState<ConnectorScreen> createState() => _ConnectorScreenState();
}

class _ConnectorScreenState extends ConsumerState<ConnectorScreen> {
  bool _busy = false;

  Future<void> _install() async {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) {
      await showRtwrtResult(
        context,
        action: 'Router connector',
        ok: false,
        detail: 'Not connected to the router.',
      );
      return;
    }
    setState(() => _busy = true);
    final result = await ConnectorInstaller.install(
      RtwrtApi(api, session),
      refresh: () => ConnectorInstaller.refreshSession(ref),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await showRtwrtResult(
      context,
      action: 'Router connector',
      ok: result.outcome != ConnectorOutcome.failed,
      detail: result.message,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Router connector', showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'This downloads the RTWRT connector from GitHub and puts it on the router. It also installs the bandwidth monitor when that package is missing. The app signs in again when the connector is ready.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _install,
            child: Text(_busy ? 'Installing' : 'Install from GitHub'),
          ),
        ],
      ),
    );
  }
}
