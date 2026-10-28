import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

/// Representation of a parsed SMS message from sms_tool.
class SmsMessage {
  const SmsMessage({
    required this.index,
    required this.sender,
    required this.timestamp,
    required this.content,
  });

  final int index;
  final String sender;
  final String timestamp;
  final String content;

  factory SmsMessage.fromJson(Map<String, dynamic> json) {
    return SmsMessage(
      index: (json['index'] as num?)?.toInt() ?? 0,
      sender: json['sender']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
    );
  }
}

class ModemScreen extends ConsumerStatefulWidget {
  const ModemScreen({super.key});

  @override
  ConsumerState<ModemScreen> createState() => _ModemScreenState();
}

class _ModemScreenState extends ConsumerState<ModemScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _at = TextEditingController(text: 'AT+CSQ');
  final _apn = TextEditingController();
  final _atPort = TextEditingController(text: '/dev/ttyUSB3');
  final _smsPort = TextEditingController(text: '/dev/ttyUSB3');
  final _networkIface = TextEditingController(text: 'wwan0');
  final _nr = TextEditingController();
  final _lte = TextEditingController();
  final _pci = TextEditingController();
  final _arfcn = TextEditingController();
  final _ussd = TextEditingController();
  final _smsTo = TextEditingController();
  final _smsBody = TextEditingController();

  String _output = 'Pull to read the modem.';
  ServingCell? _cell;
  bool _busy = false;
  String _pdp = 'ipv4v6';
  List<SmsMessage> _smsList = [];
  bool _loadingSms = false;

  static const _pdpTypes = ['ipv4', 'ipv6', 'ipv4v6'];
  static const _portChoices = [
    '/dev/ttyUSB0',
    '/dev/ttyUSB1',
    '/dev/ttyUSB2',
    '/dev/ttyUSB3',
    '/dev/ttyUSB4',
    '/dev/cdc-wdm0',
  ];
  static const _atCommands = [
    'AT+CSQ',
    'AT+COPS?',
    'AT+QNWINFO',
    'AT+CGDCONT?',
    'AT+QENG="servingcell"',
    'AT+QENG="neighbourcell"',
    'AT+QNWPREFCFG="nr5g_band"',
    'AT+QNWPREFCFG="lte_band"',
    'AT+QTEMP',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _fetchSms();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _at.dispose();
    _apn.dispose();
    _atPort.dispose();
    _smsPort.dispose();
    _networkIface.dispose();
    _nr.dispose();
    _lte.dispose();
    _pci.dispose();
    _arfcn.dispose();
    _ussd.dispose();
    _smsTo.dispose();
    _smsBody.dispose();
    super.dispose();
  }

  RtwrtApi? _client() {
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  Future<void> _report(String action, bool ok, String detail) async {
    final text = detail.trim().isEmpty
        ? (ok ? 'Done.' : 'The router did not say why.')
        : detail.trim();
    if (!mounted) return;
    setState(() => _output = text);
    await showRtwrtResult(context, action: action, ok: ok, detail: text);
  }

  Future<void> _run(
    String action,
    Future<String> Function(RtwrtApi api) body,
  ) async {
    final api = _client();
    if (api == null) {
      await _report(action, false, 'Not connected to the router.');
      return;
    }
    setState(() => _busy = true);
    try {
      final text = await body(api);
      if (!mounted) return;
      await _report(action, true, text);
    } catch (e) {
      if (!mounted) return;
      await _report(action, false, RtwrtApi.explain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run('Read modem', (api) async {
    final text = await api.shell(r'''
PORT=$(uci -q get qmodem.4_1.at_port)
[ -n "$PORT" ] || PORT=/dev/ttyUSB3
SMSPORT=$(uci -q get qmodem.4_1.sms_at_port)
[ -n "$SMSPORT" ] || SMSPORT=/dev/ttyUSB3
NETIFACE=$(uci -q get qmodem.4_1.network)
[ -n "$NETIFACE" ] || NETIFACE=wwan0
echo "PORT=$PORT"
echo "SMSPORT=$SMSPORT"
echo "NETIFACE=$NETIFACE"
echo "APN=$(uci -q get qmodem.4_1.apn)"
echo "DIAL=$(uci -q get qmodem.4_1.enable_dial)"
echo "PDP=$(uci -q get qmodem.4_1.pdp_type)"
echo "---"
tom_modem -d "$PORT" -o at -c 'AT+QENG="servingcell"'
echo "---"
tom_modem -d "$PORT" -o at -c 'AT+QNWPREFCFG="nr5g_band"'
tom_modem -d "$PORT" -o at -c 'AT+QNWPREFCFG="lte_band"'
tom_modem -d "$PORT" -o at -c 'AT+QTEMP'
''');
    final cell = ServingCell.parse(text);
    final port = RegExp(r'^PORT=(.*)$', multiLine: true).firstMatch(text);
    final smsPort = RegExp(r'^SMSPORT=(.*)$', multiLine: true).firstMatch(text);
    final netIface = RegExp(r'^NETIFACE=(.*)$', multiLine: true).firstMatch(text);
    final apn = RegExp(r'^APN=(.*)$', multiLine: true).firstMatch(text);
    final pdp = RegExp(r'^PDP=(.*)$', multiLine: true).firstMatch(text);
    final nr = RegExp(r'nr5g_band",(.+)').firstMatch(text);
    final lte = RegExp(r'lte_band",(.+)').firstMatch(text);
    if (mounted) {
      setState(() {
        _cell = cell;
        if (port != null && port.group(1)!.trim().isNotEmpty) {
          _atPort.text = port.group(1)!.trim();
        }
        if (smsPort != null && smsPort.group(1)!.trim().isNotEmpty) {
          _smsPort.text = smsPort.group(1)!.trim();
        }
        if (netIface != null && netIface.group(1)!.trim().isNotEmpty) {
          _networkIface.text = netIface.group(1)!.trim();
        }
        if (apn != null && _apn.text.isEmpty) _apn.text = apn.group(1)!.trim();
        final pdpValue = pdp?.group(1)?.trim() ?? '';
        if (_pdpTypes.contains(pdpValue)) _pdp = pdpValue;
        if (nr != null && _nr.text.isEmpty) _nr.text = nr.group(1)!.trim();
        if (lte != null && _lte.text.isEmpty) _lte.text = lte.group(1)!.trim();
      });
    }
    return text;
  });

  Future<void> _fetchSms() async {
    final api = _client();
    if (api == null) return;
    setState(() => _loadingSms = true);
    try {
      final port = _smsPort.text.trim().isNotEmpty ? _smsPort.text.trim() : '/dev/ttyUSB3';
      final text = await api.shell('if command -v rtwrt-sms >/dev/null 2>&1; then rtwrt-sms recv; elif command -v sms_tool_q >/dev/null 2>&1; then sms_tool_q -d "$port" -j recv; else sms_tool -d "$port" -j recv; fi 2>&1');
      final jsonStart = text.indexOf('{');
      final jsonEnd = text.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd > jsonStart) {
        final jsonStr = text.substring(jsonStart, jsonEnd + 1);
        final dynamic parsed = jsonDecode(jsonStr);
        if (parsed is Map && parsed['msg'] is List) {
          final list = (parsed['msg'] as List)
              .whereType<Map>()
              .map((m) => SmsMessage.fromJson(Map<String, dynamic>.from(m)))
              .toList();
          if (mounted) {
            setState(() {
              _smsList = list;
              _loadingSms = false;
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          _smsList = [];
          _loadingSms = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSms = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Modem',
        showBack: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : () {
              _refresh();
              _fetchSms();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.cell_tower), text: 'Modem'),
                Tab(icon: Icon(Icons.sms), text: 'SMS'),
                Tab(icon: Icon(Icons.settings_ethernet), text: 'Ports & Config'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildModemTab(),
                _buildSmsTab(),
                _buildPortsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModemTab() {
    final cell = _cell;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (cell != null) ...[
          _buildSignalStatusCard(cell),
          const SizedBox(height: 16),
        ],
        _field(_apn, 'APN'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('pdp|$_pdp'),
          initialValue: _pdpTypes.contains(_pdp) ? _pdp : 'ipv4v6',
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'IP type',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'ipv4', child: Text('IPv4')),
            DropdownMenuItem(value: 'ipv6', child: Text('IPv6')),
            DropdownMenuItem(value: 'ipv4v6', child: Text('IPv4 and IPv6')),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _pdp = value);
                },
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Save APN and redial'),
          onPressed: _busy
              ? null
              : () => _run('Save APN', (api) async {
                  final apn = _apn.text.trim();
                  return api.shell(
                    "uci set qmodem.4_1.apn='${_q(apn)}'; "
                    "uci set qmodem.4_1.pdp_type='${_q(_pdp)}'; "
                    'uci commit qmodem; /etc/init.d/qmodem_network restart; echo redialed',
                  );
                }),
        ),
        const SizedBox(height: 16),
        Text('Band Locking', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _field(_nr, '5G bands, colon separated (e.g. 1:3:28:78)'),
        const SizedBox(height: 8),
        _field(_lte, 'LTE bands, colon separated (e.g. 1:3:7:8:28)'),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run('Apply bands', (api) async {
                  final nr = _nr.text.trim();
                  final lte = _lte.text.trim();
                  return api.shell(
                    'PORT=\$(uci -q get qmodem.4_1.at_port); '
                    '[ -n "\$PORT" ] || PORT=/dev/ttyUSB3; '
                    'tom_modem -d "\$PORT" -o at -c "AT+QNWPREFCFG=\\"nr5g_band\\",${_q(nr)}"; '
                    'tom_modem -d "\$PORT" -o at -c "AT+QNWPREFCFG=\\"lte_band\\",${_q(lte)}"',
                  );
                }),
          child: const Text('Apply bands'),
        ),
        const SizedBox(height: 16),
        Text('Tower Lock', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _field(_pci, 'PCI')),
            const SizedBox(width: 8),
            Expanded(child: _field(_arfcn, 'ARFCN')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run('Lock tower', (api) {
                        final pci = _pci.text.trim();
                        final arfcn = _arfcn.text.trim();
                        return api.shell(
                          'PORT=\$(uci -q get qmodem.4_1.at_port); '
                          '[ -n "\$PORT" ] || PORT=/dev/ttyUSB3; '
                          'tom_modem -d "\$PORT" -o at -c '
                          '"AT+QNWLOCK=\\"common/5g\\",1,${_q(arfcn)},${_q(pci)}"',
                        );
                      }),
                child: const Text('Lock tower'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        'Release tower',
                        (api) => api.shell(
                          'PORT=\$(uci -q get qmodem.4_1.at_port); '
                          '[ -n "\$PORT" ] || PORT=/dev/ttyUSB3; '
                          'tom_modem -d "\$PORT" -o at -c "AT+QNWLOCK=\\"common/5g\\",0"',
                        ),
                      ),
                child: const Text('Release'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('AT Terminal & USSD', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('at|${_at.text}'),
          initialValue: _atCommands.contains(_at.text) ? _at.text : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'AT command shortcut',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final command in _atCommands)
              DropdownMenuItem(value: command, child: Text(command)),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _at.text = value);
                },
        ),
        const SizedBox(height: 8),
        _field(_at, 'Custom AT command'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('Send AT Command'),
          onPressed: _busy
              ? null
              : () => _run('Send AT', (api) {
                  final cmd = _at.text.trim();
                  if (!RegExp(r'^AT[0-9A-Za-z+=":,._/? -]*$').hasMatch(cmd)) {
                    return Future.value('That AT text was not sent.');
                  }
                  return api.shell(
                    'PORT=\$(uci -q get qmodem.4_1.at_port); '
                    '[ -n "\$PORT" ] || PORT=/dev/ttyUSB3; '
                    'tom_modem -d "\$PORT" -o at -c ${_sh(cmd)}',
                  );
                }),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _field(_ussd, 'USSD code (e.g. *118#)')),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run('Send USSD', (api) {
                      final code = _ussd.text.trim();
                      return api.shell(
                        'PORT=\$(uci -q get qmodem.4_1.at_port); '
                        '[ -n "\$PORT" ] || PORT=/dev/ttyUSB3; '
                        'tom_modem -d "\$PORT" -o at -c "AT+CUSD=1,\\"${_q(code)}\\""',
                      );
                    }),
              child: const Text('Run USSD'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.radar),
          label: const Text('Scan Nearby Towers'),
          onPressed: _busy
              ? null
              : () => _run(
                  'Nearby towers',
                  (api) => api.shell(
                    'PORT=\$(uci -q get qmodem.4_1.at_port); '
                    '[ -n "\$PORT" ] || PORT=/dev/ttyUSB3; '
                    'tom_modem -d "\$PORT" -o at -c "AT+QENG=\\"neighbourcell\\""',
                  ),
                ),
        ),
        if (_output.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            color: Colors.black45,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(_output, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSignalStatusCard(ServingCell cell) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.network_cell, color: Color(0xFF00F0FF)),
                    const SizedBox(width: 8),
                    Text(
                      cell.rat ?? 'Cellular',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
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
                    'Band ${cell.band ?? "Active"}',
                    style: const TextStyle(
                      color: Color(0xFF00FF9D),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _metric('RSRP', cell.rsrp != null ? '${cell.rsrp} dBm' : null),
                _metric('RSRQ', cell.rsrq != null ? '${cell.rsrq} dB' : null),
                _metric('SINR', cell.sinr != null ? '${cell.sinr} dB' : null),
                _metric('RSSI', cell.rssi != null ? '${cell.rssi} dBm' : null),
                _metric('PCI', cell.pci),
                _metric('ARFCN', cell.arfcn),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit_note, color: Color(0xFF00F0FF)),
                    const SizedBox(width: 8),
                    Text('Compose SMS', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                _field(_smsTo, 'Recipient Phone Number'),
                const SizedBox(height: 8),
                TextField(
                  controller: _smsBody,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Message Body',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('Send SMS'),
                  onPressed: _busy
                      ? null
                      : () => _run('Send SMS', (api) async {
                          final to = _smsTo.text.trim();
                          final body = _smsBody.text;
                          if (to.isEmpty || body.isEmpty) {
                            throw Exception('Enter a recipient and message body.');
                          }
                          final raw = await api.shell(
                            'rtwrt-sms send ${_sh(to)} ${_sh(body)}',
                          );
                          final start = raw.indexOf('{');
                          final end = raw.lastIndexOf('}');
                          if (start != -1 && end > start) {
                            try {
                              final decoded = jsonDecode(raw.substring(start, end + 1));
                              if (decoded is Map) {
                                if (decoded['status'] == 'success') {
                                  _smsBody.clear();
                                  await _fetchSms();
                                  return decoded['message']?.toString() ?? 'SMS sent successfully';
                                } else {
                                  throw Exception(decoded['detail'] ?? 'Failed to send SMS');
                                }
                              }
                            } catch (e) {
                              if (e is Exception) rethrow;
                            }
                          }
                          if (raw.toLowerCase().contains('error') || raw.toLowerCase().contains('failed')) {
                            throw Exception(raw.trim());
                          }
                          _smsBody.clear();
                          await _fetchSms();
                          return raw.trim();
                        }),
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
              'Inbox (${_smsList.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Check Inbox',
              onPressed: _loadingSms ? null : _fetchSms,
            ),
          ],
        ),
        if (_loadingSms) const LinearProgressIndicator(),
        if (_smsList.isEmpty && !_loadingSms)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No SMS messages found.')),
          ),
        for (final msg in _smsList)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    msg.sender.isNotEmpty ? msg.sender : 'Unknown Sender',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    msg.timestamp,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectableText(msg.content),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (val) {
                  if (val == 'reply') {
                    setState(() {
                      _smsTo.text = msg.sender;
                    });
                  } else if (val == 'delete') {
                    _run('Delete SMS', (api) {
                      final port = _smsPort.text.trim().isNotEmpty ? _smsPort.text.trim() : '/dev/ttyUSB3';
                      return api.shell('if command -v rtwrt-sms >/dev/null 2>&1; then rtwrt-sms delete ${msg.index}; else sms_tool_q -d "$port" delete ${msg.index}; fi');
                    }).then((_) => _fetchSms());
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'reply', child: Text('Reply')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPortsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cable, color: Color(0xFF00F0FF)),
                    const SizedBox(width: 8),
                    Text('Modem Communication & Network Ports', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'AT Command Port',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  key: ValueKey('at_port|${_atPort.text}'),
                  initialValue: _portChoices.contains(_atPort.text) ? _atPort.text : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select AT Port',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final p in _portChoices)
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: _busy
                      ? null
                      : (val) {
                          if (val != null) setState(() => _atPort.text = val);
                        },
                ),
                const SizedBox(height: 8),
                _field(_atPort, 'Or enter custom AT device path'),
                const SizedBox(height: 16),
                Text(
                  'SMS Service Port',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  key: ValueKey('sms_port|${_smsPort.text}'),
                  initialValue: _portChoices.contains(_smsPort.text) ? _smsPort.text : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select SMS AT Port',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final p in _portChoices)
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: _busy
                      ? null
                      : (val) {
                          if (val != null) setState(() => _smsPort.text = val);
                        },
                ),
                const SizedBox(height: 8),
                _field(_smsPort, 'Or enter custom SMS device path'),
                const SizedBox(height: 16),
                Text(
                  'Network Interface',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                _field(_networkIface, 'Interface name (default: wwan0)'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Save Ports and Apply'),
                  onPressed: _busy
                      ? null
                      : () => _run('Save Ports', (api) async {
                          final at = _atPort.text.trim();
                          final sms = _smsPort.text.trim();
                          final net = _networkIface.text.trim();
                          return api.shell(
                            "uci set qmodem.4_1.at_port='${_q(at)}'; "
                            "uci set qmodem.4_1.sms_at_port='${_q(sms)}'; "
                            "uci set qmodem.4_1.network='${_q(net)}'; "
                            'uci commit qmodem; /etc/init.d/qmodem_network restart; echo "Ports saved: AT=$at, SMS=$sms, NET=$net"',
                          );
                        }),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value == null || value.isEmpty ? 'â€”' : value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

String _q(String value) => value.replaceAll("'", "'\\''");
String _sh(String value) => "'${value.replaceAll("'", "'\\''")}'";

