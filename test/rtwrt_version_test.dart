import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/rtwrt/app_token.dart';
import 'package:luci_mobile/rtwrt/broadcast.dart';
import 'package:luci_mobile/rtwrt/github_release.dart';
import 'package:luci_mobile/rtwrt/package_publish.dart';
import 'package:luci_mobile/rtwrt/uci_browser_screen.dart';

void main() {
  test('a higher GitHub version is newer', () {
    expect(isNewerVersion('v2.2.0', '2.1.0'), isTrue);
    expect(isNewerVersion('2.2.0', '2.2.0'), isFalse);
    expect(isNewerVersion('2.1.1', '2.2.0'), isFalse);
  });

  test('only richee-bot GitHub URLs are accepted', () {
    expect(
      isRicheeGithubUrl(
        'https://github.com/richee-bot/rtwrt-app/releases/download/v2.2.0/RTWRT.apk',
      ),
      isTrue,
    );
    expect(isRicheeGithubUrl('https://example.com/RTWRT.apk'), isFalse);
    expect(
      isRicheeGithubUrl('http://github.com/richee-bot/rtwrt-app'),
      isFalse,
    );
  });

  test('software packages keep only tagged GitHub files', () {
    final packages = routerPackagesFrom({
      'packages': [
        {
          'name': 'luci-app-passwall2',
          'note': 'PassWall 2',
          'ipk_url':
              'https://github.com/richee-bot/rtwrt-aw1000-firmware/releases/download/ipk-luci-app-passwall2/luci-app-passwall2_26.3.5-r1_all.ipk',
        },
        {'name': 'bad', 'ipk_url': 'https://example.com/evil.ipk'},
      ],
    });
    expect(packages, hasLength(1));
    expect(packages.single.name, 'luci-app-passwall2');
    expect(packages.single.url, contains('/ipk-luci-app-passwall2/'));
  });

  test('package names and force install lines', () {
    expect(
      packageNameFromFile('luci-app-passwall2_26.3.5-r1_all.ipk'),
      'luci-app-passwall2',
    );
    expect(
      packageNameFromFile('xray-core_26.10.17-r1_aarch64_cortex-a53.ipk'),
      'xray-core',
    );
    expect(
      packageInstallLine('/tmp/rtwrt-package.ipk', apk: false, force: true),
      contains('--force-depends'),
    );
    expect(
      packageInstallLine('/tmp/rtwrt-package.ipk', apk: false, force: false),
      isNot(contains('--force-depends')),
    );
    expect(
      packageInstallLine('/tmp/rtwrt-package.apk', apk: true, force: true),
      contains('--force-overwrite'),
    );
  });

  test('LED modes match the router package', () {
    expect(ledModeLabels.length, 12);
    expect(ledModeLabels['police'], 'Cyber Emergency Strobe');
    expect(ledModeLabels.containsKey('waves'), isTrue);
    expect(qmodemDialModes, contains('gobinet'));
    expect(ledTimingChoices, ['15', '30', '60']);
  });

  test('telegram names drop the @ sign', () {
    expect(normalizeTelegramUser(' @Richee_Tayu '), 'Richee_Tayu');
    expect(appTokenMatches('not-the-token'), isFalse);
  });

  test('a dismissed broadcast stays hidden until the text changes', () {
    final msg = broadcastFrom({
      'id': 3,
      'active': true,
      'title': 'RTWRT notice',
      'body': 'Hello',
    });
    expect(msg, isNotNull);
    expect(
      broadcastVisible(
        msg: msg!,
        dismissedFingerprint: msg.fingerprint,
        dismissedId: 0,
      ),
      isFalse,
    );
    final next = broadcastFrom({
      'id': 3,
      'active': true,
      'title': 'RTWRT notice',
      'body': 'Hello again',
    })!;
    expect(
      broadcastVisible(
        msg: next,
        dismissedFingerprint: msg.fingerprint,
        dismissedId: 3,
      ),
      isTrue,
    );
    expect(broadcastFrom({'id': 1, 'active': false, 'body': 'x'}), isNull);
  });
}
