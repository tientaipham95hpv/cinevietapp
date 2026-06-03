import 'movie.dart';

String normalizeUserAvatarUrl(String? value) => normalizeImageUrl(value);

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    this.avatar,
    this.role,
    this.emailVerified = false,
    this.isVip = false,
  });
  final int id;
  final String email;
  final String name;
  final String? avatar;
  final String? role;
  final bool emailVerified;
  final bool isVip;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: int.tryParse('${json['id']}') ?? 0,
    email: '${json['email'] ?? ''}',
    name: '${json['name'] ?? 'User'}',
    avatar: normalizeUserAvatarUrl(
      (json['avatar'] ??
              json['avatar_url'] ??
              json['profile_photo_url'] ??
              json['photo_url'] ??
              json['image'])
          ?.toString(),
    ),
    role: json['role']?.toString(),
    emailVerified:
        '${json['email_verified'] ?? 0}' == '1' ||
        json['email_verified'] == true,
    isVip: '${json['is_vip'] ?? 0}' == '1' || json['is_vip'] == true,
  );
}
