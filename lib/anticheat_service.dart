import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'lifting_utils.dart';
import 'rank_utils.dart';

/// Result of checking the daily effort cap.
enum DailyCapStatus { allowed, softCapped, hardCapped }

/// Central anticheat engine for Endeavour.
///
/// Provides:
/// - Context-aware anomaly detection (Suspicion Quotient) for every path
/// - 24-hour daily effort cap (1440 min)
/// - Daily effort tracking per path for challenge gating
class AnticheatService {
  static final _db = FirebaseFirestore.instance;

  // ═══════════════════════════════════════════════════════════════════════
  //  Constants
  // ═══════════════════════════════════════════════════════════════════════

  /// Hard cap: 24 hours = 1440 minutes total loggable per day.
  static const int maxDailyMinutes = 1440;

  /// Soft cap: 18 hours = 1080 minutes. Shows friendly popup + flags for review.
  static const int softCapMinutes = 1080;

  /// Wilks improvement per day thresholds, indexed by rank tier (0–5).
  static const List<double> _gymSuspicionThresholds = [
    3.0, // BRONZE
    2.0, // SILVER
    1.5, // GOLD
    1.0, // PLATINUM
    0.7, // DIAMOND
    0.5, // ENLIGHTENED
  ];

  /// 5K time improvement (seconds per day) thresholds, indexed by rank tier.
  static const List<double> _runningSuspicionThresholds = [
    5.0, // BRONZE
    3.0, // SILVER
    2.0, // GOLD
    1.5, // PLATINUM
    1.0, // DIAMOND
    0.5, // ENLIGHTENED
  ];

  /// Minutes of study required per grade point jump.
  static const double academicMinutesPerGradePoint = 30.0;

  /// Minutes of logged effort required per baseline-hour increase (luminary).
  static const double luminaryMinutesPerBaselineHour = 120.0;

  /// Number of flags in a 30-day window before auto-shadowban.
  static const int shadowbanFlagThreshold = 3;

  // ═══════════════════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════════════════

  static String _todayStr() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static int _daysBetween(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 365; // treat as very old
    try {
      final parts = dateStr.split('-');
      final old = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      return DateTime.now().difference(old).inDays.clamp(1, 9999);
    } catch (_) {
      return 365;
    }
  }

  static int _rankTier(int elo, List<Rank> ranks) {
    final rank = RankUtils.getRank(elo, ranks);
    final idx = ranks.indexOf(rank);
    return idx.clamp(0, ranks.length - 1);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  1. DAILY EFFORT CAP  (24h hard cap, 18h soft cap)
  //
  //  Stored as a `dailyEffort` map field on the user document (not a
  //  subcollection) so existing Firestore security rules apply.
  //  The map has a `date` key — if it doesn't match today, treat as empty.
  // ═══════════════════════════════════════════════════════════════════════

  /// Returns today's daily effort data from the user document.
  static Future<Map<String, dynamic>> _getDailyEffort(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data();
      if (data == null) return {};

      final effort = data['dailyEffort'];
      if (effort is Map<String, dynamic> && effort['date'] == _todayStr()) {
        return effort;
      }
      return {}; // different day or no effort logged yet
    } catch (e) {
      debugPrint('⚠️ ANTICHEAT: Failed to read dailyEffort: $e');
      return {};
    }
  }

  /// Checks daily effort cap. Returns a status indicating whether to allow,
  /// show a friendly popup (soft cap at 18h), or hard-block (24h).
  static Future<DailyCapStatus> checkDailyEffortCap(int minutes, String path) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return DailyCapStatus.allowed;

