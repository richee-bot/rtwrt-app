import 'package:flutter/material.dart';
import 'package:luci_mobile/rtwrt/broadcast.dart';

/// Owner notice from GitHub. Hidden until a new message is published.
class BroadcastBanner extends StatefulWidget {
  const BroadcastBanner({super.key});

  @override
  State<BroadcastBanner> createState() => _BroadcastBannerState();
}

class _BroadcastBannerState extends State<BroadcastBanner> {
  BroadcastMsg? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final msg = await BroadcastNotice.fetch();
    if (!mounted || msg == null) return;
    final show = await BroadcastNotice.shouldShow(msg);
    if (!mounted || !show) return;
    setState(() => _msg = msg);
  }

  Future<void> _dismiss() async {
    final msg = _msg;
    if (msg == null) return;
    await BroadcastNotice.dismiss(msg);
    if (mounted) setState(() => _msg = null);
  }

  @override
  Widget build(BuildContext context) {
    final msg = _msg;
    if (msg == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(msg.title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(child: Text(msg.body)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _dismiss,
                  child: const Text('Dismiss'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
