import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/rtwrt/layout_store.dart';

void main() {
  test('new ids land at the end and pins stay first', () {
    const layout = RtwrtLayout(
      order: ['modem', 'services'],
      hidden: {},
      pins: ['services'],
    );
    expect(layout.visible(['services', 'modem', 'tools']), [
      'services',
      'modem',
      'tools',
    ]);
  });

  test('a hidden tile stays off the home list', () {
    final layout = RtwrtLayout.defaults([
      'services',
      'modem',
    ]).toggleHidden('modem');
    expect(layout.visible(['services', 'modem']), ['services']);
  });

  test('pin stops at four', () {
    var layout = RtwrtLayout.defaults(['a', 'b', 'c', 'd', 'e']);
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      layout = layout.togglePin(id);
    }
    expect(layout.pins, ['a', 'b', 'c', 'd']);
  });
}
