import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:path_provider/path_provider.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class FileEntry {
  final String name;
  final bool isDir;
  final String permissions;
  final String size;
  final String date;

  const FileEntry({
    required this.name,
    required this.isDir,
    required this.permissions,
    required this.size,
    required this.date,
  });

  factory FileEntry.fromLs(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 9) {
      final perms = parts[0];
      final isDir = perms.startsWith('d');
      final size = parts[4];
      final date = '${parts[5]} ${parts[6]} ${parts[7]}';
      final name = parts.sublist(8).join(' ');
      return FileEntry(
        name: name,
        isDir: isDir,
        permissions: perms,
        size: size,
        date: date,
      );
    }
    return const FileEntry(
      name: '',
      isDir: false,
      permissions: '',
      size: '',
      date: '',
    );
  }
}

class FileManagerScreen extends ConsumerStatefulWidget {
  const FileManagerScreen({super.key, this.initialPath = '/'});

  final String initialPath;

  @override
  ConsumerState<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends ConsumerState<FileManagerScreen> {
  late String _currentPath;
  bool _busy = false;
  List<FileEntry> _entries = [];

  static const _shortcuts = [
    '/',
    '/etc',
    '/tmp',
    '/www',
    '/overlay',
  ];

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDirectory(_currentPath));
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _loadDirectory(String path) async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final safePath = path.replaceAll("'", '');
      final out = await api.shell('ls -la \'$safePath\' 2>&1');
      if (!mounted) return;
      final lines = out.split('\n');
      final list = <FileEntry>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('total ') || trimmed.isEmpty) continue;
        final entry = FileEntry.fromLs(trimmed);
        if (entry.name == '.' || entry.name == '..') continue;
        if (entry.name.isNotEmpty) list.add(entry);
      }
      list.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      setState(() {
        _currentPath = safePath;
        _entries = list;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'File Manager', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  void _navigateUp() {
    if (_currentPath == '/' || _currentPath.isEmpty) return;
    final parent = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
    _loadDirectory(parent.isEmpty ? '/' : parent);
  }

  Future<void> _viewFile(String fileName) async {
    final api = _client();
    if (api == null) return;
    final fullPath = '$_currentPath/$fileName'.replaceAll('//', '/');
    setState(() => _busy = true);
    try {
      final text = await api.shell('head -c 65536 \'$fullPath\' 2>&1');
      if (!mounted) return;
      setState(() => _busy = false);

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(fileName, style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
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
        await showRtwrtResult(context, action: 'Read File', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  Future<void> _downloadFile(String fileName) async {
    final api = _client();
    if (api == null) return;
    final fullPath = '$_currentPath/$fileName'.replaceAll('//', '/');
    setState(() => _busy = true);
    try {
      final bytes = await api.readBase64File(fullPath);
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/$fileName');
      await localFile.writeAsBytes(bytes, flush: true);
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(
          context,
          action: 'Download',
          ok: true,
          detail: 'Saved to phone: ${localFile.path}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'Download', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  Future<void> _deleteEntry(FileEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${entry.name}?'),
        content: Text('Are you sure you want to delete ${entry.name}? This cannot be undone.'),
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
    final fullPath = '$_currentPath/${entry.name}'.replaceAll('//', '/');
    setState(() => _busy = true);
    try {
      final cmd = entry.isDir ? 'rm -rf \'$fullPath\'' : 'rm -f \'$fullPath\'';
      await api.shell(cmd);
      if (mounted) {
        setState(() => _busy = false);
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'Delete', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  Future<void> _uploadFile() async {
    final file = await FilePicker.pickFile();
    if (file == null || !mounted) return;
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final destPath = '$_currentPath/${file.name}'.replaceAll('//', '/');
      await api.writeBase64File(destPath, bytes);
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'Upload', ok: true, detail: 'Uploaded to $destPath');
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showRtwrtResult(context, action: 'Upload', ok: false, detail: RtwrtApi.explain(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'File Manager',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Upload to here',
            onPressed: _busy ? null : _uploadFile,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : () => _loadDirectory(_currentPath),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.black26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward),
                      tooltip: 'Up one directory',
                      onPressed: _currentPath == '/' ? null : _navigateUp,
                    ),
                    Expanded(
                      child: Text(
                        _currentPath,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in _shortcuts)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(s, style: const TextStyle(fontSize: 12)),
                            onPressed: _busy ? null : () => _loadDirectory(s),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _entries.isEmpty && !_busy
                ? const Center(child: Text('Empty folder'))
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, idx) {
                      final entry = _entries[idx];
                      return ListTile(
                        leading: Icon(
                          entry.isDir ? Icons.folder : Icons.insert_drive_file,
                          color: entry.isDir ? const Color(0xFF00F0FF) : Colors.white70,
                        ),
                        title: Text(entry.name),
                        subtitle: Text(
                          '${entry.permissions} • ${entry.isDir ? "dir" : "${entry.size}B"} • ${entry.date}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (val) {
                            if (val == 'view') {
                              _viewFile(entry.name);
                            } else if (val == 'download') {
                              _downloadFile(entry.name);
                            } else if (val == 'delete') {
                              _deleteEntry(entry);
                            }
                          },
                          itemBuilder: (context) => [
                            if (!entry.isDir) const PopupMenuItem(value: 'view', child: Text('View')),
                            if (!entry.isDir) const PopupMenuItem(value: 'download', child: Text('Download')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                        onTap: () {
                          if (entry.isDir) {
                            final next = '$_currentPath/${entry.name}'.replaceAll('//', '/');
                            _loadDirectory(next);
                          } else {
                            _viewFile(entry.name);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
