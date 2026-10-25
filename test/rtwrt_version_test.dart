import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/rtwrt/github_release.dart';

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
    expect(
      isRicheeGithubUrl('https://example.com/RTWRT.apk'),
      isFalse,
    );
    expect(isRicheeGithubUrl('http://github.com/richee-bot/rtwrt-app'), isFalse);
  });
}
