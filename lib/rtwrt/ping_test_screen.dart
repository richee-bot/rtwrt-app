import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class PingTarget {
  final String name;
  final String host;
  final bool isIpv6;

  const PingTarget(this.name, this.host, {this.isIpv6 = false});
}

class PingResult {
  final String target;
  final bool ok;
  final String min;
  final String avg;
  final String max;
  final String loss;
  final String raw;

  const PingResult({
    required this.target,
    required this.ok,
    this.min = '—',
    this.avg = '—',
    this.max = '—',
    this.loss = '0%',
    required this.raw,
  });
}

class PingTestScreen extends ConsumerStatefulWidget {
  const PingTestScreen({super.key});

  @override
  ConsumerState<PingTestScreen> createState() => _PingTestScreenState();
}

class _PingTestScreenState extends ConsumerState<PingTestScreen> {
  final _customHost = TextEditingController(text: '1.1.1.1');
  bool _busy = false;
  bool _testingPresets = false;
  final Map<String, PingResult> _presetResults = {};
  PingResult? _customResult;

  static const _presets = [
    PingTarget('Cloudflare IPv4', '1.1.1.1'),
    PingTarget('Google IPv4', '8.8.8.8'),
    PingTarget('Google IPv6', '2001:4860:4860::8888', isIpv6: true),
    PingTarget('Cloudflare IPv6', '2606:4700:4700::1111', isIpv6: true),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAllPresets());
  }

  @override
  void dispose() {
    _customHost.dispose();
    super.dispose();
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<PingResult> _pingHost(RtwrtApi api, String host, {bool isIpv6 = false}) async {
    final cleanHost = host.replaceAll("'", '').trim();
    final cmd = isIpv6
        ? 'ping -6 -c 3 -W 2 \'$cleanHost\' 2>&1'
        : 'ping -c 3 -W 2 \'$cleanHost\' 2>&1';
    final out = await api.shell(cmd);
    final ok = out.contains('bytes from') && !out.contains('100% packet loss');
    final lossMatch = RegExp(r'([0-9]+)% packet loss').firstMatch(out);
    final rttMatch = RegExp(r'min/avg/max(?:/mdev)? = ([0-9.]+)/([0-9.]+)/([0-9.]+)').firstMatch(out);

    return PingResult(
      target: cleanHost,
      ok: ok,
      min: rttMatch != null ? '${rttMatch.group(1)} ms' : '—',
      avg: rttMatch != null ? '${rttMatch.group(2)} ms' : '—',
      max: rttMatch != null ? '${rttMatch.group(3)} ms' : '—',
      loss: lossMatch != null ? '${lossMatch.group(1)}%' : (ok ? '0%' : '100%'),
      raw: out,
    );
  }

  Future<void> _runAllPresets() async {
    final api = _client();
    if (api == null) return;
    setState(() => _testingPresets = true);
    for (final preset in _presets) {
      try {
        final res = await _pingHost(api, preset.host, isIpv6: preset.isIpv6);
        if (!mounted) return;
        setState(() => _presetResults[preset.name] = res);
      } catch (_) {}
    }
    if (mounted) setState(() => _testingPresets = false);
  }

  Future<void> _runCustomPing() async {
    final api = _client();
    if (api == null) return;
    final host = _customHost.text.trim();
    if (host.isEmpty) return;
    final isV6 = host.contains(':');
    setState(() => _busy = true);
    try {
      final res = await _pingHost(api, host, isIpv6: isV6);
      if (mounted) {
        setState(() {
          _customResult = res;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ipv4Up = (_presetResults['Cloudflare IPv4']?.ok ?? false) ||
        (_presetResults['Google IPv4']?.ok ?? false);
    final ipv6Up = (_presetResults['Google IPv6']?.ok ?? false) ||
        (_presetResults['Cloudflare IPv6']?.ok ?? false);

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Ping & Internet Status',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Run Ping Probes',
            onPressed: _testingPresets ? null : _runAllPresets,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_testingPresets || _busy) const LinearProgressIndicator(),
          Row(
            children: [
              Expanded(
                child: _statusBadge(
                  title: 'IPv4 Internet',
                  isUp: ipv4Up,
                  avgLatency: _presetResults['Cloudflare IPv4']?.avg ?? '—',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statusBadge(
                  title: 'IPv6 Internet',
                  isUp: ipv6Up,
                  avgLatency: _presetResults['Google IPv6']?.avg ?? '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Internet Latency Probes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final preset in _presets) ...[
            _presetCard(preset),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          Text('Custom Ping Host', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customHost,
                  decoration: const InputDecoration(
                    labelText: 'Host or IP address',
                    hintText: 'e.g. 1.1.1.1 or google.com',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _runCustomPing,
                child: const Text('Ping'),
              ),
            ],
          ),
          if (_customResult != null) ...[
            const SizedBox(height: 12),
            _resultCard('Result for ${_customResult!.target}', _customResult!),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge({required String title, required bool isUp, required String avgLatency}) {
    final color = isUp ? const Color(0xFF00FF9D) : Colors.redAccent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isUp ? Icons.check_circle : Icons.error, color: color, size: 20),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isUp ? 'Connected' : 'Unreachable',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (isUp)
              Text(
                'RTT: $avgLatency',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _presetCard(PingTarget target) {
    final res = _presetResults[target.name];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              res == null
                  ? Icons.hourglass_top
                  : (res.ok ? Icons.cloud_done : Icons.cloud_off),
              color: res == null
                  ? Colors.white54
                  : (res.ok ? const Color(0xFF00FF9D) : Colors.redAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    target.host,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (res != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    res.avg,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    'loss: ${res.loss}',
                    style: TextStyle(
                      color: res.loss == '0%' ? Colors.white60 : Colors.redAccent,
                      fontSize: 11,
                    ),
                  ),
                ],
              )
            else
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(String title, PingResult res) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metric('Min RTT', res.min),
                _metric('Avg RTT', res.avg),
                _metric('Max RTT', res.max),
                _metric('Loss', res.loss),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.black26,
              child: SelectableText(
                res.raw.trim(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
