import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/rtwrt/github_release.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';
import 'package:luci_mobile/state/app_state_provider.dart';

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

  static Future<bool> _ready(RtwrtApi api) async {
    try {
      final text = await api.shell('echo RTWRT_OK');
      return text.contains('RTWRT_OK');
    } catch (_) {
      return false;
    }
  }

  /// A new ubus login picks up the connector that is already on the router.
  static Future<RtwrtApi?> refreshSession(WidgetRef ref) async {
    if (!ref.context.mounted) return null;
    final ok = await ref.read(appStateProvider).refreshRouterSession();
    if (!ok || !ref.context.mounted) return null;
    final session = ref.read(sessionProvider);
    final api = ref.read(apiServiceProvider);
    if (session == null || api == null) return null;
    return RtwrtApi(api, session);
  }

  static Future<RtwrtApi> _freshen(
    RtwrtApi api,
    Future<RtwrtApi?> Function()? refresh,
  ) async {
    if (refresh == null || await _ready(api)) return api;
    return await refresh() ?? api;
  }

  static Future<bool> _aclHasNlbw(RtwrtApi api) async {
    try {
      final text = await api.shell(
        'grep -q nlbwmon-action /usr/share/rpcd/acl.d/luci-app-rtwrt.json && echo ACL_OK',
      );
      return text.contains('ACL_OK');
    } catch (_) {
      return false;
    }
  }

  static Future<ConnectorResult> _finishNlbwmon(
    RtwrtApi api,
    ConnectorResult connector,
    Future<RtwrtApi?> Function()? refresh,
  ) async {
    if (connector.outcome == ConnectorOutcome.failed) return connector;
    try {
      final text = await api.shell(r'''
if [ -x /usr/libexec/nlbwmon-action ]; then
  if [ -x /etc/init.d/nlbwmon ]; then
    /etc/init.d/nlbwmon enabled >/dev/null 2>&1 || /etc/init.d/nlbwmon enable
    pidof nlbwmon >/dev/null 2>&1 || /etc/init.d/nlbwmon start
  fi
  echo NLBW_READY
else
  if command -v apk >/dev/null 2>&1; then
    apk add nlbwmon luci-app-nlbwmon
  elif command -v opkg >/dev/null 2>&1; then
    opkg update
    opkg install nlbwmon luci-app-nlbwmon
  else
    echo NO_PKG
  fi
  if [ -x /etc/init.d/nlbwmon ]; then
    /etc/init.d/nlbwmon enable
    /etc/init.d/nlbwmon start
  fi
  if [ -x /usr/libexec/nlbwmon-action ]; then
    echo NLBW_INSTALLED
  else
    echo NLBW_FAIL
  fi
fi
''');
      if (text.contains('NLBW_INSTALLED')) {
        if (refresh != null) await refresh();
        return const ConnectorResult(
          ConnectorOutcome.installed,
          'The connector is in place and the bandwidth monitor is installed.',
        );
      }
      if (text.contains('NLBW_READY')) return connector;
      final detail = text.contains('NO_PKG')
          ? 'This router has no package tool, so nlbwmon was not installed.'
          : text.trim();
      return ConnectorResult(
        ConnectorOutcome.failed,
        'The connector is in place. The bandwidth monitor was not installed.\n\n$detail',
      );
    } catch (e) {
      return ConnectorResult(
        ConnectorOutcome.failed,
        'The connector is in place. The bandwidth monitor was not installed.\n\n${RtwrtApi.explain(e)}',
      );
    }
  }

  static Future<ConnectorResult> ensure(
    RtwrtApi api, {
    Future<RtwrtApi?> Function()? refresh,
  }) {
    return install(api, refresh: refresh);
  }

  static Future<ConnectorResult> install(
    RtwrtApi api, {
    Future<RtwrtApi?> Function()? refresh,
  }) async {
    api = await _freshen(api, refresh);
    if (await _ready(api) && await _aclHasNlbw(api)) {
      return _finishNlbwmon(
        api,
        const ConnectorResult(
          ConnectorOutcome.ready,
          'The router connector is already in place.',
        ),
        refresh,
      );
    }
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
    if (!body.contains('"luci-app-rtwrt"') ||
        !body.trimLeft().startsWith('{')) {
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
        final written = await _afterWrite(api, refresh);
        if (written.outcome == ConnectorOutcome.failed) return written;
        final next = refresh == null ? api : await refresh() ?? api;
        return await _finishNlbwmon(next, written, refresh);
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
      } catch (writeError) {
        final refreshed = await _afterWrite(api, refresh);
        if (refreshed.outcome != ConnectorOutcome.failed) return refreshed;
        return ConnectorResult(
          ConnectorOutcome.failed,
          RtwrtApi.explain(writeError),
        );
      }
      final written = await _afterWrite(api, refresh);
      if (written.outcome == ConnectorOutcome.failed) return written;
      final next = refresh == null ? api : await refresh() ?? api;
      return await _finishNlbwmon(next, written, refresh);
    }
  }

  static Future<ConnectorResult> _afterWrite(
    RtwrtApi api,
    Future<RtwrtApi?> Function()? refresh,
  ) async {
    final next = refresh == null ? api : await refresh() ?? api;
    if (await _ready(next)) {
      return const ConnectorResult(
        ConnectorOutcome.installed,
        'The connector is installed and this login can use it.',
      );
    }
    return const ConnectorResult(
      ConnectorOutcome.failed,
      'The connector is on the router. Settings, Logout, then sign in again.',
    );
  }
}
