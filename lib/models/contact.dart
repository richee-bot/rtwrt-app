import 'package:flutter/foundation.dart';

@immutable
class Contact {
  final String id;
  final String name;
  final String number;

  const Contact({
    required this.id,
    required this.name,
    required this.number,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'number': number,
  };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    number: json['number']?.toString() ?? '',
  );

  Contact copyWith({
    String? id,
    String? name,
    String? number,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      number: number ?? this.number,
    );
  }
}
