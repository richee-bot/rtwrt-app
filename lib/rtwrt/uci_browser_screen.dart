import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

/// Every UCI config on the router, edited and committed from the phone.
class UciBrowserScreen extends ConsumerStatefulWidget {
  const UciBrowserScreen({super.key, this.initialConfig});

  final String? initialConfig;

  @override
  ConsumerState<UciBrowserScreen> createState() => _UciBrowserScreenState();
}

class _UciBrowserScreenState extends ConsumerState<UciBrowserScreen> {
  List<String> _configs = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialConfig != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => UciConfigScreen(config: widget.initialConfig!),
          ),
        );
      });
      return;
    }
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
      final list = await RtwrtApi(api, session).configs();
      if (!mounted) return;
      setState(() {
        _configs = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = RtwrtApi.explain(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const LuciAppBar(title: 'Router configs', showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : ListView.builder(
              itemCount: _configs.length,
              itemBuilder: (context, i) {
                final name = _configs[i];
                return ListTile(
                  title: Text(name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UciConfigScreen(config: name),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class UciConfigScreen extends ConsumerStatefulWidget {
  const UciConfigScreen({super.key, required this.config});

  final String config;

  @override
  ConsumerState<UciConfigScreen> createState() => _UciConfigScreenState();
}

class _UciConfigScreenState extends ConsumerState<UciConfigScreen> {
  Map<String, Map<String, dynamic>> _sections = {};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return;
    try {
      final values = await RtwrtApi(api, session).uciAll(widget.config);
      if (!mounted) return;
      setState(() {
        _sections = values;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = RtwrtApi.explain(e);
      });
    }
  }

  String _label(String id, Map<String, dynamic> section) {
    for (final key in ['ssid', 'name', 'domain', 'interface', 'hostname']) {
      final value = section[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(title: widget.config, showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : ListView(
              children: [
                for (final entry in _sections.entries)
                  ListTile(
                    title: Text(_label(entry.key, entry.value)),
                    subtitle: Text(
                      '${entry.value['.type'] ?? 'section'} · ${entry.key}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => UciSectionScreen(
                            config: widget.config,
                            section: entry.key,
                            values: entry.value,
                          ),
                        ),
                      );
                      if (mounted) await _load();
                    },
                  ),
              ],
            ),
    );
  }
}

const _fieldNames = {
  'enabled': 'Turn on',
  'ssid': 'Wi-Fi name',
  'key': 'Password',
  'encryption': 'Security',
  'channel': 'Channel',
  'apn': 'APN',
  'pdp_type': 'IP type',
  'hostname': 'Name',
  'ipaddr': 'IP address',
  'netmask': 'Subnet mask',
  'gateway': 'Gateway',
  'dns': 'DNS',
  'password': 'Password',
  'port': 'Port',
  'mode': 'Mode',
  'ttl': 'TTL',
  'disabled': 'Disabled',
  'device': 'Device',
  'proto': 'Protocol',
  'network': 'Network',
};

class UciSectionScreen extends ConsumerStatefulWidget {
  const UciSectionScreen({
    super.key,
    required this.config,
    required this.section,
    required this.values,
  });

  final String config;
  final String section;
  final Map<String, dynamic> values;

  @override
  ConsumerState<UciSectionScreen> createState() => _UciSectionScreenState();
}

class _UciSectionScreenState extends ConsumerState<UciSectionScreen> {
  late final Map<String, TextEditingController> _fields;
  late final Set<String> _lists;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lists = {};
    _fields = {};
    for (final entry in widget.values.entries) {
      if (entry.key.startsWith('.')) continue;
      if (entry.value is List) {
        _lists.add(entry.key);
        _fields[entry.key] = TextEditingController(
          text: (entry.value as List).map((e) => e.toString()).join(', '),
        );
      } else {
        _fields[entry.key] = TextEditingController(
          text: entry.value?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _nice(String key) => _fieldNames[key] ?? key;

  /// Closed lists for fields whose legal values are known. The live value is
  /// kept in the list when the router uses something outside it.
  List<String>? _knownChoices(String key) {
    final config = widget.config;
    if (key == 'encryption' && config == 'wireless') {
      return ['none', 'psk2', 'sae', 'sae-mixed', 'owe', 'psk', 'psk-mixed'];
    }
    if (key == 'htmode' && config == 'wireless') {
      return [
        'HE20',
        'HE40',
        'HE80',
        'HE160',
        'VHT20',
        'VHT40',
        'VHT80',
        'VHT160',
        'HT20',
        'HT40',
        'NOHT',
      ];
    }
    if (key == 'channel' && config == 'wireless') {
      return [
        'auto',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '10',
        '11',
        '36',
        '40',
        '44',
        '48',
        '52',
        '56',
        '60',
        '64',
        '100',
        '104',
        '108',
        '112',
        '116',
        '120',
        '124',
        '128',
        '132',
        '136',
        '140',
        '144',
        '149',
        '153',
        '157',
        '161',
        '165',
      ];
    }
    if (key == 'hwmode' && config == 'wireless') {
      return ['11g', '11a', '11n', '11ac', '11ax', '11be'];
    }
    if (key == 'band' && config == 'wireless') {
      return ['2g', '5g', '6g'];
    }
    if (key == 'proto' && config == 'network') {
      return ['static', 'dhcp', 'dhcpv6', 'pppoe', 'none', 'qmi', 'ncm', 'mbim'];
    }
    if (key == 'pdp_type') {
      return ['ipv4', 'ipv6', 'ipv4v6'];
    }
    if (key == 'mode' && (config == 'rtwrt_led' || config == 'rtwrt_rgb_led')) {
      return ['cycle_all', 'normal', 'stealth'];
    }
    if (key == 'dial_mode' && config.startsWith('qmodem')) {
      return ['qmi', 'mbim', 'ncm', 'ecm', 'rndis'];
    }
    if ((key == 'auth' || key == 'auth_type') && config.startsWith('qmodem')) {
      return ['none', 'pap', 'chap', 'both'];
    }
    return null;
  }

  List<String> _options(String key) {
    final known = _knownChoices(key);
    if (known == null) return const [];
    final current = _fields[key]?.text ?? '';
    if (current.isNotEmpty && !known.contains(current)) {
      return [current, ...known];
    }
    return known;
  }

  bool _secret(String key) {
    final name = key.toLowerCase();
    return name.contains('pass') ||
        name.contains('secret') ||
        name.contains('token') ||
        name == 'key';
  }

  bool _flag(String key) {
    final current = widget.values[key]?.toString();
    if (current != '0' && current != '1') return false;
    final name = key.toLowerCase();
    const exact = {
      'enabled',
      'disabled',
      'enable',
      'enable_dial',
      'sms_notify',
      'offline_notify',
      'auto_update',
      'hidden',
      'isolate',
    };
    if (exact.contains(name)) return true;
    return name.startsWith('enable') ||
        name.startsWith('block_') ||
        name.endsWith('_enabled') ||
        name.startsWith('is_');
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) {
      await showRtwrtResult(
        context,
        action: 'Save ${widget.config}',
        ok: false,
        detail: 'Not connected to the router.',
      );
      return;
    }
    setState(() => _saving = true);
    final values = <String, Object>{};
    for (final entry in _fields.entries) {
      final text = entry.value.text.trim();
      if (_lists.contains(entry.key)) {
        values[entry.key] = [
          for (final part in text.split(','))
            if (part.trim().isNotEmpty) part.trim(),
        ];
      } else {
        values[entry.key] = text;
      }
    }
    try {
      await RtwrtApi(
        api,
        session,
      ).uciSet(widget.config, widget.section, values);
      if (!mounted) return;
      await showRtwrtResult(
        context,
        action: 'Save ${widget.config}',
        ok: true,
        detail: 'Saved.',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      await showRtwrtResult(
        context,
        action: 'Save ${widget.config}',
        ok: false,
        detail: RtwrtApi.explain(e),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _choice(String key, List<String> options) {
    final current = _fields[key]!.text;
    final selected = options.contains(current) ? current : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$key|$current'),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _nice(key),
          helperText: key == _nice(key) ? null : key,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() => _fields[key]!.text = value);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = _fields.keys.toList()..sort();
    return Scaffold(
      appBar: LuciAppBar(
        title: widget.section,
        showBack: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving' : 'Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Change what you need, then tap Save. '
            '${widget.config} / ${widget.values['.type'] ?? 'section'}',
          ),
          const SizedBox(height: 12),
          for (final key in keys)
            _flag(key)
                ? SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_nice(key)),
                    value: _fields[key]!.text == '1',
                    onChanged: (on) => setState(() {
                      _fields[key]!.text = on ? '1' : '0';
                    }),
                  )
                : _options(key).isNotEmpty
                ? _choice(key, _options(key))
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _fields[key],
                      obscureText: _secret(key),
                      decoration: InputDecoration(
                        labelText: _nice(key),
                        helperText: key == _nice(key) ? null : key,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}
