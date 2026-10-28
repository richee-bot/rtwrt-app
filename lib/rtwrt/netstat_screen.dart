import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class NetstatEntry {
  final String proto;
  final String recvQ;
  final String sendQ;
  final String localAddress;
  final String foreignAddress;
  final String state;
  final String pidProgram;

  const NetstatEntry({
    required this.proto,
    required this.recvQ,
    required this.sendQ,
    required this.localAddress,
    required this.foreignAddress,
    required this.state,
    required this.pidProgram,
  });

  factory NetstatEntry.fromLine(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 6) {
      final proto = parts[0];
      final recvQ = parts[1];
      final sendQ = parts[2];
      final local = parts[3];
      final foreign = parts[4];
      String state = '—';
      String pid = '';
      if (parts.length >= 7) {
        state = parts[5];
        pid = parts.sublist(6).join(' ');
      } else {
        state = parts[5];
      }
      return NetstatEntry(
        proto: proto,
        recvQ: recvQ,
        sendQ: sendQ,
        localAddress: local,
        foreignAddress: foreign,
        state: state,
        pidProgram: pid,
      );
    }
    return const NetstatEntry(
      proto: '',
      recvQ: '',
      sendQ: '',
      localAddress: '',
      foreignAddress: '',
      state: '',
      pidProgram: '',
    );
  }
}

class NetstatScreen extends ConsumerStatefulWidget {
  const NetstatScreen({super.key});

  @override
  ConsumerState<NetstatScreen> createState() => _NetstatScreenState();
}

class _NetstatScreenState extends ConsumerState<NetstatScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  bool _busy = false;
  List<NetstatEntry> _allEntries = [];
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchNetstat());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _fetchNetstat() async {
    final api = _client();
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final text = await api.shell('netstat -tulpen 2>/dev/null || netstat -an 2>/dev/null');
      if (!mounted) return;
      final lines = text.split('\n');
      final list = <NetstatEntry>[];
      for (final line in lines) {
        final t = line.trim();
        if (t.startsWith('Proto ') || t.startsWith('Active ') || t.isEmpty) continue;
        final entry = NetstatEntry.fromLine(t);
        if (entry.proto.isNotEmpty && entry.localAddress.isNotEmpty) {
          list.add(entry);
        }
      }
      setState(() {
        _allEntries = list;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<NetstatEntry> _getFilteredEntries(int tabIndex) {
    return _allEntries.where((e) {
      if (_filterQuery.isNotEmpty) {
        final q = _filterQuery.toLowerCase();
        final match = e.localAddress.toLowerCase().contains(q) ||
            e.foreignAddress.toLowerCase().contains(q) ||
            e.pidProgram.toLowerCase().contains(q) ||
            e.proto.toLowerCase().contains(q);
        if (!match) return false;
      }
      switch (tabIndex) {
        case 1: // Listening
          return e.state.toUpperCase().contains('LISTEN');
        case 2: // Established
          return e.state.toUpperCase().contains('ESTABLISHED');
        case 3: // TCP
          return e.proto.toLowerCase().contains('tcp');
        case 4: // UDP
          return e.proto.toLowerCase().contains('udp');
        default: // All
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Netstat - Active Ports',
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _busy ? null : _fetchNetstat,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: 'All'),
                Tab(text: 'Listening'),
                Tab(text: 'Established'),
                Tab(text: 'TCP'),
                Tab(text: 'UDP'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Filter by port, address, or process name...',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _filterQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _filterQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (val) => setState(() => _filterQuery = val.trim()),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (var i = 0; i < 5; i++) _buildList(_getFilteredEntries(i)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<NetstatEntry> entries) {
    if (entries.isEmpty && !_busy) {
      return const Center(child: Text('No connections matching filter.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, idx) {
        final e = entries[idx];
        final isListen = e.state.toUpperCase().contains('LISTEN');
        final isEst = e.state.toUpperCase().contains('ESTABLISHED');
        final badgeColor = isListen
            ? const Color(0xFF00FF9D)
            : (isEst ? const Color(0xFF00F0FF) : Colors.white60);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        e.proto.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                    Text(
                      e.state,
                      style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Local Address', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          SelectableText(
                            e.localAddress,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward, size: 14, color: Colors.white38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Foreign Address', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          SelectableText(
                            e.foreignAddress,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (e.pidProgram.isNotEmpty) ...[
                  const Divider(height: 16),
                  Text(
                    'Program: ${e.pidProgram}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
