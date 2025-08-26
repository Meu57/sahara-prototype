import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';

class SessionService {
  static const _keyUserId = 'anonymous_user_id';
  static final Logger _logger = Logger();

  // Get the current user's ID, or create one if it doesn't exist.
  static Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getString(_keyUserId);
    if (userId == null) {
      userId = Uuid().v4(); // No 'const' here
      await prefs.setString(_keyUserId, userId);
      _logger.i('New client-side anonymous user ID created: $userId');
    }
    return userId;
  }

  // This is the new helper to save an ID given by the server.
  static Future<void> setUserId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, id);
    _logger.i('Server-provided anonymous user ID has been saved: $id');
  }
}
