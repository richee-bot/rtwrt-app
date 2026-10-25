import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/rtwrt/app_token.dart';
import 'package:luci_mobile/rtwrt/profile.dart';
import 'package:luci_mobile/rtwrt/result_dialog.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/utils/url_parser.dart';

/// First open. Collects Telegram, Wi-Fi address, router login, and the app token.
class FirstUseScreen extends ConsumerStatefulWidget {
  const FirstUseScreen({super.key});

  @override
  ConsumerState<FirstUseScreen> createState() => _FirstUseScreenState();
}

class _FirstUseScreenState extends ConsumerState<FirstUseScreen> {
  final _telegram = TextEditingController();
  final _ip = TextEditingController(text: '192.168.1.1');
  final _user = TextEditingController(text: 'root');
  final _password = TextEditingController();
  final _token = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  bool _showToken = false;

  @override
  void dispose() {
    _telegram.dispose();
    _ip.dispose();
    _user.dispose();
    _password.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final telegram = normalizeTelegramUser(_telegram.text);
    if (telegram.length < 3) {
      await showRtwrtResult(
        context,
        action: 'Welcome',
        ok: false,
        detail: 'Enter a Telegram username, for example @richeetayu.',
      );
      return;
    }
    final parsed = UrlParser.parse(_ip.text.trim());
    if (!parsed.isValid) {
      await showRtwrtResult(
        context,
        action: 'Welcome',
        ok: false,
        detail: 'Enter the router Wi-Fi address, for example 192.168.1.1.',
      );
      return;
    }
    final user = _user.text.trim().isEmpty ? 'root' : _user.text.trim();
    final password = _password.text;
    if (password.isEmpty) {
      await showRtwrtResult(
        context,
        action: 'Welcome',
        ok: false,
        detail: 'Enter the router password.',
      );
      return;
    }
    if (!appTokenMatches(_token.text)) {
      await showRtwrtResult(
        context,
        action: 'Welcome',
        ok: false,
        detail:
            'That app token does not match. It is in app-token.txt in the RTWRT APP folder.',
      );
      return;
    }
    setState(() => _busy = true);
    final storage = SecureStorageService();
    try {
      await storage.writeValue(RtwrtProfile.telegramKey, telegram);
      await storage.writeValue(RtwrtProfile.wifiIpKey, parsed.hostWithPort);
      await storage.writeValue(RtwrtProfile.onboardingKey, '1');
      await storage.saveCredentials(
        ipAddress: parsed.hostWithPort,
        username: user,
        password: password,
        useHttps: parsed.useHttps,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await showRtwrtResult(
        context,
        action: 'Welcome',
        ok: false,
        detail: 'Could not save this on the phone. $e',
      );
      return;
    }
    if (!mounted) return;
    final appState = ref.read(appStateProvider);
    final ok = await appState.login(
      parsed.hostWithPort,
      user,
      password,
      parsed.useHttps,
      context: context,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await showRtwrtResult(
        context,
        action: 'Welcome',
        ok: true,
        detail: 'Saved @$telegram. Signed in at ${parsed.hostWithPort}.',
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacementNamed('/');
      return;
    }
    await showRtwrtResult(
      context,
      action: 'Welcome',
      ok: false,
      detail:
          'Saved @$telegram. The router did not accept ${parsed.hostWithPort} yet. '
          'The login screen is next so you can try again.',
    );
    if (!mounted) return;
    await Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Welcome to RTWRT')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'This phone has not been set up yet.\n\n'
              '1. Your Telegram username, so reports show who sent them.\n'
              '2. The router Wi-Fi address, login, and password.\n'
              '3. The app token from app-token.txt in the RTWRT APP folder.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _telegram,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Telegram username',
                hintText: '@username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ip,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Wi-Fi IP',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Login',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              enabled: !_busy,
              obscureText: !_showToken,
              decoration: InputDecoration(
                labelText: 'App token',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showToken = !_showToken),
                  icon: Icon(
                    _showToken ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving' : 'Save and continue'),
            ),
          ],
        ),
      ),
    );
  }
}
