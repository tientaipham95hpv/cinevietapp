import 'app_user.dart';

class MovieComment {
  const MovieComment({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.userName,
    this.userAvatar,
    this.rating,
    this.likeCount = 0,
    this.userLiked = false,
    this.isSpoiler = false,
  });

  final int id;
  final int userId;
  final String content;
  final DateTime createdAt;
  final String? userName;
  final String? userAvatar;
  final int? rating;
  final int likeCount;
  final bool userLiked;
  final bool isSpoiler;

  factory MovieComment.fromJson(Map<String, dynamic> json) => MovieComment(
    id: int.tryParse('${json['id'] ?? 0}') ?? 0,
    userId: int.tryParse('${json['user_id'] ?? 0}') ?? 0,
    content: '${json['content'] ?? ''}',
    createdAt:
        DateTime.tryParse('${json['created_at'] ?? ''}') ?? DateTime.now(),
    userName:
        (json['user_name'] ?? json['user']?['name'] ?? json['author']?['name'])
            ?.toString(),
    userAvatar: normalizeUserAvatarUrl(
      (json['user_avatar'] ??
              json['avatar'] ??
              json['user']?['avatar'] ??
              json['user']?['avatar_url'] ??
              json['user']?['profile_photo_url'] ??
              json['author']?['avatar'] ??
              json['author']?['avatar_url'])
          ?.toString(),
    ),
    rating: int.tryParse('${json['rating'] ?? ''}'),
    likeCount: int.tryParse('${json['like_count'] ?? 0}') ?? 0,
    userLiked: json['user_liked'] == true || json['user_liked'] == 1,
    isSpoiler: json['is_spoiler'] == true || json['is_spoiler'] == 1,
  );
}
