import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class PartitionInfo {
  final String filesystem;
  final String size;
  final String used;
  final String available;
  final String usePercent;
  final String mount;
  final double ratio;

  const PartitionInfo({
    required this.filesystem,
    required this.size,
    required this.used,
    required this.available,
    required this.usePercent,
    required this.mount,
    required this.ratio,
  });

  factory PartitionInfo.fromLine(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 6) {
      final pctStr = parts[4].replaceAll('%', '');
      final pct = (double.tryParse(pctStr) ?? 0.0) / 100.0;
      return PartitionInfo(
        filesystem: parts[0],
        size: parts[1],
        used: parts[2],
        available: parts[3],
        usePercent: parts[4],
        mount: parts.sublist(5).join(' '),
        ratio: pct.clamp(0.0, 1.0),
      );
    }
    return const PartitionInfo(
      filesystem: '',
      size: '',
      used: '',
      available: '',
      usePercent: '0%',
      mount: '',
      ratio: 0.0,
    );
  }
}

class StorageManagerScreen extends ConsumerStatefulWidget {
  const StorageManagerScreen({super.key});

  @override
  ConsumerState<StorageManagerScreen> createState() => _StorageManagerScreenState();
}

class _StorageManagerScreenState extends ConsumerState<StorageManagerScreen> {
  bool _busy = false;
  List<PartitionInfo> _partitions = [];
  String _lsblkOutput = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchStorage());
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _fetchStorage() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final out = await api.shell('df -h; echo "===LSBLK==="; lsblk 2>/dev/null || fdisk -l 2>/dev/null');
      if (!mounted) return;
      final parts = out.split('===LSBLK===');
      final dfText = parts.first.trim();
      final lsblkText = parts.length > 1 ? parts[1].trim() : '';

      final lines = dfText.split('\n');
      final list = <PartitionInfo>[];
      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        final p = PartitionInfo.fromLine(line);
        if (p.mount.isNotEmpty) list.add(p);
      }

      setState(() {
        _partitions = list;
        _lsblkOutput = lsblkText;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'Storage', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  Future<void> _unmount(String mountPoint) async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final res = await api.shell('umount "$mountPoint"');
      if (mounted) {
        await showRtwrtResult(
          context,
          action: 'Unmount',
          ok: res.trim().isEmpty,
          detail: res.trim().isEmpty ? 'Successfully unmounted $mountPoint' : res,
        );
        await _fetchStorage();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'Unmount', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlayPart = _partitions.firstWhere(
      (p) => p.mount == '/overlay' || p.mount == '/',
      orElse: () => const PartitionInfo(
        filesystem: '',
        size: '—',
        used: '—',
        available: '—',
        usePercent: '0%',
        mount: '/overlay',
        ratio: 0.0,
      ),
    );

    final tmpPart = _partitions.firstWhere(
      (p) => p.mount == '/tmp',
      orElse: () => const PartitionInfo(
        filesystem: '',
        size: '—',
        used: '—',
        available: '—',
        usePercent: '0%',
        mount: '/tmp',
        ratio: 0.0,
      ),
    );

    return Scaffold(
      appBar: LuciAppBar(
        title: 'Storage & Disk Manager',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _fetchStorage,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          Text('Key Storage Partitions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _storageGaugeCard(
            title: 'Router Storage (/overlay)',
            subtitle: 'Free space for installed APK/IPK packages and configurations',
            info: overlayPart,
            color: const Color(0xFF00F0FF),
          ),
          const SizedBox(height: 12),
          _storageGaugeCard(
            title: 'RAM Disk (/tmp)',
            subtitle: 'Temporary memory buffer for firmware downloads and logs',
            info: tmpPart,
            color: const Color(0xFF00FF9D),
          ),
          const SizedBox(height: 16),
          Text('All Mounted Filesystems', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final p in _partitions)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  p.mount,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${p.filesystem} • Used: ${p.used} / ${p.size} (${p.usePercent})',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: p.mount.startsWith('/mnt/') || p.mount.startsWith('/media/')
                    ? OutlinedButton(
                        onPressed: _busy ? null : () => _unmount(p.mount),
                        child: const Text('Unmount'),
                      )
                    : Text(
                        '${p.available} Free',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          const SizedBox(height: 16),
          if (_lsblkOutput.isNotEmpty)
            ExpansionTile(
              title: const Text('Block Devices (lsblk / fdisk)'),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.black26,
                  child: SelectableText(
                    _lsblkOutput,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _storageGaugeCard({
    required String title,
    required String subtitle,
    required PartitionInfo info,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(
                  info.usePercent,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: info.ratio,
                minHeight: 10,
                backgroundColor: Colors.white12,
                color: color,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Used: ${info.used}', style: const TextStyle(fontSize: 12)),
                Text('Available: ${info.available}', style: const TextStyle(fontSize: 12)),
                Text('Total: ${info.size}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
