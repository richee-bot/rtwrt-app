import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class SystemInfoScreen extends ConsumerStatefulWidget {
  const SystemInfoScreen({super.key});

  @override
  ConsumerState<SystemInfoScreen> createState() => _SystemInfoScreenState();
}

class _SystemInfoScreenState extends ConsumerState<SystemInfoScreen> {
  bool _busy = false;
  String _model = '';
  String _release = '';
  String _kernel = '';
  String _arch = '';
  String _cpu = '';
  String _cpuFreq = '';
  String _memory = '';
  String _uptime = '';
  String _rawOutput = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchInfo());
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _fetchInfo() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final out = await api.shell(r'''
echo "MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || cat /proc/device-tree/model 2>/dev/null)"
echo "RELEASE=$(cat /etc/openwrt_release 2>/dev/null | grep DISTRIB_DESCRIPTION | cut -d= -f2 | tr -d '\"')"
echo "KERNEL=$(uname -r)"
echo "ARCH=$(uname -m)"
echo "UPTIME=$(uptime)"
echo "CPU=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 || grep -m1 'Processor' /proc/cpuinfo 2>/dev/null | cut -d: -f2)"
echo "FREQ=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null || echo '')"
echo "MEM=$(free -h 2>/dev/null || free -m 2>/dev/null)"
''');
      if (!mounted) return;
      final modelMatch = RegExp(r'^MODEL=(.*)$', multiLine: true).firstMatch(out);
      final relMatch = RegExp(r'^RELEASE=(.*)$', multiLine: true).firstMatch(out);
      final kernMatch = RegExp(r'^KERNEL=(.*)$', multiLine: true).firstMatch(out);
      final archMatch = RegExp(r'^ARCH=(.*)$', multiLine: true).firstMatch(out);
      final upMatch = RegExp(r'^UPTIME=(.*)$', multiLine: true).firstMatch(out);
      final cpuMatch = RegExp(r'^CPU=(.*)$', multiLine: true).firstMatch(out);
      final freqMatch = RegExp(r'^FREQ=(.*)$', multiLine: true).firstMatch(out);

      final memIndex = out.indexOf('MEM=');
      final memText = memIndex != -1 ? out.substring(memIndex + 4).trim() : '';

      String freqFormatted = '';
      if (freqMatch != null && freqMatch.group(1)!.trim().isNotEmpty) {
        final khz = int.tryParse(freqMatch.group(1)!.trim()) ?? 0;
        if (khz > 0) {
          freqFormatted = '${(khz / 1000).toStringAsFixed(0)} MHz (${(khz / 1000000).toStringAsFixed(2)} GHz)';
        }
      }

      setState(() {
        _model = modelMatch?.group(1)?.trim() ?? 'Arcadyan AW1000';
        if (_model.isEmpty) _model = 'Arcadyan AW1000 (RTWRT)';
        _release = relMatch?.group(1)?.trim() ?? 'OpenWrt 25.12';
        _kernel = kernMatch?.group(1)?.trim() ?? '';
        _arch = archMatch?.group(1)?.trim() ?? 'aarch64';
        _uptime = upMatch?.group(1)?.trim() ?? '';
        _cpu = cpuMatch?.group(1)?.trim() ?? 'Qualcomm IPQ807x';
        if (_cpu.isEmpty) _cpu = 'ARMv8 Cortex-A53 (4 Cores)';
        _cpuFreq = freqFormatted;
        _memory = memText;
        _rawOutput = out;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'System Info', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'System Info',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _fetchInfo,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          _infoCard(
            title: 'Device & Hardware',
            icon: Icons.router,
            items: [
              MapEntry('Model', _model),
              MapEntry('Architecture', _arch),
              MapEntry('CPU Model', _cpu),
              if (_cpuFreq.isNotEmpty) MapEntry('Current Frequency', _cpuFreq),
            ],
          ),
          const SizedBox(height: 12),
          _infoCard(
            title: 'Firmware & Operating System',
            icon: Icons.memory,
            items: [
              MapEntry('Release', _release),
              MapEntry('Kernel', _kernel),
              MapEntry('System Load / Uptime', _uptime),
            ],
          ),
          const SizedBox(height: 12),
          if (_memory.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.pie_chart, color: Color(0xFF00FF9D)),
                        SizedBox(width: 8),
                        Text(
                          'Memory & Swap Usage',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _memory,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Raw System Info'),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Colors.black26,
                child: SelectableText(
                  _rawOutput,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required IconData icon,
    required List<MapEntry<String, String>> items,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF00F0FF)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(height: 20),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        item.key,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        item.value.isEmpty ? '—' : item.value,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
