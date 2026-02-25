import 'app_role.dart';

class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String username;
  final String fullName;
  final AppRole role;

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      username: map['username'] as String? ?? '',
      fullName: map['full_name'] as String? ?? '',
      role: AppRole.fromString(map['role'] as String? ?? 'employee'),
    );
  }
}
