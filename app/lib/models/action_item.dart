// lib/models/action_item.dart (UPDATED with copyWith)

class ActionItem {
  final int? id;
  final String title;
  final String description;
  final bool isCompleted;
  final DateTime dateAdded;

  ActionItem({
    this.id,
    required this.title,
    required this.description,
    this.isCompleted = false,
    required this.dateAdded,
  });

  // --- NEW METHOD ---
  ActionItem copyWith({
    int? id,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? dateAdded,
  }) {
    return ActionItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }
  // --- END OF NEW METHOD ---

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted ? 1 : 0,
      'dateAdded': dateAdded.toIso8601String(),
    };
  }
}