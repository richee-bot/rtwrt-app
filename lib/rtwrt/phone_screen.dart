import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:luci_mobile/services/telephony_service.dart';
import 'package:luci_mobile/state/telephony_notifier.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _numberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  void _appendDigit(String digit) {
    HapticFeedback.lightImpact();
    setState(() {
      _numberController.text += digit;
    });
  }

  void _backspace() {
    HapticFeedback.lightImpact();
    final text = _numberController.text;
    if (text.isNotEmpty) {
      setState(() {
        _numberController.text = text.substring(0, text.length - 1);
      });
    }
  }

  void _showComposeSheet(BuildContext context, {String recipient = ''}) {
    final toCtrl = TextEditingController(text: recipient);
    final msgCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Compose SMS',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: toCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Recipient Number',
                  hintText: '+601...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: msgCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Message Body',
                  hintText: 'Type your message...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Send SMS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final to = toCtrl.text.trim();
                  final body = msgCtrl.text.trim();
                  if (to.isEmpty || body.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill in both recipient and message.')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  final res = await ref.read(telephonyProvider.notifier).sendSms(to, body);
                  if (!context.mounted) return;
                  if (res.isSuccess) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(res.message ?? 'SMS sent successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(res.error ?? 'Failed to send SMS.'),
                        backgroundColor: Colors.redAccent,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(telephonyProvider);
    final notifier = ref.read(telephonyProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Modem Phone & SMS',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: state.status.volte ? Colors.greenAccent : Colors.orangeAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${state.ownDisplayNumber} • ${state.identity.operator.isNotEmpty ? state.identity.operator : 'SIM Active'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.refresh(),
            tooltip: 'Sync Live State',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dialpad), text: 'Keypad'),
            Tab(icon: Icon(Icons.history), text: 'Calls'),
            Tab(icon: Icon(Icons.sms), text: 'SMS'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.lastError != null)
              Container(
                color: Colors.red.withValues(alpha: 0.2),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.lastError!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (state.status.isRinging)
              _buildIncomingCallBanner(state.status, notifier),
            Expanded(
              child: state.status.isTalking || state.status.isDialing
                  ? _buildActiveCallView(state.status, notifier)
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDialpadTab(notifier, state.busy),
                        _buildHistoryTab(state.history, notifier),
                        _buildSmsTab(state.smsList, notifier),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 2
          ? FloatingActionButton.extended(
              onPressed: () => _showComposeSheet(context),
              icon: const Icon(Icons.edit),
              label: const Text('Compose'),
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.black,
            )
          : null,
    );
  }

  Widget _buildIncomingCallBanner(
    TelephonyStatus status,
    TelephonyNotifier notifier,
  ) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blueGrey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.greenAccent.withValues(alpha: 0.2),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.green,
            child: Icon(Icons.phone_in_talk, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Incoming Call...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  status.peer.isNotEmpty ? status.peer : 'Unknown Caller',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_end, color: Colors.red),
            onPressed: () => notifier.hangup(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.call, color: Colors.green),
            onPressed: () => notifier.answer(),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCallView(
    TelephonyStatus status,
    TelephonyNotifier notifier,
  ) {
    final minutes = (status.duration ~/ 60).toString().padLeft(2, '0');
    final seconds = (status.duration % 60).toString().padLeft(2, '0');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.green.withValues(alpha: 0.2),
            child: const Icon(Icons.person, size: 60, color: Colors.greenAccent),
          ),
          const SizedBox(height: 24),
          Text(
            status.peer.isNotEmpty ? status.peer : 'Active Call',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            status.isDialing ? 'Dialing...' : '$minutes:$seconds',
            style: TextStyle(
              fontSize: 18,
              color: status.isDialing ? Colors.orangeAccent : Colors.grey,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 32,
                color: Colors.white,
                icon: const Icon(Icons.mic_off),
                onPressed: () {},
              ),
              IconButton(
                iconSize: 32,
                color: Colors.white,
                icon: const Icon(Icons.volume_up),
                onPressed: () {},
              ),
              IconButton(
                iconSize: 32,
                color: Colors.white,
                icon: const Icon(Icons.dialpad),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 30),
          GestureDetector(
            onTap: () => notifier.hangup(),
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.call_end, color: Colors.white, size: 36),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDialpadTab(TelephonyNotifier notifier, bool busy) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _numberController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Enter Number',
                    border: InputBorder.none,
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
              if (_numberController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: _backspace,
                  onLongPress: () {
                    HapticFeedback.heavyImpact();
                    setState(() => _numberController.clear());
                  },
                ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          _keypadRow(['1', '2', '3'], ['', 'ABC', 'DEF']),
          _keypadRow(['4', '5', '6'], ['GHI', 'JKL', 'MNO']),
          _keypadRow(['7', '8', '9'], ['PQRS', 'TUV', 'WXYZ']),
          _keypadRow(['*', '0', '#'], ['', '+', '']),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: busy
                ? null
                : () {
                    final num = _numberController.text.trim();
                    if (num.isNotEmpty) {
                      notifier.dial(num);
                    }
                  },
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.greenAccent[700],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.greenAccent.withValues(alpha: 0.3),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.call, color: Colors.white, size: 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keypadRow(List<String> digits, List<String> subtexts) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < 3; i++)
            _keypadButton(digits[i], subtexts[i]),
        ],
      ),
    );
  }

  Widget _keypadButton(String digit, String sub) {
    return InkWell(
      onTap: () => _appendDigit(digit),
      onLongPress: () {
        if (digit == '0') {
          _appendDigit('+');
        }
      },
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            if (sub.isNotEmpty)
              Text(
                sub,
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab(
    List<TelephonyCallRecord> history,
    TelephonyNotifier notifier,
  ) {
    if (history.isEmpty) {
      return const Center(
        child: Text('No recent calls logged.'),
      );
    }

    final dateFormat = DateFormat('MMM d, h:mm a');

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: history.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = history[index];
        final isMissed = item.event == 'missed';
        final isOut = item.event == 'out';

        IconData icon = Icons.call_received;
        Color color = Colors.green;
        if (isMissed) {
          icon = Icons.call_missed;
          color = Colors.red;
        } else if (isOut) {
          icon = Icons.call_made;
          color = Colors.blue;
        }

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(
            item.number.isNotEmpty ? item.number : 'Private / Unknown',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isMissed ? Colors.redAccent : Colors.white,
            ),
          ),
          subtitle: Text(dateFormat.format(item.date)),
          trailing: IconButton(
            icon: const Icon(Icons.call, color: Colors.green),
            onPressed: () {
              if (item.number.isNotEmpty) {
                notifier.dial(item.number);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildSmsTab(
    List<Map<String, dynamic>> smsList,
    TelephonyNotifier notifier,
  ) {
    if (smsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mail_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No SMS messages found.'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('Compose Message'),
              onPressed: () => _showComposeSheet(context),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: smsList.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final reversed = smsList.reversed.toList();
        final msg = reversed[index];
        final sender = msg['sender']?.toString() ?? 'Unknown';
        final content = msg['content']?.toString() ?? '';
        final time = msg['timestamp']?.toString() ?? '';

        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.cyan,
            child: Icon(Icons.sms, color: Colors.black, size: 20),
          ),
          title: Text(sender, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(content, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(time, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.reply, size: 20),
            onPressed: () => _showComposeSheet(context, recipient: sender),
          ),
        );
      },
    );
  }
}