    try {
      final data = await _getDailyEffort(uid);
      final currentTotal = (data['total'] as num?)?.toInt() ?? 0;
      final newTotal = currentTotal + minutes;

      if (newTotal > maxDailyMinutes) return DailyCapStatus.hardCapped;
      if (newTotal > softCapMinutes) {
        // Flag account for review
        await _db.collection('users').doc(uid).set({
          'flaggedForReview': true,
          'flaggedReason': 'Logged $newTotal minutes in a single day',
          'flaggedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return DailyCapStatus.softCapped;
      }
      return DailyCapStatus.allowed;
    } catch (e) {
      debugPrint('⚠️ ANTICHEAT: Daily cap check failed: $e');
      return DailyCapStatus.allowed;
    }
  }

  /// Logs [minutes] of effort for [path] into the user document.
  /// Also sets activity flags (stopwatchSubmit, liftUpdate, etc.) if provided.
  static Future<void> logDailyEffort(
    int minutes,
    String path, {
    String? activityFlag,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final today = _todayStr();
      final docRef = _db.collection('users').doc(uid);

      // Read current effort to decide if we need to reset for a new day
      final doc = await docRef.get();
      final existing = doc.data()?['dailyEffort'];
      final isToday = existing is Map<String, dynamic> && existing['date'] == today;

      if (isToday) {
        // Same day — increment existing values
        final updates = <String, dynamic>{
          'dailyEffort.$path': FieldValue.increment(minutes),
          'dailyEffort.total': FieldValue.increment(minutes),
        };
        if (activityFlag != null) {
          updates['dailyEffort.$activityFlag'] = true;
        }
        await docRef.update(updates);
      } else {
        // New day — reset the map
        final newEffort = <String, dynamic>{
          'date': today,
          'gym': 0,
          'academic': 0,
          'running': 0,
          'luminary': 0,
          'total': minutes,
          path: minutes,
        };
        if (activityFlag != null) {
          newEffort[activityFlag] = true;
        }
        await docRef.set({'dailyEffort': newEffort}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('⚠️ ANTICHEAT: logDailyEffort failed: $e');
    }
  }

  /// Returns today's effort data for challenge gating.
  static Future<Map<String, dynamic>> getTodayEffort() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};
    try {
      return await _getDailyEffort(uid);
    } catch (e) {
      debugPrint('⚠️ ANTICHEAT: getTodayEffort failed: $e');
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  2. GYM — Suspicion Quotient (Wilks rate-of-change)
  // ═══════════════════════════════════════════════════════════════════════

  /// Checks a gym PR update. Returns `true` if clean, `false` if flagged.
  /// The update is NOT blocked — just flagged in the flags subcollection.
  static Future<bool> checkGymPR({
    required int newBench,
    required int newSquat,
    required int newDeadlift,
    required double bodyweight,
    required String gender,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true;

    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};

    final prevWilks = (data['prevWilks'] as num?)?.toDouble();
    if (prevWilks == null) {
      // First time setting lifts — no comparison possible, store baseline.
      return true;
    }

    final newTotal = (newBench + newSquat + newDeadlift).toDouble();
    final newWilks =
        LiftingUtils.calculateWilksScore(newTotal, bodyweight, gender);

    final days = _daysBetween(data['lastLiftUpdateDate'] as String?);
    final suspicion = (newWilks - prevWilks) / days;

    final totalElo =
        ((data['skillElo'] as num?)?.toInt() ?? 0) +
        ((data['effortElo'] as num?)?.toInt() ?? 0);
    final tier = _rankTier(totalElo, RankUtils.gymRanks);
    final threshold = _gymSuspicionThresholds[tier];

    if (suspicion > threshold) {
      await _writeFlag(uid, 'gym_suspicion', suspicion, threshold,
          'Wilks jumped ${(newWilks - prevWilks).toStringAsFixed(1)} in $days days at ${RankUtils.gymRanks[tier].name} rank');
      return false;
    }
    return true;
  }

  /// Stores previous Wilks after a successful lift update.
  static Future<void> storeGymBaseline({
    required int bench,
    required int squat,
    required int deadlift,
    required double bodyweight,
    required String gender,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final total = (bench + squat + deadlift).toDouble();
    final wilks = LiftingUtils.calculateWilksScore(total, bodyweight, gender);

    await _db.collection('users').doc(uid).set({
      'prevWilks': wilks,
      'lastLiftUpdateDate': _todayStr(),
    }, SetOptions(merge: true));

    // Log activity flag for challenges
    await logDailyEffort(0, 'gym', activityFlag: 'liftUpdate');
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  3. ACADEMICS — Grade jump correlation
  // ═══════════════════════════════════════════════════════════════════════

  /// Checks an academic grade update. Returns `true` if clean.
  static Future<bool> checkAcademicGradeJump({
    required int newGrade,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true;

    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};

    final prevGrade = (data['prevGrade'] as num?)?.toInt();
    if (prevGrade == null) return true; // first time

    final gradeJump = newGrade - prevGrade;
    if (gradeJump <= 0) return true; // grade went down or stayed same

    final currentEffort =
        (data['academicEffortElo'] as num?)?.toInt() ?? 0;
    final effortAtLastUpdate =
        (data['effortEloAtLastGradeUpdate'] as num?)?.toInt() ?? 0;
    final studyMinutes = currentEffort - effortAtLastUpdate;

    final requiredMinutes = gradeJump * academicMinutesPerGradePoint;

    if (studyMinutes < requiredMinutes * 0.5) {
      await _writeFlag(
        uid,
        'academic_suspicion',
        gradeJump.toDouble(),
        requiredMinutes * 0.5,
        'Grade jumped $gradeJump points with only $studyMinutes study minutes (needed ${(requiredMinutes * 0.5).toInt()})',
      );
      return false;
    }
    return true;
  }

  /// Stores academic baseline after a grade update.
  static Future<void> storeAcademicBaseline({required int grade}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await _db.collection('users').doc(uid).get();
    final currentEffort =
        (doc.data()?['academicEffortElo'] as num?)?.toInt() ?? 0;

    await _db.collection('users').doc(uid).set({
      'prevGrade': grade,
      'lastGradeUpdateDate': _todayStr(),
      'effortEloAtLastGradeUpdate': currentEffort,
    }, SetOptions(merge: true));

    await logDailyEffort(0, 'academic', activityFlag: 'gradeUpdate');
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  4. RUNNING — 5K time improvement rate
  // ═══════════════════════════════════════════════════════════════════════

  /// Checks a 5K baseline update. Returns `true` if clean.
  static Future<bool> checkRunning5kImprovement({
    required int newMinutes,
    required int newSeconds,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true;

    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};

    final prev5kSeconds = (data['prev5kSeconds'] as num?)?.toInt();
    if (prev5kSeconds == null) return true; // first time

    final new5kSeconds = newMinutes * 60 + newSeconds;
    final timeImprovement = prev5kSeconds - new5kSeconds; // positive = faster
    if (timeImprovement <= 0) return true; // got slower, no flag

    final days = _daysBetween(data['last5kUpdateDate'] as String?);
    final suspicion = timeImprovement / days;

    final totalElo =
        ((data['runningSkillElo'] as num?)?.toInt() ?? 0) +
        ((data['runningEffortElo'] as num?)?.toInt() ?? 0);
    final tier = _rankTier(totalElo, RankUtils.runningRanks);
    final threshold = _runningSuspicionThresholds[tier];

    if (suspicion > threshold) {
      await _writeFlag(
        uid,
        'running_suspicion',
        suspicion,
        threshold,
        '5K improved ${timeImprovement}s in $days days at ${RankUtils.runningRanks[tier].name} rank',
      );
      return false;
    }
    return true;
  }

  /// Stores running baseline after a 5K update.
  static Future<void> storeRunningBaseline({
    required int minutes,
    required int seconds,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _db.collection('users').doc(uid).set({
      'prev5kSeconds': minutes * 60 + seconds,
      'last5kUpdateDate': _todayStr(),
    }, SetOptions(merge: true));

    await logDailyEffort(0, 'running', activityFlag: 'fiveKUpdate');
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  5. LUMINARY — Hours jump correlation
  // ═══════════════════════════════════════════════════════════════════════

  /// Checks a luminary baseline update. Returns `true` if clean.
  static Future<bool> checkLuminaryHoursJump({
    required int newHours,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return true;

    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data() ?? {};

    final prevHours = (data['prevBaselineHours'] as num?)?.toInt();
    if (prevHours == null) return true;

    final hoursJump = newHours - prevHours;
    if (hoursJump <= 0) return true;

    final currentEffort =
        (data['luminaryEffortElo'] as num?)?.toInt() ?? 0;
    final effortAtLastUpdate =
        (data['effortEloAtLastBaselineUpdate'] as num?)?.toInt() ?? 0;
    final effortMinutes = currentEffort - effortAtLastUpdate;

    final requiredMinutes = hoursJump * luminaryMinutesPerBaselineHour;

    if (effortMinutes < requiredMinutes * 0.5) {
      await _writeFlag(
        uid,
        'luminary_suspicion',
        hoursJump.toDouble(),
        requiredMinutes * 0.5,
        'Baseline jumped $hoursJump hours with only $effortMinutes effort minutes (needed ${(requiredMinutes * 0.5).toInt()})',
      );
      return false;
    }
    return true;
  }

  /// Stores luminary baseline after an hours update.
  static Future<void> storeLuminaryBaseline({required int hours}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await _db.collection('users').doc(uid).get();
    final currentEffort =
        (doc.data()?['luminaryEffortElo'] as num?)?.toInt() ?? 0;

    await _db.collection('users').doc(uid).set({
      'prevBaselineHours': hours,
      'lastBaselineUpdateDate': _todayStr(),
      'effortEloAtLastBaselineUpdate': currentEffort,
    }, SetOptions(merge: true));

    await logDailyEffort(0, 'luminary', activityFlag: 'baselineUpdate');
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  Flag Writing + Auto-Shadowban Check
  // ═══════════════════════════════════════════════════════════════════════

  static Future<void> _writeFlag(
    String uid,
    String type,
    double score,
    double threshold,
    String details,
  ) async {
    debugPrint(
        '⚠️ ANTICHEAT FLAG: $type — score=$score threshold=$threshold — $details');

    // Write flag document
    await _db.collection('users').doc(uid).collection('flags').add({
      'type': type,
      'suspicionScore': score,
      'threshold': threshold,
      'details': details,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Count flags in last 30 days
    final cutoff =
        DateTime.now().subtract(const Duration(days: 30));
    final flagsQuery = await _db
        .collection('users')
        .doc(uid)
        .collection('flags')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
        .get();

    final flagCount = flagsQuery.docs.length;

    // Update rolling count
    await _db.collection('users').doc(uid).set({
      'flagCount30d': flagCount,
    }, SetOptions(merge: true));

    // Auto-shadowban if threshold exceeded
    if (flagCount >= shadowbanFlagThreshold) {
      await _db.collection('users').doc(uid).set({
        'isShadowbanned': true,
      }, SetOptions(merge: true));
      debugPrint('🚫 ANTICHEAT: User $uid auto-shadowbanned ($flagCount flags in 30d)');
    }
  }
}
