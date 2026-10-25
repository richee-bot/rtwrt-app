import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/models/service_status.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';
import 'package:luci_mobile/rtwrt/uci_browser_screen.dart';

const _coreServices = {
  'boot',
  'bootcount',
  'cron',
  'dnsmasq',
  'done',
  'dropbear',
  'firewall',
  'fstab',
  'gpio_switch',
  'led',
  'led-status',
  'log',
  'network',
  'odhcpd',
  'openssl',
  'packet_steering',
  'qca-nss-drv',
  'rpcd',
  'set-irq-affinity',
  'skb_recycler',
  'smp_affinity',
  'sysctl',
  'sysfixtime',
  'sysntpd',
  'system',
  'ucitrack',
  'uhttpd',
  'umount',
  'urandom_seed',
  'urngd',
  'wpad',
  'zram',
};

const _critical = {
  'uhttpd',
  'rpcd',
  'network',
  'firewall',
  'dnsmasq',
  'dropbear',
  'wpad',
};

const _labels = {
  'passwall2': 'PassWall 2',
  'passwall': 'PassWall 1',
  'passwall2_server': 'PassWall 2 server',
  'passwall_server': 'PassWall server',
  'rtwrt-ads': 'RTWRT ADS',
  'rtwrt_rgb_led': 'RGB LED',
  'adguardhome': 'AdGuard Home',
  'openclash': 'OpenClash',
  'sing-box': 'sing-box',
  'haproxy': 'HAProxy',
  'microsocks': 'microsocks',
  'naiveproxy': 'naiveproxy',
  'ttyd': 'Terminal service',
  'byte-ttl': 'TTL',
  'qmodem_network': 'Modem dial',
  'qmodem_init': 'Modem startup',
  'cpufreq': 'CPU',
  'vnstat': 'Bandwidth',
  'adblock': 'AdBlock',
};

const _configFor = {
  'rtwrt-ads': 'rtwrt_ads',
  'rtwrt_rgb_led': 'rtwrt_led',
  'byte-ttl': 'qmodem_ttl',
  'qmodem_network': 'qmodem',
  'qmodem_init': 'qmodem',
  'qmodem-iface-heal': 'qmodem',
  'qmodem_reboot': 'qmodem',
};

/// Optional services on this router. A new init script shows up on refresh.
class ServiceBoardScreen extends ConsumerStatefulWidget {
  const ServiceBoardScreen({super.key});

  @override
  ConsumerState<ServiceBoardScreen> createState() => _ServiceBoardScreenState();
}

class _ServiceBoardScreenState extends ConsumerState<ServiceBoardScreen> {
  List<ServiceStatus> _items = const [];
  bool _loading = true;
  bool _showCore = false;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) {
      setState(() {
        _loading = false;
        _error = 'Not connected to the router.';
      });
      return;
    }
    try {
      final map = await api.rcList(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
      );
      final list = map.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = RtwrtApi.explain(e);
      });
    }
  }

  bool _on(ServiceStatus service) => service.running ?? service.enabled;

  Future<void> _toggle(ServiceStatus service, bool on) async {
    if (_critical.contains(service.name) && !on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(service.name),
          content: const Text(
            'Stopping this service can drop the connection to the router.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Stop'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return;
    setState(() => _busy = service.name);
    final action = on ? 'Start ${service.name}' : 'Stop ${service.name}';
    var ok = true;
    var detail = on ? 'Started.' : 'Stopped.';
    try {
      await api.rcInit(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        name: service.name,
        action: on ? 'enable' : 'disable',
      );
      await api.rcInit(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        name: service.name,
        action: on ? 'start' : 'stop',
      );
    } catch (e) {
      ok = false;
      detail = RtwrtApi.explain(e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (!mounted) return;
    await showRtwrtResult(context, action: action, ok: ok, detail: detail);
    if (mounted) await _load();
  }

  void _openConfig(ServiceStatus service) {
    final config =
        _configFor[service.name] ?? service.name.replaceAll('-', '_');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UciBrowserScreen(initialConfig: config),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final item in _items)
        if (_showCore || !_coreServices.contains(item.name)) item,
    ];
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Services',
        showBack: true,
        actions: [
          IconButton(
            tooltip: _showCore ? 'Hide core' : 'Show core',
            onPressed: () => setState(() => _showCore = !_showCore),
            icon: Icon(_showCore ? Icons.visibility_off : Icons.visibility),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: shown.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const ListTile(
                      title: Text('Installed services'),
                      subtitle: Text(
                        'A package you install later appears here on refresh. '
                        'Long-press a row to edit its settings.',
                      ),
                    );
                  }
                  final service = shown[index - 1];
                  final label = _labels[service.name] ?? service.name;
                  return ListTile(
                    title: Text(label),
                    subtitle: Text(
                      service.running == null
                          ? (service.enabled ? 'Enabled at boot' : 'Disabled')
                          : (service.running! ? 'Running' : 'Stopped'),
                    ),
                    onLongPress: () => _openConfig(service),
                    trailing: _busy == service.name
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Switch(
                            value: _on(service),
                            onChanged: (on) => _toggle(service, on),
                          ),
                  );
                },
              ),
            ),
    );
  }
}
