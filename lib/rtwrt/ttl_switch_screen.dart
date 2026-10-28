import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class TtlPreset {
  final int ttl;
  final String title;
  final String description;

  const TtlPreset({
    required this.ttl,
    required this.title,
    required this.description,
  });
}

class TtlSwitchScreen extends ConsumerStatefulWidget {
  const TtlSwitchScreen({super.key});

  @override
  ConsumerState<TtlSwitchScreen> createState() => _TtlSwitchScreenState();
}

class _TtlSwitchScreenState extends ConsumerState<TtlSwitchScreen> {
  bool _busy = false;
  int _currentTtl = 64;
  bool _enabled = true;
  final _customTtlController = TextEditingController();

  static const _presets = [
    TtlPreset(
      ttl: 64,
      title: 'TTL 64',
      description: 'Trick the carrier when your Laptop/PC connects directly to your phone hotspot.',
    ),
    TtlPreset(
      ttl: 65,
      title: 'TTL 65',
      description: 'Trick the carrier when your Router connects to your phone hotspot.',
    ),
    TtlPreset(
      ttl: 128,
      title: 'TTL 128',
      description: 'Tell the carrier it is a normal Windows PC browsing standard data.',
    ),
    TtlPreset(
      ttl: 129,
      title: 'TTL 129',
      description: 'Trick the carrier into seeing a Windows PC when using a Router in between.',
    ),
    TtlPreset(
      ttl: 255,
      title: 'TTL 255',
      description: 'Tell the carrier a Network Router is sharing the internet (triggers hotspot blocks).',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchTtl());
  }

  @override
  void dispose() {
    _customTtlController.dispose();
    super.dispose();
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _fetchTtl() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final out = await api.shell(r'''
echo "TTL=$(uci -q get qmodem_ttl.main.ttl)"
echo "ENABLE=$(uci -q get qmodem_ttl.main.enable)"
''');
      if (!mounted) return;
      final ttlMatch = RegExp(r'^TTL=(.*)$', multiLine: true).firstMatch(out);
      final enMatch = RegExp(r'^ENABLE=(.*)$', multiLine: true).firstMatch(out);

      final val = int.tryParse(ttlMatch?.group(1)?.trim() ?? '') ?? 64;
      final en = enMatch?.group(1)?.trim() != '0';

      setState(() {
        _currentTtl = val;
        _enabled = en;
        _customTtlController.text = val.toString();
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyTtl(int ttlVal) async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final script = '''
uci set qmodem_ttl.main.enable='1'
uci set qmodem_ttl.main.ttl='$ttlVal'
uci commit qmodem_ttl
/etc/init.d/qmodem_ttl restart
echo "TTL updated to $ttlVal"
''';
      final res = await api.shell(script);
      if (mounted) {
        setState(() {
          _currentTtl = ttlVal;
          _enabled = true;
          _customTtlController.text = ttlVal.toString();
          _busy = false;
        });
        await showRtwrtResult(
          context,
          action: 'TTL Switch',
          ok: true,
          detail: 'Hotspot bypass set to TTL $ttlVal.\n${res.trim()}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'TTL Switch', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  Future<void> _toggleEnable(bool en) async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final val = en ? '1' : '0';
      final script = '''
uci set qmodem_ttl.main.enable='$val'
uci commit qmodem_ttl
${en ? '/etc/init.d/qmodem_ttl restart' : '/etc/init.d/qmodem_ttl stop'}
''';
      await api.shell(script);
      if (mounted) {
        setState(() {
          _enabled = en;
          _busy = false;
        });
        await showRtwrtResult(
          context,
          action: 'TTL Service',
          ok: true,
          detail: en ? 'TTL modification active.' : 'TTL modification disabled (passthrough).',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'TTL Service', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'TTL Switch',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _fetchTtl,
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
                          Icon(Icons.alt_route, color: Color(0xFF00F0FF)),
                          SizedBox(width: 8),
                          Text('Active TTL Policy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FF9D).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF00FF9D)),
                        ),
                        child: Text(
                          _enabled ? 'TTL $_currentTtl ACTIVE' : 'PASSTHROUGH',
                          style: const TextStyle(
                            color: Color(0xFF00FF9D),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Carrier Hotspot TTL Modification'),
                    subtitle: const Text('Applies mangle rules to outgoing packets on cellular WAN'),
                    value: _enabled,
                    onChanged: _busy ? null : _toggleEnable,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Hotspot Bypass Presets', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final preset in _presets)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: _enabled && _currentTtl == preset.ttl
                    ? const BorderSide(color: Color(0xFF00FF9D), width: 2)
                    : BorderSide.none,
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: (_enabled && _currentTtl == preset.ttl
                          ? const Color(0xFF00FF9D)
                          : const Color(0xFF00F0FF))
                      .withValues(alpha: 0.15),
                  child: Text(
                    '${preset.ttl}',
                    style: TextStyle(
                      color: _enabled && _currentTtl == preset.ttl
                          ? const Color(0xFF00FF9D)
                          : const Color(0xFF00F0FF),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                title: Text(preset.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(preset.description, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ),
                trailing: _enabled && _currentTtl == preset.ttl
                    ? const Icon(Icons.check_circle, color: Color(0xFF00FF9D))
                    : OutlinedButton(
                        onPressed: _busy ? null : () => _applyTtl(preset.ttl),
                        child: const Text('Apply'),
                      ),
                onTap: _busy ? null : () => _applyTtl(preset.ttl),
              ),
            ),
          const SizedBox(height: 16),
          Text('Custom TTL Value', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customTtlController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Enter custom TTL (1 - 255)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        final val = int.tryParse(_customTtlController.text.trim()) ?? 0;
                        if (val >= 1 && val <= 255) {
                          _applyTtl(val);
                        } else {
                          showRtwrtResult(
                            context,
                            action: 'Custom TTL',
                            ok: false,
                            detail: 'Enter a valid TTL between 1 and 255.',
                          );
                        }
                      },
                child: const Text('Apply Custom'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
