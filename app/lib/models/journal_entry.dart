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

  // A helper method to convert our object to a Map for the database.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'date': date.toIso8601String(), // Store date as a string
    };
  }
}