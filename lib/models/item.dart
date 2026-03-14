class Item {
  final int? id;
  final String name;
  final int maxCapacity;
  final String template;

  Item({this.id, required this.name, this.maxCapacity = 10, this.template = ""});

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'max_capacity': maxCapacity,
    'template': template,
  };

  factory Item.fromMap(Map<String, dynamic> map) => Item(
    id: map['id'],
    name: map['name'],
    maxCapacity: map['max_capacity'],
    template: map['template'],
  );
}
