import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/rtwrt/github_release.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

enum ConnectorOutcome { ready, installed, failed }

class ConnectorResult {
  const ConnectorResult(this.outcome, this.message);

  final ConnectorOutcome outcome;
  final String message;
}

/// Pulls the rpcd ACL from GitHub and installs it on the connected router.
class ConnectorInstaller {
  static final Dio _dio = Dio(
    BaseOptions(
      headers: const {'User-Agent': 'RTWRT'},
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<ConnectorResult> ensure(RtwrtApi api) async {
    try {
      final text = await api.shell('echo RTWRT_OK');
      if (text.contains('RTWRT_OK')) {
        return const ConnectorResult(
          ConnectorOutcome.ready,
          'The router connector is already in place.',
        );
      }
    } catch (e) {
      final message = RtwrtApi.explain(e);
      if (!message.contains('blocked this command') &&
          !message.contains('permission')) {
        return ConnectorResult(ConnectorOutcome.failed, message);
      }
    }
    return install(api);
  }

  static Future<ConnectorResult> install(RtwrtApi api) async {
    if (!isRicheeGithubUrl(AppConfig.connectorUrl)) {
      return const ConnectorResult(
        ConnectorOutcome.failed,
        'The connector address is not on GitHub.',
      );
    }
    String body;
    try {
      final response = await _dio.get<String>(AppConfig.connectorUrl);
      body = response.data ?? '';
    } catch (e) {
      return ConnectorResult(
        ConnectorOutcome.failed,
        'Could not download the connector from GitHub. $e',
      );
    }
    if (!body.contains('"luci-app-rtwrt"') || !body.trimLeft().startsWith('{')) {
      return const ConnectorResult(
        ConnectorOutcome.failed,
        'GitHub did not return the connector file.',
      );
    }

    final encoded = base64Encode(utf8.encode(body));
    try {
      final text = await api.shell('''
mkdir -p /usr/share/rpcd/acl.d
printf '%s' '$encoded' | base64 -d > /usr/share/rpcd/acl.d/luci-app-rtwrt.json
grep -q luci-app-rtwrt /usr/share/rpcd/acl.d/luci-app-rtwrt.json
PREFIX=\$(uci -q get uhttpd.main.ubus_prefix)
if [ "\$PREFIX" != /ubus ]; then
  uci set uhttpd.main.ubus_prefix=/ubus
  uci commit uhttpd
  (sleep 2; /etc/init.d/uhttpd restart) >/dev/null 2>&1 &
fi
(sleep 1; /etc/init.d/rpcd restart) >/dev/null 2>&1 &
echo INSTALLED
''');
      if (text.contains('INSTALLED')) {
        return const ConnectorResult(
          ConnectorOutcome.installed,
          'The connector is installed. Log out of the app, then sign in again.',
        );
      }
      return ConnectorResult(
        ConnectorOutcome.failed,
        text.trim().isEmpty ? 'The router did not confirm the install.' : text,
      );
    } catch (e) {
      try {
        await api.writeBase64File(
          '/usr/share/rpcd/acl.d/luci-app-rtwrt.json',
          utf8.encode(body),
        );
        return const ConnectorResult(
          ConnectorOutcome.installed,
          'The connector file is on the router. Restart it, then sign in again.',
        );
      } catch (writeError) {
        return ConnectorResult(
          ConnectorOutcome.failed,
          RtwrtApi.explain(writeError),
        );
      }
    }
  }
}
