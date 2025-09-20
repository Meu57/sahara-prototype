// lib/models/action_item.dart

class ActionItem {
  final String id; // Firestore document ID
  final String title;
  final String description;
  final String resourceId; // Used for linking to a resource
  final bool isCompleted;
  final DateTime dateAdded;

  ActionItem({
    required this.id,
    required this.title,
    required this.description,
    required this.resourceId,
    this.isCompleted = false,
    required this.dateAdded,
  });

  // ✅ Factory constructor for backend deserialization
  factory ActionItem.fromJson(Map<String, dynamic> json) {
    return ActionItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      resourceId: json['resourceId'] ?? json['resource_id'] ?? '',
      isCompleted: () {
  final v = json['isCompleted'];
  if (v is bool) return v;
  if (v is int) return v == 1;
  if (v is String) return v.toLowerCase() == 'true';
  return false;
}(),

      dateAdded: () {
  final value = json['dateAdded'];
  if (value == null) return DateTime.now();

  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }

  if (value is Map) {
    // Read raw parts (Firestore may use 'seconds' or '_seconds')
    final dynamic secondsRaw = value['seconds'] ?? value['_seconds'];
    final dynamic nanosRaw = value['nanoseconds'] ?? value['_nanoseconds'] ?? 0;

    // Convert to ints safely
    int seconds;
    if (secondsRaw is int) {
      seconds = secondsRaw;
    } else if (secondsRaw is num) {
      seconds = secondsRaw.toInt();
    } else if (secondsRaw is String) {
      seconds = int.tryParse(secondsRaw) ?? 0;
    } else {
      seconds = 0;
    }

    int nanos;
    if (nanosRaw is int) {
      nanos = nanosRaw;
    } else if (nanosRaw is num) {
      nanos = nanosRaw.toInt();
    } else if (nanosRaw is String) {
      nanos = int.tryParse(nanosRaw) ?? 0;
    } else {
      nanos = 0;
    }

    final int ms = seconds * 1000 + (nanos ~/ 1000000);
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }

  // fallback
  return DateTime.now();
}(),

    );
  }

  // ✅ Factory constructor for chat suggestion payloads
  factory ActionItem.fromSuggestionJson(Map<String, dynamic> json) {
    return ActionItem(
      id: '', // Suggestion doesn't have an ID yet
      title: json['title'] ?? '',
      description: 'Find this in the Resource Library.',
      resourceId: json['resource_id'] ?? json['resourceId'] ?? '',
      isCompleted: false,
      dateAdded: DateTime.now(),
    );
  }

  // ✅ Serialize for backend POST/PUT
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'resourceId': resourceId,
      'isCompleted': isCompleted,
      'dateAdded': dateAdded.toIso8601String(),
    };
  }

  // ✅ Local DB mapping
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'resourceId': resourceId,
      'isCompleted': isCompleted ? 1 : 0,
      'dateAdded': dateAdded.toIso8601String(),
    };
  }

  // ✅ Immutability for toggling and updates
  ActionItem copyWith({
    String? id,
    String? title,
    String? description,
    String? resourceId,
    bool? isCompleted,
    DateTime? dateAdded,
  }) {
    return ActionItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      resourceId: resourceId ?? this.resourceId,
      isCompleted: isCompleted ?? this.isCompleted,
      dateAdded: dateAdded ?? this.dateAdded,
    );
  }
}
