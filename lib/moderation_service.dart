import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Community moderation: user reporting, shadowban evaluation, and AI comment filter.
///
/// Reports are stored on the **reporter's own user document** (`reportedUsers` list)
/// and on the **target's user document** (`reportedBy` list + `reportCount`),
/// avoiding the need for a separate `reports` collection with custom Firestore rules.
class ModerationService {
  static final _db = FirebaseFirestore.instance;

  /// Number of unique reports needed to trigger a shadowban.
  static const int reportThreshold = 3;

  // ═══════════════════════════════════════════════════════════════════════
  //  1. REPORT USER
  // ═══════════════════════════════════════════════════════════════════════

  /// Reports a user. Returns a status message.
  /// Stores the report on the reporter's doc and the target's doc.
  static Future<String> reportUser(String targetUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'Not logged in.';
    if (uid == targetUid) return 'You cannot report yourself.';

    try {
      // Check if already reported (stored on reporter's own doc)
      final myDoc = await _db.collection('users').doc(uid).get();
      final myData = myDoc.data() ?? {};
      final alreadyReported = List<String>.from(myData['reportedUsers'] ?? []);

      if (alreadyReported.contains(targetUid)) {
        return 'You have already reported this user.';
      }

      // Mark report on reporter's own doc
      await _db.collection('users').doc(uid).set({
        'reportedUsers': FieldValue.arrayUnion([targetUid]),
      }, SetOptions(merge: true));

      // Increment report count on target's doc + add reporter UID
      await _db.collection('users').doc(targetUid).set({
        'reportCount': FieldValue.increment(1),
        'reportedBy': FieldValue.arrayUnion([uid]),
      }, SetOptions(merge: true));

      // Evaluate shadowban
      await _evaluateShadowban(targetUid);

      return 'Report submitted. Thank you for helping keep the community fair.';
    } catch (e) {
      debugPrint('⚠️ MODERATION: reportUser failed: $e');
      return 'Report could not be submitted. Please try again later.';
    }
  }

  /// Checks if reportThreshold+ unique users have reported the target.
  /// If so, shadowbans them.
  static Future<void> _evaluateShadowban(String targetUid) async {
    try {
      final targetDoc = await _db.collection('users').doc(targetUid).get();
      final data = targetDoc.data() ?? {};
      final reportCount = (data['reportCount'] as num?)?.toInt() ?? 0;

      if (reportCount >= reportThreshold) {
        await _db.collection('users').doc(targetUid).set({
          'isShadowbanned': true,
        }, SetOptions(merge: true));
        debugPrint(
            '🚫 MODERATION: User $targetUid shadowbanned ($reportCount reports)');
      }
    } catch (e) {
      debugPrint('⚠️ MODERATION: _evaluateShadowban failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  2. AI COMMENT FILTER
  // ═══════════════════════════════════════════════════════════════════════

  /// Generic phrases that should be rejected to prevent Elo farming via
  /// low-effort peer reviews.
  static final _genericPatterns = [
    'good',
    'nice',
    'great',
    'cool',
    'awesome',
    'amazing',
    'do better',
    'try harder',
    'keep going',
    'great job',
    'good job',
    'well done',
    'not bad',
    'ok',
    'okay',
    'fine',
    'sure',
    'yes',
    'no',
    'lol',
    'lmao',
    'idk',
    'did it',
    'done',
    'updated',
    'because',
    'just because',
    'i did',
    'completed',
  ];

  /// Returns `true` if the comment passes the filter (is acceptable).
  /// Returns `false` if the comment is too generic / low-effort.
  ///
  /// Rules:
  /// - Must be at least 20 characters
  /// - Must not be a single generic phrase
  /// - Must contain at least 3 distinct words
  static bool filterComment(String text) {
    final trimmed = text.trim();

    // Minimum length
    if (trimmed.length < 20) return false;

    // Check against generic patterns (case-insensitive exact match)
    final lower = trimmed.toLowerCase();
    for (final pattern in _genericPatterns) {
      if (lower == pattern) return false;
    }

    // Must have at least 3 distinct words
    final words = trimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    if (words.length < 3) return false;

    return true;
  }
}
