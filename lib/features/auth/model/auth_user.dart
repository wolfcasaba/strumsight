import 'package:flutter/foundation.dart';

/// A signed-in account (the public shape returned by `GET /auth/me`).
@immutable
class AuthUser {
  const AuthUser({required this.id, required this.email});

  final int id;
  final String email;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as int,
        email: json['email'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}
