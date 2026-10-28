import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/rtwrt/package_publish.dart';
import 'package:luci_mobile/rtwrt/modem_screen.dart';
import 'package:luci_mobile/rtwrt/storage_manager_screen.dart';
import 'package:luci_mobile/rtwrt/netstat_screen.dart';
import 'package:luci_mobile/rtwrt/bandix_screen.dart';

void main() {
  group('Package Installation Commands', () {
    test('detects apk vs ipk extensions accurately', () {
      expect(isApkPackage('/tmp/pkg.apk'), isTrue);
      expect(isApkPackage('file.APK'), isTrue);
      expect(isApkPackage('archive.ipk'), isFalse);
      expect(isApkPackage('file.IPK'), isFalse);
    });

    test('generates exact force install command for Alpine .apk packages', () {
      final line = packageInstallLine('/tmp/app.apk', apk: true, force: true);
      expect(line, 'apk add --force-broken-world --allow-untrusted /tmp/app.apk');
    });

    test('generates exact standard install command for .apk packages', () {
      final line = packageInstallLine('/tmp/app.apk', apk: true, force: false);
      expect(line, 'apk add --allow-untrusted /tmp/app.apk');
    });

    test('generates exact force install command for OpenWrt .ipk packages', () {
      final line = packageInstallLine('/tmp/app.ipk', apk: false, force: true);
      expect(line, contains('opkg install --force-depends --force-overwrite /tmp/app.ipk'));
    });

    test('named package install uses exact force flags', () {
      final line = namedPackageInstall('luci-app-vantage', force: true);
      expect(line, contains('apk add --force-broken-world --allow-untrusted luci-app-vantage'));
      expect(line, contains('opkg install --force-depends --force-overwrite luci-app-vantage'));
    });
  });

  group('SMS Interface Model', () {
    test('parses sms_tool json message object', () {
      final json = {
        'index': 1,
        'sender': '66628',
        'timestamp': '10/28/26 12:06:56',
        'content': 'Test SMS content from carrier',
      };
      final msg = SmsMessage.fromJson(json);
      expect(msg.index, 1);
      expect(msg.sender, '66628');
      expect(msg.timestamp, '10/28/26 12:06:56');
      expect(msg.content, 'Test SMS content from carrier');
    });
  });

  group('Storage Capacity & Disk Manager Model', () {
    test('parses df -h lines into partition stats', () {
      const line = '/dev/ubi0_2             154.6M     16.7M    133.2M  11% /overlay';
      final part = PartitionInfo.fromLine(line);
      expect(part.mount, '/overlay');
      expect(part.size, '154.6M');
      expect(part.used, '16.7M');
      expect(part.available, '133.2M');
      expect(part.usePercent, '11%');
      expect(part.ratio, closeTo(0.11, 0.01));
    });
  });

  group('Netstat Model', () {
    test('parses netstat -tulpen lines into connection entries', () {
      const line = 'tcp        0      0 127.0.0.1:8686          0.0.0.0:*               LISTEN      20033/bandix';
      final entry = NetstatEntry.fromLine(line);
      expect(entry.proto, 'tcp');
      expect(entry.localAddress, '127.0.0.1:8686');
      expect(entry.state, 'LISTEN');
      expect(entry.pidProgram, '20033/bandix');
    });
  });

  group('Bandix Model', () {
    test('parses bandix ubus device status object', () {
      final json = {
        'ip4': '192.168.1.100',
        'mac': '00:11:22:33:44:55',
        'host': 'laptop.lan',
        't_rx_r': 1048576,
        't_tx_r': 524288,
        't_rx_b': 50000000,
        't_tx_b': 20000000,
      };
      final dev = BandixDevice.fromJson(json);
      expect(dev.ip, '192.168.1.100');
      expect(dev.host, 'laptop.lan');
      expect(dev.rxRate, 1048576);
      expect(dev.txRate, 524288);
      expect(dev.totalRxBytes, 50000000);
      expect(dev.totalTxBytes, 20000000);
    });
  });
}
