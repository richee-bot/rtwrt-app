import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class CpuModeScreen extends ConsumerStatefulWidget {
  const CpuModeScreen({super.key});

  @override
  ConsumerState<CpuModeScreen> createState() => _CpuModeScreenState();
}

class _CpuModeScreenState extends ConsumerState<CpuModeScreen> {
  bool _busy = false;
  String _activeGov = '';
  String _availableGovs = '';
  String _curFreq = '';
  String _minFreq = '';
  String _maxFreq = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCpuState());
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _fetchCpuState() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final out = await api.shell(r'''
echo "GOV=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor 2>/dev/null)"
echo "AVAIL=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_governors 2>/dev/null)"
echo "CUR=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null)"
echo "MIN=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 2>/dev/null)"
echo "MAX=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 2>/dev/null)"
''');
      if (!mounted) return;
      final govMatch = RegExp(r'^GOV=(.*)$', multiLine: true).firstMatch(out);
      final availMatch = RegExp(r'^AVAIL=(.*)$', multiLine: true).firstMatch(out);
      final curMatch = RegExp(r'^CUR=(.*)$', multiLine: true).firstMatch(out);
      final minMatch = RegExp(r'^MIN=(.*)$', multiLine: true).firstMatch(out);
      final maxMatch = RegExp(r'^MAX=(.*)$', multiLine: true).firstMatch(out);

      String fmt(String? val) {
        if (val == null || val.trim().isEmpty) return '—';
        final khz = int.tryParse(val.trim()) ?? 0;
        if (khz <= 0) return '—';
        return '${(khz / 1000).toStringAsFixed(0)} MHz (${(khz / 1000000).toStringAsFixed(2)} GHz)';
      }

      setState(() {
        _activeGov = govMatch?.group(1)?.trim() ?? 'performance';
        _availableGovs = availMatch?.group(1)?.trim() ?? 'performance schedutil';
        _curFreq = fmt(curMatch?.group(1));
        _minFreq = fmt(minMatch?.group(1));
        _maxFreq = fmt(maxMatch?.group(1));
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setGovernor(String modeKey, String label) async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      // Map modeKey to valid governor
      // If LowPower: try powersave, if not available in kernel fallback to schedutil
      String targetGov = modeKey;
      if (modeKey == 'powersave' && !_availableGovs.contains('powersave')) {
        targetGov = 'schedutil';
      }

      final script = '''
for p in /sys/devices/system/cpu/cpufreq/policy*; do
  [ -d "\$p" ] && echo "$targetGov" > "\$p/scaling_governor" 2>/dev/null
done
# Persist to /etc/rc.local if present
sed -i '/scaling_governor/d' /etc/rc.local 2>/dev/null
sed -i 's/^exit 0/for p in \\/sys\\/devices\\/system\\/cpu\\/cpufreq\\/policy*; do echo "$targetGov" > "\$p\\/scaling_governor"; done\\nexit 0/' /etc/rc.local 2>/dev/null
echo "Switched to $targetGov"
''';
      final res = await api.shell(script);
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(
          context,
          action: 'CPU Mode',
          ok: true,
          detail: 'CPU scaled to $label ($targetGov).\n${res.trim()}',
        );
        await _fetchCpuState();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'CPU Mode', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'CPU Governor & Scaling',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _fetchCpuState,
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
                    children: const [
                      Icon(Icons.speed, color: Color(0xFF00F0FF)),
                      SizedBox(width: 8),
                      Text(
                        'CPU Frequency & Live State',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _metric('Active Governor', _activeGov.toUpperCase()),
                      _metric('Current Clock', _curFreq),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _metric('Min Frequency', _minFreq),
                      _metric('Max Frequency', _maxFreq),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Available Kernel Governors: $_availableGovs',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Select CPU Scaling Mode', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _modeTile(
            title: 'LowPower (Powersave)',
            subtitle: 'Reduces CPU clock speed and minimizes power draw and thermals.',
            icon: Icons.energy_savings_leaf,
            color: const Color(0xFF00FF9D),
            modeKey: 'powersave',
            isSelected: _activeGov == 'powersave',
          ),
          const SizedBox(height: 8),
          _modeTile(
            title: 'Schedutil (Balanced Dynamic)',
            subtitle: 'Dynamically scales frequency based on scheduler load and network demands.',
            icon: Icons.tune,
            color: const Color(0xFF00F0FF),
            modeKey: 'schedutil',
            isSelected: _activeGov == 'schedutil',
          ),
          const SizedBox(height: 8),
          _modeTile(
            title: 'Performance (Maximum Speed)',
            subtitle: 'Locks CPU cores to maximum clock speed for lowest latency and peak throughput.',
            icon: Icons.bolt,
            color: Colors.amberAccent,
            modeKey: 'performance',
            isSelected: _activeGov == 'performance',
          ),
        ],
      ),
    );
  }

  Widget _modeTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String modeKey,
    required bool isSelected,
  }) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected ? BorderSide(color: color, width: 2) : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'ACTIVE',
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: color)
            : OutlinedButton(
                onPressed: _busy ? null : () => _setGovernor(modeKey, title),
                child: const Text('Apply'),
              ),
        onTap: _busy ? null : () => _setGovernor(modeKey, title),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}
