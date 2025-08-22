// lib/services/database_service.dart

import 'package:path/path.dart';
import 'package:sahara_app/models/action_item.dart';
import 'package:sahara_app/models/journal_entry.dart';
import 'package:sqflite/sqflite.dart';

// The class has been renamed for clarity, as it now handles more than just journals.
class DatabaseService {
  static Database? _database;
  static const String _journalTableName = 'journal_entries';
  static const String _actionTableName = 'action_items'; // The name for our new table

  // Singleton instance
  DatabaseService._privateConstructor();
  static final DatabaseService instance = DatabaseService._privateConstructor();

  // Getter for the database, remains the same
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  // Initialize the database, now pointing to a new DB file name
  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    // Using a new DB file name ensures a clean slate upon upgrade.
    final path = join(dbPath, 'sahara_main.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  // Create BOTH database tables
  Future<void> _createDB(Database db, int version) async {
    // 1. Create the original journal entries table
    await db.execute('''
      CREATE TABLE $_journalTableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        date TEXT NOT NULL
      )
    ''');

    // 2. NEW: Create the new action items table
    await db.execute('''
      CREATE TABLE $_actionTableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        isCompleted INTEGER NOT NULL,
        dateAdded TEXT NOT NULL
      )
    ''');
  }

  // --- Journal Methods (copied from your original file) ---

  Future<void> createJournalEntry(JournalEntry entry) async {
    final db = await database;
    await db.insert(
      _journalTableName,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<JournalEntry>> getJournalEntries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_journalTableName, orderBy: 'date DESC');

    return List.generate(maps.length, (i) {
      return JournalEntry(
        id: maps[i]['id'],
        title: maps[i]['title'],
        body: maps[i]['body'],
        date: DateTime.parse(maps[i]['date']),
      );
    });
  }


  // --- NEW Action Item Methods ---

  Future<void> createActionItem(ActionItem item) async {
    final db = await database;
    await db.insert(
      _actionTableName,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ActionItem>> getActionItems() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_actionTableName, orderBy: 'dateAdded DESC');

    return List.generate(maps.length, (i) {
      return ActionItem(
        id: maps[i]['id'],
        title: maps[i]['title'],
        description: maps[i]['description'],
        isCompleted: maps[i]['isCompleted'] == 1, // Convert integer (0 or 1) back to boolean
        dateAdded: DateTime.parse(maps[i]['dateAdded']),
      );
    });
  }

  Future<void> updateActionItem(ActionItem item) async {
    final db = await database;
    await db.update(
      _actionTableName,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> deleteActionItem(int id) async {
    final db = await database;
    await db.delete(
      _actionTableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  // Inside the DatabaseService class

// --- NEW METHOD ---
Future<bool> doesActionItemExist(String title) async {
  final db = await database;
  final List<Map<String, dynamic>> maps = await db.query(
    _actionTableName,
    where: 'title = ? AND isCompleted = ?',
    whereArgs: [title, 0], // Check for an item with the same title that is NOT completed
  );
  return maps.isNotEmpty;
}





}