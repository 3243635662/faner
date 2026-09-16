import 'package:shared_preferences/shared_preferences.dart';

/// 视频播放位置记忆（key → 已播放秒数）。
///
/// key 用 [MediaSource.heroTag]（本地绝对路径 / 远端 URL）。
class VideoResumeStore {
  VideoResumeStore._();

  static const _prefix = 'video_resume_';

  static Future<Duration?> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seconds = prefs.getInt('$_prefix$key');
      if (seconds == null || seconds <= 0) return null;
      return Duration(seconds: seconds);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String key, Duration position) async {
    if (position.inSeconds <= 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_prefix$key', position.inSeconds);
    } catch (_) {
      // 忽略写入失败
    }
  }

  /// 清除所有视频播放进度（设置页「清除播放进度」用）。
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {
      // 忽略
    }
  }
}
