import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ProgressStore {
  static const _kBookList = 'books_opened_v1'; // tủ sách

  static String _keyProgress(String bookId) => 'progress_v1_$bookId';

  /// bookId ổn định theo file: path + size + modified
  static String makeBookId({
    required String path,
    required int size,
    required int modifiedMillis,
  }) {
    return base64Url.encode(utf8.encode('$path|$size|$modifiedMillis'));
  }

  static Future<void> saveProgress({
    required String bookId,
    required String title,
    required String path,
    required int pageIndex,
    required int totalPages,
  }) async {
    final sp = await SharedPreferences.getInstance();

    final data = <String, dynamic>{
      'bookId': bookId,
      'title': title,
      'path': path,
      'pageIndex': pageIndex,
      'totalPages': totalPages,
      'lastReadAt': DateTime.now().millisecondsSinceEpoch,
    };

    // 1) lưu tiến độ
    await sp.setString(_keyProgress(bookId), jsonEncode(data));

    // 2) cập nhật tủ sách: đưa quyển này lên đầu
    final raw = sp.getString(_kBookList);
    final List list = raw == null ? [] : (jsonDecode(raw) as List);
    list.removeWhere((e) => e is Map && e['bookId'] == bookId);
    list.insert(0, data);

    // giới hạn 200 quyển gần nhất
    if (list.length > 200) list.removeRange(200, list.length);

    await sp.setString(_kBookList, jsonEncode(list));
  }

  static Future<Map<String, dynamic>?> loadProgress(String bookId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_keyProgress(bookId));
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<List<Map<String, dynamic>>> loadLibrary() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kBookList);
    if (raw == null) return [];
    final List list = jsonDecode(raw) as List;
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
} import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ProgressStore {
  static const _kBookList = 'books_opened_v1'; // tủ sách

  static String _keyProgress(String bookId) => 'progress_v1_$bookId';

  /// bookId ổn định theo file: path + size + modified
  static String makeBookId({
    required String path,
    required int size,
    required int modifiedMillis,
  }) {
    return base64Url.encode(utf8.encode('$path|$size|$modifiedMillis'));
  }

  static Future<void> saveProgress({
    required String bookId,
    required String title,
    required String path,
    required int pageIndex,
    required int totalPages,
  }) async {
    final sp = await SharedPreferences.getInstance();

    final data = <String, dynamic>{
      'bookId': bookId,
      'title': title,
      'path': path,
      'pageIndex': pageIndex,
      'totalPages': totalPages,
      'lastReadAt': DateTime.now().millisecondsSinceEpoch,
    };

    // 1) lưu tiến độ
    await sp.setString(_keyProgress(bookId), jsonEncode(data));

    // 2) cập nhật tủ sách: đưa quyển này lên đầu
    final raw = sp.getString(_kBookList);
    final List list = raw == null ? [] : (jsonDecode(raw) as List);
    list.removeWhere((e) => e is Map && e['bookId'] == bookId);
    list.insert(0, data);

    // giới hạn 200 quyển gần nhất
    if (list.length > 200) list.removeRange(200, list.length);

    await sp.setString(_kBookList, jsonEncode(list));
  }

  static Future<Map<String, dynamic>?> loadProgress(String bookId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_keyProgress(bookId));
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<List<Map<String, dynamic>>> loadLibrary() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kBookList);
    if (raw == null) return [];
    final List list = jsonDecode(raw) as List;
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
