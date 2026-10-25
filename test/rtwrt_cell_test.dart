import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/rtwrt/rtwrt_api.dart';

void main() {
  test('parses a 5G serving cell', () {
    const raw =
        '+QENG: "servingcell","NOCONN","NR5G-SA","TDD",502,153,1234567,321,ABCDEF,633696,78,12,-86,-11,24,0,30';
    final cell = ServingCell.parse(raw);
    expect(cell.rat, 'NR5G-SA');
    expect(cell.band, '78');
    expect(cell.pci, '321');
    expect(cell.arfcn, '633696');
    expect(cell.rsrp, '-86');
    expect(cell.sinr, '24');
  });

  test('parses an LTE serving cell', () {
    const raw =
        '+QENG: "servingcell","NOCONN","LTE","FDD",502,153,1,55,100,3,3,3,1,-90,-12,-60,10,7,0,0';
    final cell = ServingCell.parse(raw);
    expect(cell.rat, 'LTE');
    expect(cell.band, '3');
    expect(cell.rsrp, '-90');
    expect(cell.rssi, '-60');
    expect(cell.sinr, '10');
  });
}
