import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Phone-local order, pins, and hidden tiles for the RTWRT hub.
class RtwrtLayout {
  const RtwrtLayout({
    required this.order,
    required this.hidden,
    required this.pins,
  });

  final List<String> order;
  final Set<String> hidden;
  final List<String> pins;

  static const maxPins = 4;

  static RtwrtLayout defaults(List<String> ids) => RtwrtLayout(
    order: List<String>.of(ids),
    hidden: const {},
    pins: const [],
  );

  List<String> visible(List<String> known) {
    final ranked = <String>[
      for (final id in order)
        if (known.contains(id) && !hidden.contains(id) && !pins.contains(id))
          id,
      for (final id in known)
        if (!order.contains(id) && !hidden.contains(id) && !pins.contains(id))
          id,
    ];
    final pinRow = <String>[
      for (final id in pins)
        if (known.contains(id) && !hidden.contains(id)) id,
    ];
    return [...pinRow, ...ranked];
  }

  RtwrtLayout move(int from, int to) {
    final next = List<String>.of(order);
    if (from < 0 || from >= next.length || to < 0 || to >= next.length) {
      return this;
    }
    final item = next.removeAt(from);
    next.insert(to, item);
    return RtwrtLayout(order: next, hidden: hidden, pins: pins);
  }

  RtwrtLayout toggleHidden(String id) {
    final next = Set<String>.of(hidden);
    if (!next.add(id)) next.remove(id);
    final nextPins = [
      for (final pin in pins)
        if (pin != id || !next.contains(id)) pin,
    ];
    return RtwrtLayout(order: order, hidden: next, pins: nextPins);
  }

  RtwrtLayout togglePin(String id) {
    final next = List<String>.of(pins);
    if (next.contains(id)) {
      next.remove(id);
    } else if (next.length < maxPins) {
      next.add(id);
    }
    return RtwrtLayout(order: order, hidden: hidden, pins: next);
  }
}

class LayoutStore {
  static const _key = 'rtwrt-layout-v1';

  Future<RtwrtLayout> load(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return RtwrtLayout.defaults(ids);
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return RtwrtLayout.defaults(ids);
      final order = [
        for (final id in (json['order'] as List? ?? const <dynamic>[]))
          if (id is String && ids.contains(id)) id,
        for (final id in ids)
          if (!(json['order'] as List? ?? const []).contains(id)) id,
      ];
      final hidden = {
        for (final id in (json['hidden'] as List? ?? const <dynamic>[]))
          if (id is String && ids.contains(id)) id,
      };
      final pins = [
        for (final id in (json['pins'] as List? ?? const <dynamic>[]))
          if (id is String && ids.contains(id) && !hidden.contains(id)) id,
      ].take(RtwrtLayout.maxPins).toList();
      return RtwrtLayout(order: order, hidden: hidden, pins: pins);
    } catch (_) {
      return RtwrtLayout.defaults(ids);
    }
  }

  Future<void> save(RtwrtLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'order': layout.order,
        'hidden': layout.hidden.toList(),
        'pins': layout.pins,
      }),
    );
  }
}
