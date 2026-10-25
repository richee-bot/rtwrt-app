import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

class ModemScreen extends ConsumerStatefulWidget {
  const ModemScreen({super.key});

  @override
  ConsumerState<ModemScreen> createState() => _ModemScreenState();
}

class _ModemScreenState extends ConsumerState<ModemScreen> {
  final _at = TextEditingController(text: 'AT+CSQ');
  final _apn = TextEditingController();
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

  static const _pdpTypes = ['ipv4', 'ipv6', 'ipv4v6'];
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
  void dispose() {
    _at.dispose();
    _apn.dispose();
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
echo "PORT=$PORT"
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
    final apn = RegExp(r'^APN=(.*)$', multiLine: true).firstMatch(text);
    final pdp = RegExp(r'^PDP=(.*)$', multiLine: true).firstMatch(text);
    final nr = RegExp(r'nr5g_band",(.+)').firstMatch(text);
    final lte = RegExp(r'lte_band",(.+)').firstMatch(text);
    if (mounted) {
      setState(() {
        _cell = cell;
        if (apn != null && _apn.text.isEmpty) _apn.text = apn.group(1)!.trim();
        final pdpValue = pdp?.group(1)?.trim() ?? '';
        if (_pdpTypes.contains(pdpValue)) _pdp = pdpValue;
        if (nr != null && _nr.text.isEmpty) _nr.text = nr.group(1)!.trim();
        if (lte != null && _lte.text.isEmpty) _lte.text = lte.group(1)!.trim();
      });
    }
    return text;
  });

  @override
  Widget build(BuildContext context) {
    final cell = _cell;
    return Scaffold(
      appBar: LuciAppBar(
        title: 'Modem',
        showBack: true,
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (cell != null) ...[
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _metric('RAT', cell.rat),
                _metric('Band', cell.band),
                _metric('RSRP', cell.rsrp),
                _metric('RSRQ', cell.rsrq),
                _metric('SINR', cell.sinr),
                _metric('RSSI', cell.rssi),
                _metric('PCI', cell.pci),
                _metric('ARFCN', cell.arfcn),
              ],
            ),
            const SizedBox(height: 12),
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
          FilledButton(
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
            child: const Text('Save APN and redial'),
          ),
          const SizedBox(height: 16),
          _field(_nr, '5G bands, colon separated'),
          const SizedBox(height: 8),
          _field(_lte, 'LTE bands, colon separated'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run('Apply bands', (api) async {
                    final nr = _nr.text.trim();
                    final lte = _lte.text.trim();
                    return api.shell('''
PORT=\$(uci -q get qmodem.4_1.at_port)
[ -n "\$PORT" ] || PORT=/dev/ttyUSB3
tom_modem -d "\$PORT" -o at -c 'AT+QNWPREFCFG="nr5g_band",${_q(nr)}'
tom_modem -d "\$PORT" -o at -c 'AT+QNWPREFCFG="lte_band",${_q(lte)}'
''');
                  }),
            child: const Text('Apply bands'),
          ),
          const SizedBox(height: 16),
          _field(_pci, 'Tower PCI'),
          const SizedBox(height: 8),
          _field(_arfcn, 'Tower ARFCN'),
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
                            '\'AT+QNWLOCK="common/5g",1,${_q(arfcn)},${_q(pci)}\'',
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
                            'tom_modem -d "\$PORT" -o at -c '
                            '\'AT+QNWLOCK="common/5g",0\'',
                          ),
                        ),
                  child: const Text('Release'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('at|${_at.text}'),
            initialValue: _atCommands.contains(_at.text) ? _at.text : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'AT command',
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
          OutlinedButton(
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
            child: const Text('Send AT'),
          ),
          const SizedBox(height: 16),
          _field(_ussd, 'USSD code'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run('Send USSD', (api) {
                    final code = _ussd.text.trim();
                    return api.shell(
                      'PORT=\$(uci -q get qmodem.4_1.at_port); '
                      '[ -n "\$PORT" ] || PORT=/dev/ttyUSB3; '
                      'tom_modem -d "\$PORT" -o at -c '
                      '\'AT+CUSD=1,"${_q(code)}"\'',
                    );
                  }),
            child: const Text('Send USSD'),
          ),
          const SizedBox(height: 16),
          _field(_smsTo, 'SMS number'),
          const SizedBox(height: 8),
          _field(_smsBody, 'SMS text'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          'Read SMS',
                          (api) => api.shell(
                            'PORT=\$(uci -q get qmodem.4_1.sms_at_port); '
                            '[ -n "\$PORT" ] || PORT=/dev/ttyUSB2; '
                            'sms_tool -d "\$PORT" recv',
                          ),
                        ),
                  child: const Text('Read SMS'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run('Send SMS', (api) {
                          final to = _smsTo.text.trim();
                          final body = _smsBody.text;
                          return api.shell(
                            'PORT=\$(uci -q get qmodem.4_1.sms_at_port); '
                            '[ -n "\$PORT" ] || PORT=/dev/ttyUSB2; '
                            'sms_tool -d "\$PORT" send ${_sh(to)} ${_sh(body)}',
                          );
                        }),
                  child: const Text('Send SMS'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(
                    'Nearby towers',
                    (api) => api.shell(
                      'PORT=\$(uci -q get qmodem.4_1.at_port); '
                      '[ -n "\$PORT" ] || PORT=/dev/ttyUSB3; '
                      'tom_modem -d "\$PORT" -o at -c \'AT+QENG="neighbourcell"\'',
                    ),
                  ),
            child: const Text('Nearby towers'),
          ),
          const SizedBox(height: 16),
          SelectableText(_output),
        ],
      ),
    );
  }

  Widget _metric(String label, String? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value == null || value.isEmpty ? '—' : value),
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

String _q(String value) => value.replaceAll("'", '');

String _sh(String value) => "'${value.replaceAll("'", "'\\''")}'";
