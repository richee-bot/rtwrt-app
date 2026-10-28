import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class BandixDevice {
  final String ip;
  final String mac;
  final String host;
  final int rxRate; // bytes/sec
  final int txRate; // bytes/sec
  final int totalRxBytes;
  final int totalTxBytes;

  const BandixDevice({
    required this.ip,
    required this.mac,
    required this.host,
    required this.rxRate,
    required this.txRate,
    required this.totalRxBytes,
    required this.totalTxBytes,
  });

  factory BandixDevice.fromJson(Map<String, dynamic> json) {
    return BandixDevice(
      ip: json['ip4']?.toString() ?? '',
      mac: json['mac']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      rxRate: (json['t_rx_r'] as num?)?.toInt() ?? 0,
      txRate: (json['t_tx_r'] as num?)?.toInt() ?? 0,
      totalRxBytes: (json['t_rx_b'] as num?)?.toInt() ?? 0,
      totalTxBytes: (json['t_tx_b'] as num?)?.toInt() ?? 0,
    );
  }
}

class BandixScreen extends ConsumerStatefulWidget {
  const BandixScreen({super.key});

  @override
  ConsumerState<BandixScreen> createState() => _BandixScreenState();
}

class _BandixScreenState extends ConsumerState<BandixScreen> {
  bool _busy = false;
  String _version = '';
  List<BandixDevice> _devices = [];
  String _vnstatOutput = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchBandix());
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSec >= 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '$bytesPerSec B/s';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  Future<void> _fetchBandix() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final out = await api.shell(r'''
echo "===VERSION==="
ubus call luci.bandix getVersion 2>/dev/null || echo "{}"
echo "===STATUS==="
ubus call luci.bandix getStatus 2>/dev/null || echo "{}"
echo "===VNSTAT==="
vnstat -i wwan0 -tr 1 2>/dev/null || vnstat -i wwan0 2>/dev/null || echo "vnstat unavailable"
''');
      if (!mounted) return;
      final verPart = out.split('===VERSION===').last.split('===STATUS===').first.trim();
      final statPart = out.split('===STATUS===').last.split('===VNSTAT===').first.trim();
      final vnstatPart = out.split('===VNSTAT===').last.trim();

      String verStr = 'Bandix eBPF';
      try {
        final vJson = jsonDecode(verPart);
        if (vJson is Map && vJson['bandix_version'] != null) {
          verStr = 'Bandix v${vJson['bandix_version']}';
        }
      } catch (_) {}

      final devList = <BandixDevice>[];
      try {
        final sJson = jsonDecode(statPart);
        if (sJson is Map && sJson['d'] is List) {
          for (final item in sJson['d']) {
            if (item is Map) {
              devList.add(BandixDevice.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
      } catch (_) {}

      // Sort by active rxRate descending
      devList.sort((a, b) => (b.rxRate + b.txRate).compareTo(a.rxRate + a.txRate));

      setState(() {
        _version = verStr;
        _devices = devList;
        _vnstatOutput = vnstatPart;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restartBandix() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.shell('/etc/init.d/bandix restart');
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(
          context,
          action: 'Restart Bandix',
          ok: true,
          detail: 'Bandix eBPF monitoring service restarted.',
        );
        await _fetchBandix();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'Restart Bandix', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  Future<void> _clearTrafficData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Bandix Traffic Data?'),
        content: const Text('This resets traffic statistics accumulators for all client devices.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.shell('ubus call luci.bandix clearData 2>/dev/null || rm -rf /usr/share/bandix/metrics/*');
      if (mounted) {
        setState(() => _busy = false);
        await _fetchBandix();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'Clear Data', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Bandwidth & Bandix Monitor',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _fetchBandix,
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
                          Icon(Icons.data_thresholding, color: Color(0xFF00F0FF)),
                          SizedBox(width: 8),
                          Text('Bandix eBPF Traffic Engine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                          _version.isNotEmpty ? _version : 'ACTIVE',
                          style: const TextStyle(color: Color(0xFF00FF9D), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Restart Service'),
                        onPressed: _busy ? null : _restartBandix,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                        label: const Text('Clear Stats', style: TextStyle(color: Colors.redAccent)),
                        onPressed: _busy ? null : _clearTrafficData,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Connected Devices (${_devices.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Live Rates',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_devices.isEmpty && !_busy)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No devices monitored yet.'))),
          for (final dev in _devices)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          dev.host.isNotEmpty ? dev.host : (dev.ip.isNotEmpty ? dev.ip : dev.mac),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.arrow_downward, size: 14, color: Color(0xFF00FF9D)),
                            Text(
                              _formatSpeed(dev.rxRate),
                              style: const TextStyle(
                                color: Color(0xFF00FF9D),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_upward, size: 14, color: Color(0xFF00F0FF)),
                            Text(
                              _formatSpeed(dev.txRate),
                              style: const TextStyle(
                                color: Color(0xFF00F0FF),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dev.ip} • ${dev.mac}',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Total: ↓ ${_formatBytes(dev.totalRxBytes)}  ↑ ${_formatBytes(dev.totalTxBytes)}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (_vnstatOutput.isNotEmpty)
            ExpansionTile(
              title: const Text('Cellular Interface Traffic (vnstat)'),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.black26,
                  child: SelectableText(
                    _vnstatOutput,
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
