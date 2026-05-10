import 'package:shared_preferences/shared_preferences.dart';

class StopwatchService {
  static const String _gymStartTimeKey = 'gym_stopwatch_start_time';
  static const String _gymRunningKey = 'gym_stopwatch_running';
  static const String _academicStartTimeKey = 'academic_stopwatch_start_time';
  static const String _academicRunningKey = 'academic_stopwatch_running';

  // Gym stopwatch methods
  static Future<void> saveGymStopwatchStart(int startTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gymStartTimeKey, startTime);
    await prefs.setBool(_gymRunningKey, true);
  }

  static Future<void> clearGymStopwatch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_gymStartTimeKey);
    await prefs.remove(_gymRunningKey);
  }

  static Future<bool> isGymStopwatchRunning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_gymRunningKey) ?? false;
  }

  static Future<int> getGymElapsedSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final startTime = prefs.getInt(_gymStartTimeKey);
    if (startTime == null) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = now - startTime;
    return (elapsedMs / 1000).round();
  }

  static Future<void> pauseGymStopwatch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gymRunningKey, false);
  }

  // Academic stopwatch methods
  static Future<void> saveAcademicStopwatchStart(int startTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_academicStartTimeKey, startTime);
    await prefs.setBool(_academicRunningKey, true);
  }

  static Future<void> clearAcademicStopwatch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_academicStartTimeKey);
    await prefs.remove(_academicRunningKey);
  }

  static Future<bool> isAcademicStopwatchRunning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_academicRunningKey) ?? false;
  }

  static Future<int> getAcademicElapsedSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final startTime = prefs.getInt(_academicStartTimeKey);
    if (startTime == null) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = now - startTime;
    return (elapsedMs / 1000).round();
  }

  static Future<void> pauseAcademicStopwatch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_academicRunningKey, false);
  }

  // Running stopwatch methods
  static const String _runningStartTimeKey = 'running_stopwatch_start_time';
  static const String _runningRunningKey = 'running_stopwatch_running';

  static Future<void> saveRunningStopwatchStart(int startTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_runningStartTimeKey, startTime);
    await prefs.setBool(_runningRunningKey, true);
  }

  static Future<void> clearRunningStopwatch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_runningStartTimeKey);
    await prefs.remove(_runningRunningKey);
  }

  static Future<bool> isRunningStopwatchRunning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_runningRunningKey) ?? false;
  }

  static Future<int> getRunningElapsedSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final startTime = prefs.getInt(_runningStartTimeKey);
    if (startTime == null) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return ((now - startTime) / 1000).round();
  }

  // Luminary stopwatch methods
  static const String _luminaryStartTimeKey = 'luminary_stopwatch_start_time';
  static const String _luminaryRunningKey = 'luminary_stopwatch_running';

  static Future<void> saveLuminaryStopwatchStart(int startTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_luminaryStartTimeKey, startTime);
    await prefs.setBool(_luminaryRunningKey, true);
  }

  static Future<void> clearLuminaryStopwatch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_luminaryStartTimeKey);
    await prefs.remove(_luminaryRunningKey);
  }

  static Future<bool> isLuminaryStopwatchRunning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_luminaryRunningKey) ?? false;
  }

  static Future<int> getLuminaryElapsedSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final startTime = prefs.getInt(_luminaryStartTimeKey);
    if (startTime == null) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return ((now - startTime) / 1000).round();
  }
}
