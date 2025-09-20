// lib/models/journal_entry.dart

class JournalEntry {
  final int? id;
  final String title;
  final String body;
  final DateTime date;

  JournalEntry({
    this.id,
    required this.title,
    required this.body,
    required this.date,
  });

  /// Converts a JournalEntry object into a Map for sending to the backend
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'date': date.toIso8601String(), // Store date as ISO 8601 string
    };
  }

  /// Creates a JournalEntry object from a Map received from the backend
  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    return JournalEntry(
      id: map['id'] is int ? map['id'] : null,
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
    );
  }
}
