import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luci_mobile/models/contact.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactsNotifier extends Notifier<List<Contact>> {
  static const _key = 'rtwrt_saved_contacts';

  @override
  List<Contact> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          state = decoded
              .whereType<Map>()
              .map((m) => Contact.fromJson(Map<String, dynamic>.from(m)))
              .toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        }
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(state.map((c) => c.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  Future<void> addContact(String name, String number) async {
    final newContact = Contact(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim(),
      number: number.trim(),
    );
    final updated = List<Contact>.from(state)..add(newContact);
    updated.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = updated;
    await _save();
  }

  Future<void> editContact(String id, String name, String number) async {
    state = [
      for (final c in state)
        if (c.id == id) c.copyWith(name: name.trim(), number: number.trim()) else c
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _save();
  }

  Future<void> deleteContact(String id) async {
    state = state.where((c) => c.id != id).toList();
    await _save();
  }

  String resolveName(String number) {
    if (number.trim().isEmpty) return '';
    final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return number;
    for (final c in state) {
      final cDigits = c.number.replaceAll(RegExp(r'[^0-9]'), '');
      if (cDigits == digits) return c.name;
      if (digits.length >= 8 && cDigits.length >= 8) {
        final sub1 = digits.substring(digits.length - 8);
        final sub2 = cDigits.substring(cDigits.length - 8);
        if (sub1 == sub2) return c.name;
      }
    }
    return number;
  }
}

final contactsProvider = NotifierProvider<ContactsNotifier, List<Contact>>(
  ContactsNotifier.new,
);
