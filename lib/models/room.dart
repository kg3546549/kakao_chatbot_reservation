enum RoomType { reservation, admin, general }

extension RoomTypeExtension on RoomType {
  String get label {
    switch (this) {
      case RoomType.reservation: return '예약방';
      case RoomType.admin: return '관리자방';
      case RoomType.general: return '일반방(무시)';
    }
  }
}

class Room {
  final int? id;
  final String name;
  final RoomType type;

  Room({this.id, required this.name, this.type = RoomType.general});

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type.index,
  };

  factory Room.fromMap(Map<String, dynamic> map) => Room(
    id: map['id'],
    name: map['name'],
    type: RoomType.values[map['type']],
  );
}
