import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/screens/clients_screen.dart';
import 'package:luci_mobile/screens/diagnostics_screen.dart';
import 'package:luci_mobile/screens/firewall_screen.dart';
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/screens/log_screen.dart';
import 'package:luci_mobile/screens/system_settings_screen.dart';
import 'package:luci_mobile/screens/traffic_screen.dart';
import 'package:luci_mobile/screens/wifi_scan_screen.dart';
import 'package:luci_mobile/screens/wireless_screen.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_hub_tile.dart';

import 'package:luci_mobile/rtwrt/connector_installer.dart';
import 'package:luci_mobile/rtwrt/connector_screen.dart';
import 'package:luci_mobile/rtwrt/error_log_screen.dart';
import 'package:luci_mobile/rtwrt/firmware_screen.dart';
import 'package:luci_mobile/rtwrt/layout_store.dart';
import 'package:luci_mobile/rtwrt/modem_screen.dart';
import 'package:luci_mobile/rtwrt/package_screen.dart';
import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';
import 'package:luci_mobile/rtwrt/service_board_screen.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/rtwrt/tools_screen.dart';
import 'package:luci_mobile/rtwrt/uci_browser_screen.dart';

class _Dest {
  const _Dest(
    this.id,
    this.title,
    this.subtitle,
    this.icon,
    this.page, {
    required this.group,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget page;
  final String group;
}

const _groups = ['Everyday', 'Internet', 'Network', 'Lights', 'Care'];

const _destinations = <_Dest>[
  _Dest(
    'services',
    'Services',
    'Switches, including software you install later',
    Icons.toggle_on,
    ServiceBoardScreen(),
    group: 'Everyday',
  ),
  _Dest(
    'modem',
    'Modem',
    'Signal, bands, tower, AT, SMS, USSD',
    Icons.cell_tower,
    ModemScreen(),
    group: 'Everyday',
  ),
  _Dest(
    'tools',
    'Tools',
    'Redial, data use, ping, backup, tasks',
    Icons.build,
    ToolsScreen(),
    group: 'Care',
  ),
  _Dest(
    'software',
    'Software',
    'Install and remove packages',
    Icons.download,
    PackageScreen(),
    group: 'Care',
  ),
  _Dest(
    'configs',
    'All settings',
    'Every config file on the router',
    Icons.tune,
    UciBrowserScreen(),
    group: 'Care',
  ),
  _Dest(
    'wireless',
    'Wi-Fi',
    'Names, passwords, channels',
    Icons.wifi,
    WirelessScreen(),
    group: 'Everyday',
  ),
  _Dest(
    'scan',
    'Channel pick',
    'Networks around the router',
    Icons.wifi_find,
    WifiScanScreen(),
    group: 'Network',
  ),
  _Dest(
    'clients',
    'Clients',
    'Who is connected',
    Icons.people,
    ClientsScreen(),
    group: 'Everyday',
  ),
  _Dest(
    'firewall',
    'Firewall',
    'Zones, forwards, and rules',
    Icons.shield,
    FirewallScreen(),
    group: 'Network',
  ),
  _Dest(
    'interfaces',
    'Interfaces',
    'LAN, WAN, and the mobile link',
    Icons.lan,
    InterfacesScreen(showBack: true),
    group: 'Network',
  ),
  _Dest(
    'passwall2',
    'PassWall 2',
    'Nodes and rules for the VPN that is in use',
    Icons.vpn_lock,
    UciBrowserScreen(initialConfig: 'passwall2'),
    group: 'Internet',
  ),
  _Dest(
    'passwall',
    'PassWall 1',
    'The other PassWall copy',
    Icons.vpn_key,
    UciBrowserScreen(initialConfig: 'passwall'),
    group: 'Internet',
  ),
  _Dest(
    'openclash',
    'OpenClash',
    'Clash settings on the router',
    Icons.security,
    UciBrowserScreen(initialConfig: 'openclash'),
    group: 'Internet',
  ),
  _Dest(
    'singbox',
    'sing-box',
    'sing-box settings',
    Icons.alt_route,
    UciBrowserScreen(initialConfig: 'sing-box'),
    group: 'Internet',
  ),
  _Dest(
    'adguard',
    'AdGuard Home',
    'AdGuard settings stored on the router',
    Icons.block,
    UciBrowserScreen(initialConfig: 'adguardhome'),
    group: 'Internet',
  ),
  _Dest(
    'ads',
    'RTWRT ADS',
    'Games, AdMob, TikTok, auto-update',
    Icons.do_not_disturb_on,
    UciBrowserScreen(initialConfig: 'rtwrt_ads'),
    group: 'Internet',
  ),
  _Dest(
    'rgb',
    'RGB LED',
    'Mode, timing, and alerts',
    Icons.lightbulb,
    UciBrowserScreen(initialConfig: 'rtwrt_led'),
    group: 'Lights',
  ),
  _Dest(
    'led5g',
    '5G lights',
    'The six lights and their colors',
    Icons.highlight,
    UciBrowserScreen(initialConfig: '5g-led'),
    group: 'Lights',
  ),
  _Dest(
    'phone',
    'Phone port',
    'RJ11 volume, gain, and ring',
    Icons.phone,
    UciBrowserScreen(initialConfig: 'fxs'),
    group: 'Lights',
  ),
  _Dest(
    'dhcp',
    'DHCP and DNS',
    'Leases, hosts, and cache',
    Icons.dns,
    UciBrowserScreen(initialConfig: 'dhcp'),
    group: 'Network',
  ),
  _Dest(
    'system',
    'System',
    'Hostname, time, and password',
    Icons.settings,
    SystemSettingsScreen(),
    group: 'Care',
  ),
  _Dest(
    'logs',
    'Logs',
    'System log',
    Icons.article,
    LogScreen(),
    group: 'Care',
  ),
  _Dest(
    'errors',
    'Error log',
    'What failed, with the router’s own words',
    Icons.report,
    ErrorLogScreen(),
    group: 'Care',
  ),
  _Dest(
    'traffic',
    'Bandwidth',
    'vnstat history',
    Icons.data_usage,
    TrafficScreen(),
    group: 'Care',
  ),
  _Dest(
    'diagnostics',
    'Diagnostics',
    'Ping and lookup',
    Icons.network_ping,
    DiagnosticsScreen(),
    group: 'Care',
  ),
  _Dest(
    'firmware',
    'Firmware',
    'Install a GitHub image, and choose to keep settings',
    Icons.system_update,
    FirmwareScreen(),
    group: 'Care',
  ),
  _Dest(
    'connector',
    'Connector',
    'Install the ubus connector from GitHub',
    Icons.cable,
    ConnectorScreen(),
    group: 'Care',
  ),
];

/// The RTWRT home. Order, pins, and hidden tiles stay on the phone.
class RtwrtHubScreen extends ConsumerStatefulWidget {
  const RtwrtHubScreen({super.key});

  @override
  ConsumerState<RtwrtHubScreen> createState() => _RtwrtHubScreenState();
}

class _RtwrtHubScreenState extends ConsumerState<RtwrtHubScreen> {
  final _store = LayoutStore();
  RtwrtLayout? _layout;
  bool _arrange = false;

  List<String> get _ids => [for (final dest in _destinations) dest.id];

  _Dest _byId(String id) => _destinations.firstWhere((dest) => dest.id == id);

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureConnector());
  }

