import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class RepoKeyItem {
  final String path;
  final String fileName;
  final String type; // apk or opkg

  const RepoKeyItem({
    required this.path,
    required this.fileName,
    required this.type,
  });
}

class RepoKeysScreen extends ConsumerStatefulWidget {
  const RepoKeysScreen({super.key});

  @override
  ConsumerState<RepoKeysScreen> createState() => _RepoKeysScreenState();
}

class _RepoKeysScreenState extends ConsumerState<RepoKeysScreen> {
  bool _busy = false;
  List<RepoKeyItem> _keys = [];
  final _keyNameController = TextEditingController();
  final _keyContentController = TextEditingController();
  final _keyUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchKeys());
  }

  @override
  void dispose() {
    _keyNameController.dispose();
    _keyContentController.dispose();
    _keyUrlController.dispose();
    super.dispose();
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _fetchKeys() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final out = await api.shell(r'''
for f in /etc/apk/keys/*; do
  [ -f "$f" ] && echo "APK:$f"
done
for f in /etc/opkg/keys/*; do
  [ -f "$f" ] && echo "OPKG:$f"
done
''');
      if (!mounted) return;
      final lines = out.split('\n');
      final list = <RepoKeyItem>[];
      for (final line in lines) {
        final t = line.trim();
        if (t.startsWith('APK:')) {
          final p = t.substring(4);
          list.add(RepoKeyItem(path: p, fileName: p.split('/').last, type: 'APK'));
        } else if (t.startsWith('OPKG:')) {
          final p = t.substring(5);
          list.add(RepoKeyItem(path: p, fileName: p.split('/').last, type: 'OPKG'));
        }
      }
      setState(() {
        _keys = list;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewKey(RepoKeyItem key) async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final text = await api.shell('cat \'${key.path}\' 2>&1');
      if (!mounted) return;
      setState(() => _busy = false);

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(key.fileName, style: const TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'View Key', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  Future<void> _deleteKey(RepoKeyItem key) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${key.fileName}?'),
        content: const Text('Deleting this key might prevent repository packages from installing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.shell('rm -f \'${key.path}\'');
      if (mounted) {
        setState(() => _busy = false);
        await _fetchKeys();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'Delete Key', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  Future<void> _showAddKeyDialog() async {
    var isApk = true;
    var importFromUrl = false;
    _keyNameController.clear();
    _keyContentController.clear();
    _keyUrlController.clear();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Add Repository Public Key'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('APK (/etc/apk/keys)'),
                      selected: isApk,
                      onSelected: (val) => setDialogState(() => isApk = true),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('OPKG (/etc/opkg/keys)'),
                      selected: !isApk,
                      onSelected: (val) => setDialogState(() => isApk = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyNameController,
                  decoration: const InputDecoration(
                    labelText: 'Key file name',
                    hintText: 'e.g. custom-repo.pem or key.pub',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Download from URL'),
                  value: importFromUrl,
                  onChanged: (val) => setDialogState(() => importFromUrl = val),
                ),
                if (importFromUrl) ...[
                  TextField(
                    controller: _keyUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Public Key URL',
                      hintText: 'https://example.com/signing-key.pem',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _keyContentController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Paste Public Key Content',
                      hintText: '-----BEGIN PUBLIC KEY-----\n...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = _keyNameController.text.trim();
                if (name.isEmpty) return;
                final targetDir = isApk ? '/etc/apk/keys' : '/etc/opkg/keys';
                final fullPath = '$targetDir/$name';
                final api = _client();
                if (api == null) return;

                Navigator.pop(dialogCtx);
                if (!mounted) return;
                setState(() => _busy = true);
                try {
                  if (importFromUrl) {
                    final url = _keyUrlController.text.trim();
                    await api.shell('mkdir -p "$targetDir"; curl -fL -o "$fullPath" \'$url\' || wget -O "$fullPath" \'$url\'');
                  } else {
                    final content = _keyContentController.text;
                    await api.shell('mkdir -p "$targetDir"; cat > "$fullPath" << \'RTWRT_KEY_EOF\'\n$content\nRTWRT_KEY_EOF');
                  }
                  if (mounted) {
                    setState(() => _busy = false);
                    await _fetchKeys();
                  }
                } catch (e) {
                  if (mounted) {
                    setState(() => _busy = false);
                    await showRtwrtResult(context, action: 'Add Key', ok: false, detail: RtwrtApi.explain(e));
                  }
                }
              },
              child: const Text('Save Key'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Repository Public Keys',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Key',
            onPressed: _busy ? null : _showAddKeyDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _fetchKeys,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          const Text(
            'Cryptographic public keys for verifying APK and OPKG repository packages.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          if (_keys.isEmpty && !_busy)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No repository keys found.'))),
          for (final key in _keys)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  Icons.vpn_key,
                  color: key.type == 'APK' ? const Color(0xFF00F0FF) : const Color(0xFF00FF9D),
                ),
                title: Text(key.fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(key.path, style: const TextStyle(fontSize: 11)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility),
                      tooltip: 'View Key',
                      onPressed: () => _viewKey(key),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      tooltip: 'Delete',
                      onPressed: () => _deleteKey(key),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
