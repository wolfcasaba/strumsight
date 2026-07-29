import 'package:flutter/foundation.dart';

/// A signed-in account (the public shape returned by `GET /auth/me`).
@immutable
class AuthUser {
  const AuthUser({required this.id, required this.email});

  final int id;
  final String email;

  factory AuthUser.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final email = json['email'];
    if (id is! int || id <= 0) {
      throw const FormatException('Invalid account user ID.');
    }
    final separator = email is String ? email.indexOf('@') : -1;
    if (email is! String ||
        separator <= 0 ||
        separator != email.lastIndexOf('@') ||
        separator >= email.length - 1) {
      throw const FormatException('Invalid account user e-mail.');
    }
    return AuthUser(id: id, email: email);
  }

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}