  Future<void> _ensureConnector() async {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null || !mounted) return;
    final ConnectorResult result;
    try {
      result = await ConnectorInstaller.ensure(
        RtwrtApi(api, session),
        refresh: () => ConnectorInstaller.refreshSession(ref),
      );
    } catch (_) {
      return;
    }
    if (!mounted || result.outcome == ConnectorOutcome.ready) return;
    await showRtwrtResult(
      context,
      action: 'Router connector',
      ok: result.outcome == ConnectorOutcome.installed,
      detail: result.message,
    );
  }

  Future<void> _load() async {
    final layout = await _store.load(_ids);
    if (mounted) setState(() => _layout = layout);
  }

  Future<void> _update(RtwrtLayout layout) async {
    setState(() => _layout = layout);
    await _store.save(layout);
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    return Scaffold(
      appBar: LuciAppBar(
        title: 'RTWRT',
        showBack: true,
        actions: [
          TextButton(
            onPressed: layout == null
                ? null
                : () => setState(() => _arrange = !_arrange),
            child: Text(_arrange ? 'Done' : 'Arrange'),
          ),
        ],
      ),
      body: layout == null
          ? const Center(child: CircularProgressIndicator())
          : _arrange
          ? _editor(layout)
          : _home(layout),
    );
  }

  Widget _home(RtwrtLayout layout) {
    final ids = layout.visible(_ids).toSet();
    if (ids.isEmpty) {
      return const Center(
        child: Text('Every tile is hidden. Use Arrange to put one back.'),
      );
    }
    final pinned = [
      for (final id in layout.pins)
        if (ids.contains(id)) _byId(id),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (pinned.isNotEmpty) ...[
          const LuciSectionHeader('Pinned'),
          LuciHubSection(
            tiles: [for (final dest in pinned) _tile(context, dest)],
          ),
        ],
        for (final group in _groups)
          if (_destinations.any(
            (d) =>
                d.group == group &&
                ids.contains(d.id) &&
                !layout.pins.contains(d.id),
          )) ...[
            LuciSectionHeader(group),
            LuciHubSection(
              tiles: [
                for (final dest in _destinations)
                  if (dest.group == group &&
                      ids.contains(dest.id) &&
                      !layout.pins.contains(dest.id))
                    _tile(context, dest),
              ],
            ),
          ],
      ],
    );
  }

  Widget _tile(BuildContext context, _Dest dest) {
    return LuciHubTile(
      icon: dest.icon,
      title: dest.title,
      subtitle: dest.subtitle,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => dest.page)),
    );
  }

  Widget _editor(RtwrtLayout layout) {
    return Column(
      children: [
        ListTile(
          title: const Text('Drag to reorder. Pin up to four. Hide the rest.'),
          trailing: TextButton(
            onPressed: () => _update(RtwrtLayout.defaults(_ids)),
            child: const Text('Reset'),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: layout.order.length,
            onReorderItem: (from, to) => _update(layout.move(from, to)),
            itemBuilder: (context, index) {
              final id = layout.order[index];
              final dest = _byId(id);
              final hidden = layout.hidden.contains(id);
              return ListTile(
                key: ValueKey(id),
                enabled: !hidden,
                title: Text(dest.title),
                subtitle: Text(hidden ? 'Hidden' : dest.subtitle),
                leading: IconButton(
                  tooltip: layout.pins.contains(id) ? 'Unpin' : 'Pin',
                  onPressed: hidden
                      ? null
                      : () => _update(layout.togglePin(id)),
                  icon: Icon(
                    layout.pins.contains(id)
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                  ),
                ),
                trailing: IconButton(
                  tooltip: hidden ? 'Show' : 'Hide',
                  onPressed: () => _update(layout.toggleHidden(id)),
                  icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
