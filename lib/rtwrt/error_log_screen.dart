import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';

/// Failures saved on the phone, with the router's own wording.
class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key});

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  List<String> _lines = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lines = await RtwrtErrorLog.read();
    if (mounted) setState(() => _lines = lines);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Error log',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Copy',
            onPressed: _lines.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _lines.join('\n\n')));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Copied')));
                  },
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: _lines.isEmpty
                ? null
                : () async {
                    await RtwrtErrorLog.clear();
                    await _load();
                  },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _lines.isEmpty
          ? const Center(child: Text('No errors saved yet.'))
          : ListView.separated(
              itemCount: _lines.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_lines[index]),
              ),
            ),
    );
  }
}
