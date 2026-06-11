class Reservation {
  final int? id;
  final String? cloudId;
  final int itemId;
  final String nickname;
  final String roomName;
  final DateTime createdAt;

  Reservation({
    this.id,
    this.cloudId,
    required this.itemId,
    required this.nickname,
    required this.roomName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'cloud_id': cloudId,
        'item_id': itemId,
        'nickname': nickname,
        'room_name': roomName,
        'created_at': createdAt.toIso8601String(),
      };

  factory Reservation.fromMap(Map<String, dynamic> map) => Reservation(
        id: map['id'],
        cloudId: map['cloud_id'],
        itemId: map['item_id'],
        nickname: map['nickname'],
        roomName: map['room_name'],
        createdAt: DateTime.parse(map['created_at']),
      );
}
