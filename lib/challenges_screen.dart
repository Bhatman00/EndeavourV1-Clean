import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'anticheat_service.dart';
import 'moderation_service.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
const _kBg0 = Color(0xFF0A0A14);
const _kBg1 = Color(0xFF141428);
const _kGold = Color(0xFFFFB830);
const _kPurple = Color(0xFF6E5CFF);

// ─── Enums ────────────────────────────────────────────────────────────────────
enum _Diff { easy, hard, elite }

enum _DPath { gym, academic, running, luminary, any }

/// How the challenge is verified against daily effort data.
enum _RequireType {
  effort,           // requires X minutes logged in a specific path
  stopwatch,        // requires a stopwatch submission in a specific path
  liftUpdate,       // requires a lift stat update today (gym)
  gradeUpdate,      // requires a grade update today (academic)
  fiveKUpdate,      // requires a 5K time update today (running)
  baselineUpdate,   // requires a baseline update today (luminary)
  multiPath,        // requires effort in N different paths today
}

// ─── Models ───────────────────────────────────────────────────────────────────
class _Challenge {
  final String id;
  final String title;
  final String description;
  final _DPath path;
  final _Diff diff;
  final int elo;
  final IconData icon;
  final _RequireType requireType;
  final int requiredMinutes;    // minutes needed (or path count for multiPath)
  final bool needsContextTrap;  // if true, shows a text input before completion

  const _Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.path,
    required this.diff,
    required this.elo,
    required this.icon,
    this.requireType = _RequireType.effort,
    this.requiredMinutes = 0,
    this.needsContextTrap = false,
  });
}

class _PathSection {
  final _DPath path;
  final String label;
  final Color color;
  final IconData icon;
  final List<_Challenge> challenges;

  const _PathSection({
    required this.path,
    required this.label,
    required this.color,
    required this.icon,
    required this.challenges,
  });
}

// ─── Provable Challenge Pools ─────────────────────────────────────────────────
const _gymPool = <_Challenge>[
  _Challenge(id: 'g0', title: 'LOG A SESSION', description: "Log at least 15 gym minutes today.", path: _DPath.gym, diff: _Diff.easy, elo: 50, icon: Icons.fitness_center_rounded, requireType: _RequireType.effort, requiredMinutes: 15),
  _Challenge(id: 'g1', title: '45 MINUTE WORKOUT', description: "Log at least 45 gym minutes today.", path: _DPath.gym, diff: _Diff.hard, elo: 100, icon: Icons.timer_rounded, requireType: _RequireType.effort, requiredMinutes: 45),
  _Challenge(id: 'g2', title: '90 MINUTE GRIND', description: "Log at least 90 gym minutes today.", path: _DPath.gym, diff: _Diff.elite, elo: 200, icon: Icons.emoji_events_rounded, requireType: _RequireType.effort, requiredMinutes: 90),
  _Challenge(id: 'g3', title: 'UPDATE YOUR LIFTS', description: "Update your bench, squat, or deadlift today.", path: _DPath.gym, diff: _Diff.easy, elo: 50, icon: Icons.trending_up_rounded, requireType: _RequireType.liftUpdate, needsContextTrap: true),
  _Challenge(id: 'g4', title: 'USE THE TIMER', description: "Submit a stopwatch session in gym.", path: _DPath.gym, diff: _Diff.hard, elo: 100, icon: Icons.access_time_rounded, requireType: _RequireType.stopwatch),
  _Challenge(id: 'g5', title: '2 HOUR SESSION', description: "Log at least 120 gym minutes today.", path: _DPath.gym, diff: _Diff.elite, elo: 200, icon: Icons.local_fire_department_rounded, requireType: _RequireType.effort, requiredMinutes: 120),
  _Challenge(id: 'g6', title: '30 MINUTE WORKOUT', description: "Log at least 30 gym minutes today.", path: _DPath.gym, diff: _Diff.hard, elo: 100, icon: Icons.replay_rounded, requireType: _RequireType.effort, requiredMinutes: 30),
];

const _acadPool = <_Challenge>[
  _Challenge(id: 'a0', title: 'STUDY 15 MINUTES', description: "Log at least 15 study minutes today.", path: _DPath.academic, diff: _Diff.easy, elo: 50, icon: Icons.auto_stories_rounded, requireType: _RequireType.effort, requiredMinutes: 15),
  _Challenge(id: 'a1', title: 'STUDY 1 HOUR', description: "Log at least 60 study minutes today.", path: _DPath.academic, diff: _Diff.hard, elo: 100, icon: Icons.psychology_rounded, requireType: _RequireType.effort, requiredMinutes: 60),
  _Challenge(id: 'a2', title: 'STUDY 3 HOURS', description: "Log at least 180 study minutes today.", path: _DPath.academic, diff: _Diff.elite, elo: 200, icon: Icons.functions_rounded, requireType: _RequireType.effort, requiredMinutes: 180),
  _Challenge(id: 'a3', title: 'USE THE TIMER', description: "Submit a stopwatch session in academics.", path: _DPath.academic, diff: _Diff.easy, elo: 50, icon: Icons.access_time_rounded, requireType: _RequireType.stopwatch),
  _Challenge(id: 'a4', title: 'STUDY 2 HOURS', description: "Log at least 120 study minutes today.", path: _DPath.academic, diff: _Diff.hard, elo: 125, icon: Icons.hourglass_top_rounded, requireType: _RequireType.effort, requiredMinutes: 120),
  _Challenge(id: 'a5', title: 'UPDATE YOUR GRADE', description: "Update your academic grade today.", path: _DPath.academic, diff: _Diff.hard, elo: 100, icon: Icons.school_rounded, requireType: _RequireType.gradeUpdate, needsContextTrap: true),
  _Challenge(id: 'a6', title: 'STUDY 4 HOURS', description: "Log at least 240 study minutes today.", path: _DPath.academic, diff: _Diff.elite, elo: 200, icon: Icons.workspace_premium_rounded, requireType: _RequireType.effort, requiredMinutes: 240),
];

const _runPool = <_Challenge>[
  _Challenge(id: 'r0', title: 'LOG A RUN', description: "Log at least 10 running minutes today.", path: _DPath.running, diff: _Diff.easy, elo: 50, icon: Icons.directions_run_rounded, requireType: _RequireType.effort, requiredMinutes: 10),
  _Challenge(id: 'r1', title: '30 MINUTE RUN', description: "Log at least 30 running minutes today.", path: _DPath.running, diff: _Diff.hard, elo: 100, icon: Icons.speed_rounded, requireType: _RequireType.effort, requiredMinutes: 30),
  _Challenge(id: 'r2', title: '60 MINUTE RUN', description: "Log at least 60 running minutes today.", path: _DPath.running, diff: _Diff.elite, elo: 200, icon: Icons.emoji_events_rounded, requireType: _RequireType.effort, requiredMinutes: 60),
  _Challenge(id: 'r3', title: 'USE THE TIMER', description: "Submit a stopwatch session in running.", path: _DPath.running, diff: _Diff.easy, elo: 50, icon: Icons.access_time_rounded, requireType: _RequireType.stopwatch),
  _Challenge(id: 'r4', title: '45 MINUTE RUN', description: "Log at least 45 running minutes today.", path: _DPath.running, diff: _Diff.hard, elo: 125, icon: Icons.timeline_rounded, requireType: _RequireType.effort, requiredMinutes: 45),
  _Challenge(id: 'r5', title: 'UPDATE YOUR 5K', description: "Update your 5K personal best today.", path: _DPath.running, diff: _Diff.hard, elo: 100, icon: Icons.flag_rounded, requireType: _RequireType.fiveKUpdate, needsContextTrap: true),
  _Challenge(id: 'r6', title: '90 MIN ENDURANCE', description: "Log at least 90 running minutes today.", path: _DPath.running, diff: _Diff.elite, elo: 200, icon: Icons.bolt_rounded, requireType: _RequireType.effort, requiredMinutes: 90),
];

const _lumPool = <_Challenge>[
  _Challenge(id: 'l0', title: 'LOG A SESSION', description: "Log at least 15 luminary minutes today.", path: _DPath.luminary, diff: _Diff.easy, elo: 50, icon: Icons.auto_awesome_rounded, requireType: _RequireType.effort, requiredMinutes: 15),
  _Challenge(id: 'l1', title: 'DEEP WORK HOUR', description: "Log at least 60 luminary minutes today.", path: _DPath.luminary, diff: _Diff.hard, elo: 100, icon: Icons.local_fire_department_rounded, requireType: _RequireType.effort, requiredMinutes: 60),
  _Challenge(id: 'l2', title: 'DEEP WORK 3 HOURS', description: "Log at least 180 luminary minutes today.", path: _DPath.luminary, diff: _Diff.elite, elo: 200, icon: Icons.brush_rounded, requireType: _RequireType.effort, requiredMinutes: 180),
  _Challenge(id: 'l3', title: 'USE THE TIMER', description: "Submit a stopwatch session in luminary.", path: _DPath.luminary, diff: _Diff.easy, elo: 50, icon: Icons.access_time_rounded, requireType: _RequireType.stopwatch),
  _Challenge(id: 'l4', title: 'DEEP WORK 2 HOURS', description: "Log at least 120 luminary minutes today.", path: _DPath.luminary, diff: _Diff.hard, elo: 125, icon: Icons.waves_rounded, requireType: _RequireType.effort, requiredMinutes: 120),
  _Challenge(id: 'l5', title: 'UPDATE BASELINE', description: "Update your weekly deep-work hours today.", path: _DPath.luminary, diff: _Diff.hard, elo: 100, icon: Icons.tune_rounded, requireType: _RequireType.baselineUpdate, needsContextTrap: true),
  _Challenge(id: 'l6', title: 'DEEP WORK 4 HOURS', description: "Log at least 240 luminary minutes today.", path: _DPath.luminary, diff: _Diff.elite, elo: 200, icon: Icons.star_rounded, requireType: _RequireType.effort, requiredMinutes: 240),
];

const _anyPool = <_Challenge>[
  _Challenge(id: 'any0', title: 'LOG ANY SESSION', description: "Log at least 15 minutes in any path today.", path: _DPath.any, diff: _Diff.easy, elo: 75, icon: Icons.flag_rounded, requireType: _RequireType.effort, requiredMinutes: 15),
  _Challenge(id: 'any1', title: 'TWO PATHS ACTIVE', description: "Log effort in 2 different paths today.", path: _DPath.any, diff: _Diff.hard, elo: 150, icon: Icons.compare_arrows_rounded, requireType: _RequireType.multiPath, requiredMinutes: 2),
  _Challenge(id: 'any2', title: 'THREE PATHS ACTIVE', description: "Log effort in 3 different paths today.", path: _DPath.any, diff: _Diff.elite, elo: 300, icon: Icons.all_inclusive_rounded, requireType: _RequireType.multiPath, requiredMinutes: 3),
  _Challenge(id: 'any3', title: 'KEEP THE STREAK', description: "Log any activity today to keep a streak.", path: _DPath.any, diff: _Diff.easy, elo: 75, icon: Icons.local_fire_department_rounded, requireType: _RequireType.effort, requiredMinutes: 1),
  _Challenge(id: 'any4', title: 'DUAL PATH HOUR', description: "Log 60+ minutes across 2 paths today.", path: _DPath.any, diff: _Diff.hard, elo: 200, icon: Icons.military_tech_rounded, requireType: _RequireType.multiPath, requiredMinutes: 2),
];

// ─── Daily Selection ──────────────────────────────────────────────────────────
List<_Challenge> _pickThreeFromPool(List<_Challenge> pool, int seed) {
  final day = DateTime.now().difference(DateTime(2000, 1, 1)).inDays;
  final base = (day + seed).abs();
  final n = pool.length;
  final i0 = base % n;
  // Step of 3 is coprime to 7-item pools, guaranteeing distinct daily rotation
  final i1 = (base + 3) % n;
  final i2 = (base + 6) % n;
  final idxs = <int>[i0];
  if (i1 != i0) idxs.add(i1);
  if (i2 != i0 && i2 != i1) idxs.add(i2);
  for (var i = 0; i < n && idxs.length < 3; i++) {
    if (!idxs.contains(i)) idxs.add(i);
  }
  return idxs.take(3).map((i) => pool[i]).toList();
}

List<_PathSection> _buildSections(Map<String, dynamic> data) {
  int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
  final gymElo = asInt(data['skillElo']) + asInt(data['effortElo']);
  final acadElo = asInt(data['academicSkillElo']) + asInt(data['academicEffortElo']);
  final runElo = asInt(data['runningSkillElo']) + asInt(data['runningEffortElo']);
  final lumElo = asInt(data['luminarySkillElo']) + asInt(data['luminaryEffortElo']);

  final sections = <_PathSection>[];

  if (gymElo > 0) {
    sections.add(const _PathSection(path: _DPath.gym, label: 'GYM', color: Color(0xFFFF3B5C), icon: Icons.fitness_center_rounded, challenges: [])
        ._withChallenges(_pickThreeFromPool(_gymPool, 0)));
  }
  if (acadElo > 0) {
    sections.add(const _PathSection(path: _DPath.academic, label: 'ACADEMICS', color: Color(0xFF6E5CFF), icon: Icons.auto_stories_rounded, challenges: [])
        ._withChallenges(_pickThreeFromPool(_acadPool, 11)));
  }
  if (runElo > 0) {
    sections.add(const _PathSection(path: _DPath.running, label: 'RUNNING', color: Color(0xFF30D158), icon: Icons.directions_run_rounded, challenges: [])
        ._withChallenges(_pickThreeFromPool(_runPool, 23)));
  }
  if (lumElo > 0) {
    sections.add(const _PathSection(path: _DPath.luminary, label: 'LUMINARY', color: Color(0xFFFFD60A), icon: Icons.auto_awesome_rounded, challenges: [])
        ._withChallenges(_pickThreeFromPool(_lumPool, 37)));
  }

  // Cross-path bonus: only appears when the user actively trains 2+ disciplines
  if (sections.length >= 2) {
    final day = DateTime.now().difference(DateTime(2000, 1, 1)).inDays;
    sections.add(const _PathSection(path: _DPath.any, label: 'CROSS-PATH', color: Color(0xFFFFB830), icon: Icons.all_inclusive_rounded, challenges: [])
        ._withChallenges([_anyPool[(day + 3) % _anyPool.length]]));
  }

  return sections;
}

extension _SectionCopy on _PathSection {
  _PathSection _withChallenges(List<_Challenge> cs) =>
      _PathSection(path: path, label: label, color: color, icon: icon, challenges: cs);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
String _diffLabel(_Diff d) {
  switch (d) {
    case _Diff.easy:  return 'EASY';
    case _Diff.hard:  return 'HARD';
    case _Diff.elite: return 'ELITE';
  }
}

Color _diffColor(_Diff d) {
  switch (d) {
    case _Diff.easy:  return const Color(0xFF30D158);
    case _Diff.hard:  return const Color(0xFFFFB830);
    case _Diff.elite: return const Color(0xFFFF3B5C);
  }
}

String _eloField(_DPath p) {
  switch (p) {
    case _DPath.gym:      return 'effortElo';
    case _DPath.academic: return 'academicEffortElo';
    case _DPath.running:  return 'runningEffortElo';
    case _DPath.luminary: return 'luminaryEffortElo';
    case _DPath.any:      return 'effortElo';
  }
}

String _todayStr() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String _prettyDate() {
  final now = DateTime.now();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  List<_PathSection> _sections = [];
  final Set<String> _completed = {};
  int _bonusEloToday = 0;
  bool _loading = true;
  late Timer _resetTimer;
  Duration _timeUntilReset = Duration.zero;
  Map<String, dynamic> _todayEffort = {}; // daily effort data for gating

  int get _totalChallenges => _sections.fold(0, (s, sec) => s + sec.challenges.length);

  int get _completedToday {
    int count = 0;
    for (final section in _sections) {
      for (final c in section.challenges) {
        if (_completed.contains(c.id)) count++;
      }
    }
    return count;
  }

  bool get _allDone => _sections.isNotEmpty && _completedToday >= _totalChallenges;

  @override
  void initState() {
    super.initState();
    _loadData();
    _updateTimer();
    _resetTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTimer());
  }

  @override
  void dispose() {
    _resetTimer.cancel();
    super.dispose();
  }

  void _updateTimer() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    if (mounted) setState(() => _timeUntilReset = midnight.difference(now));
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    final savedDate = data['challengeDate'] as String? ?? '';
    final savedCompleted = List<String>.from(data['completedChallengeIds'] ?? []);
    final savedBonus = (data['challengeBonusEloToday'] as num?)?.toInt() ?? 0;

    // Fetch today's effort for challenge gating
    final effort = await AnticheatService.getTodayEffort();

    if (mounted) {
      setState(() {
        _sections = _buildSections(data);
        _todayEffort = effort;
        if (savedDate == _todayStr()) {
          _completed.addAll(savedCompleted);
          _bonusEloToday = savedBonus;
        }
        _loading = false;
      });
    }
  }

  /// Checks if a challenge's effort requirement is met.
  bool _isRequirementMet(_Challenge c) {
    switch (c.requireType) {
      case _RequireType.effort:
        if (c.path == _DPath.any) {
          final total = (_todayEffort['total'] as num?)?.toInt() ?? 0;
          return total >= c.requiredMinutes;
        }
        final pathKey = _pathToEffortKey(c.path);
        final logged = (_todayEffort[pathKey] as num?)?.toInt() ?? 0;
        return logged >= c.requiredMinutes;
      case _RequireType.stopwatch:
        final flagKey = _stopwatchFlagKey(c.path);
        return _todayEffort[flagKey] == true;
      case _RequireType.liftUpdate:
        return _todayEffort['liftUpdate'] == true;
      case _RequireType.gradeUpdate:
        return _todayEffort['gradeUpdate'] == true;
      case _RequireType.fiveKUpdate:
        return _todayEffort['fiveKUpdate'] == true;
      case _RequireType.baselineUpdate:
        return _todayEffort['baselineUpdate'] == true;
      case _RequireType.multiPath:
        int activePaths = 0;
        for (final key in ['gym', 'academic', 'running', 'luminary']) {
          if ((_todayEffort[key] as num?)?.toInt() != null &&
              (_todayEffort[key] as num).toInt() > 0) {
            activePaths++;
          }
        }
        return activePaths >= c.requiredMinutes;
    }
  }

  static String _pathToEffortKey(_DPath p) {
    switch (p) {
      case _DPath.gym:      return 'gym';
      case _DPath.academic: return 'academic';
      case _DPath.running:  return 'running';
      case _DPath.luminary: return 'luminary';
      case _DPath.any:      return 'total';
    }
  }

  static String _stopwatchFlagKey(_DPath p) {
    switch (p) {
      case _DPath.gym:      return 'gymStopwatchSubmit';
      case _DPath.academic: return 'academicStopwatchSubmit';
      case _DPath.running:  return 'runningStopwatchSubmit';
      case _DPath.luminary: return 'luminaryStopwatchSubmit';
      case _DPath.any:      return 'gymStopwatchSubmit';
    }
  }

  Future<void> _completeChallenge(_Challenge challenge) async {
    if (_completed.contains(challenge.id)) return;
    if (!_isRequirementMet(challenge)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Context trap: for non-quantifiable tasks, require text input
    if (challenge.needsContextTrap) {
      final passed = await _showContextTrapDialog(challenge);
      if (!passed) return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _completed.add(challenge.id);
      _bonusEloToday += challenge.elo;
    });

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'challengeDate': _todayStr(),
      'completedChallengeIds': _completed.toList(),
      'challengeBonusEloToday': _bonusEloToday,
      _eloField(challenge.path): FieldValue.increment(challenge.elo),
    });

    if (_allDone && mounted) {
      await Future.delayed(const Duration(milliseconds: 150));
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 120));
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 120));
      HapticFeedback.heavyImpact();
    }
  }

  /// Shows the context trap dialog for non-quantifiable challenges.
  /// Returns true if the user provided a valid response.
  Future<bool> _showContextTrapDialog(_Challenge challenge) async {
    final controller = TextEditingController();
    String? errorText;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF12121A).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.title,
                      style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: Colors.white, fontFamily: '.SF Pro Display',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'What did you change and why?',
                      style: TextStyle(
                        fontSize: 13, color: Colors.white.withValues(alpha: 0.5),
                        fontFamily: '.SF Pro Display',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: '.SF Pro Display'),
                      decoration: InputDecoration(
                        hintText: 'Describe what you updated...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25)),
                        errorText: errorText,
                        errorStyle: const TextStyle(color: Color(0xFFFF3B5C), fontSize: 11),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kGold, width: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.4))),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGold.withValues(alpha: 0.2),
                            foregroundColor: _kGold,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            final text = controller.text;
                            if (!ModerationService.filterComment(text)) {
                              setDialogState(() {
                                errorText = 'Please provide a specific, detailed response (20+ chars, 3+ words).';
                              });
                              return;
                            }
                            Navigator.of(ctx).pop(true);
                          },
                          child: const Text('Submit'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return result == true;
  }

  String _formatCountdown() {
    final h = _timeUntilReset.inHours;
    final m = _timeUntilReset.inMinutes % 60;
    final s = _timeUntilReset.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg0,
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _ChallengesPainter())),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                _buildSummaryCard(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 1.5),
      );
    }
    if (_sections.isEmpty) {
      return const _EmptyState();
    }

    // Build flat item list: section header + challenge cards
    final items = <Widget>[];
    for (final section in _sections) {
      final doneSec = section.challenges.where((c) => _completed.contains(c.id)).length;
      items.add(_SectionHeader(section: section, done: doneSec));
      for (final c in section.challenges) {
        final met = _completed.contains(c.id) || _isRequirementMet(c);
        items.add(_ChallengeCard(
          challenge: c,
          completed: _completed.contains(c.id),
          requirementMet: met,
          onComplete: () => _completeChallenge(c),
        ));
      }
    }
    items.add(const SizedBox(height: 48));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      children: items,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
                  ),
                  child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily Challenges',
                  style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white,
                    letterSpacing: -0.5, fontFamily: '.SF Pro Display', height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      _prettyDate(),
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.35),
                        letterSpacing: 0.2, fontFamily: '.SF Pro Display',
                      ),
                    ),
                    Text(
                      '  ·  Resets in ${_formatCountdown()}',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.25),
                        letterSpacing: 0.2, fontFamily: '.SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Bonus ELO counter
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _kGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: _kGold.withValues(alpha: 0.35), width: 0.7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded, color: _kGold, size: 13),
                    const SizedBox(width: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        '+$_bonusEloToday ELO',
                        key: ValueKey(_bonusEloToday),
                        style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: _kGold,
                          fontFamily: '.SF Pro Display', height: 1, letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final total = _totalChallenges;
    final done = _completedToday.clamp(0, total > 0 ? total : 1);
    final progress = total > 0 ? done / total : 0.0;
    final allDone = _allDone;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              color: allDone ? _kGold.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: allDone ? _kGold.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.07),
                width: 0.5,
              ),
              boxShadow: allDone
                  ? [BoxShadow(color: _kGold.withValues(alpha: 0.08), blurRadius: 32)]
                  : [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            allDone ? 'ALL CHALLENGES COMPLETE' : 'TODAY\'S PROGRESS',
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600,
                              color: allDone ? _kGold.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.35),
                              letterSpacing: 1.4, fontFamily: '.SF Pro Display',
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '$done / $total Challenges',
                            style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white,
                              letterSpacing: -0.4, fontFamily: '.SF Pro Display', height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: allDone
                          ? _AllDoneBadge(key: const ValueKey('done'))
                          : _ProgressPercent(key: const ValueKey('progress'), value: progress),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, val, child) => LinearProgressIndicator(
                      value: val,
                      backgroundColor: Colors.white.withValues(alpha: 0.07),
                      valueColor: AlwaysStoppedAnimation<Color>(allDone ? _kGold : _kPurple),
                      minHeight: 4,
                    ),
                  ),
                ),
                if (allDone) ...[
                  const SizedBox(height: 12),
                  Text(
                    'You\'ve claimed all bonus ELO for today. Come back tomorrow.',
                    style: TextStyle(
                      fontSize: 12, color: Colors.white.withValues(alpha: 0.40),
                      fontFamily: '.SF Pro Display', letterSpacing: -0.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final _PathSection section;
  final int done;

  const _SectionHeader({required this.section, required this.done});

  @override
  Widget build(BuildContext context) {
    final total = section.challenges.length;
    final allDone = done >= total;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: section.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(section.icon, color: section.color, size: 15),
          ),
          const SizedBox(width: 10),
          Text(
            section.label,
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: section.color, letterSpacing: 1.6,
              fontFamily: '.SF Pro Display', height: 1,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: allDone
                  ? section.color.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: allDone
                    ? section.color.withValues(alpha: 0.40)
                    : Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (allDone) ...[
                  Icon(Icons.check_rounded, color: section.color, size: 10),
                  const SizedBox(width: 4),
                ],
                Text(
                  allDone ? 'DONE' : '$done/$total',
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: allDone ? section.color : Colors.white.withValues(alpha: 0.35),
                    letterSpacing: 0.6, fontFamily: '.SF Pro Display', height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kPurple.withValues(alpha: 0.25), width: 0.7),
              ),
              child: const Icon(Icons.bolt_rounded, color: _kPurple, size: 32),
            ),
            const SizedBox(height: 20),
            const Text(
              'No challenges yet',
              style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white,
                letterSpacing: -0.4, fontFamily: '.SF Pro Display',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Log your first session in any path to unlock your personalised daily challenges.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: 0.40),
                fontFamily: '.SF Pro Display', height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared Badges ────────────────────────────────────────────────────────────
class _AllDoneBadge extends StatelessWidget {
  const _AllDoneBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _kGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: _kGold.withValues(alpha: 0.45), width: 0.7),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events_rounded, color: _kGold, size: 14),
          SizedBox(width: 5),
          Text(
            'DONE',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: _kGold,
              letterSpacing: 0.8, fontFamily: '.SF Pro Display', height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressPercent extends StatelessWidget {
  final double value;
  const _ProgressPercent({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      '${(value * 100).toInt()}%',
      style: TextStyle(
        fontSize: 32, fontWeight: FontWeight.w700,
        color: Colors.white.withValues(alpha: 0.12),
        letterSpacing: -1.5, fontFamily: '.SF Pro Display', height: 1,
      ),
    );
  }
}

// ─── Challenge Card ───────────────────────────────────────────────────────────
class _ChallengeCard extends StatefulWidget {
  final _Challenge challenge;
  final bool completed;
  final bool requirementMet;
  final VoidCallback onComplete;

  const _ChallengeCard({
    required this.challenge,
    required this.completed,
    required this.requirementMet,
    required this.onComplete,
  });

  @override
  State<_ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends State<_ChallengeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _glow = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeOut);
    if (widget.completed) _glowCtrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_ChallengeCard old) {
    super.didUpdateWidget(old);
    if (!old.completed && widget.completed) _glowCtrl.forward();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    // Resolve section color from path
    final color = _sectionColor(c.path);
    final done = widget.completed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedBuilder(
        animation: _glow,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: done
                ? [BoxShadow(color: color.withValues(alpha: 0.16 * _glow.value), blurRadius: 28, offset: const Offset(0, 6))]
                : [],
          ),
          child: child,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: done ? color.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: done ? color.withValues(alpha: 0.30) : Colors.white.withValues(alpha: 0.07),
                  width: 0.5,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22)),
                        gradient: LinearGradient(colors: [
                          Colors.transparent,
                          done ? color.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: done ? 0.20 : 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(c.icon, color: color, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: _diffColor(c.diff).withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _diffLabel(c.diff),
                                style: TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.w700,
                                  color: _diffColor(c.diff), letterSpacing: 0.9,
                                  fontFamily: '.SF Pro Display', height: 1,
                                ),
                              ),
                            ),
                            const Spacer(),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(100),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _kGold.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(100),
                                    border: Border.all(color: _kGold.withValues(alpha: 0.30), width: 0.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.bolt_rounded, color: _kGold, size: 11),
                                      const SizedBox(width: 2),
                                      Text(
                                        '+${c.elo}',
                                        style: const TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w700,
                                          color: _kGold, fontFamily: '.SF Pro Display', height: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          c.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700,
                            color: done ? color : Colors.white,
                            letterSpacing: -0.3, fontFamily: '.SF Pro Display', height: 1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          c.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: done ? 0.40 : 0.60),
                            letterSpacing: -0.1, fontFamily: '.SF Pro Display', height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                          child: done
                              ? _CompletedRow(key: const ValueKey('done'), color: color, elo: c.elo)
                              : widget.requirementMet
                                  ? _CompleteButton(key: const ValueKey('btn'), color: color, onTap: widget.onComplete)
                                  : _LockedButton(key: const ValueKey('locked'), color: color, challenge: c),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _sectionColor(_DPath p) {
    switch (p) {
      case _DPath.gym:      return const Color(0xFFFF3B5C);
      case _DPath.academic: return const Color(0xFF6E5CFF);
      case _DPath.running:  return const Color(0xFF30D158);
      case _DPath.luminary: return const Color(0xFFFFD60A);
      case _DPath.any:      return const Color(0xFFFFB830);
    }
  }
}

class _CompleteButton extends StatefulWidget {
  final Color color;
  final VoidCallback onTap;
  const _CompleteButton({super.key, required this.color, required this.onTap});

  @override
  State<_CompleteButton> createState() => _CompleteButtonState();
}

class _CompleteButtonState extends State<_CompleteButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _pressed ? widget.color.withValues(alpha: 0.22) : widget.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.color.withValues(alpha: _pressed ? 0.55 : 0.30), width: 0.7),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline_rounded, color: widget.color, size: 15),
              const SizedBox(width: 8),
              Text(
                'MARK COMPLETE',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: widget.color, letterSpacing: 0.9,
                  fontFamily: '.SF Pro Display', height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedButton extends StatelessWidget {
  final Color color;
  final _Challenge challenge;
  const _LockedButton({super.key, required this.color, required this.challenge});

  String get _hintText {
    switch (challenge.requireType) {
      case _RequireType.effort:
        return 'Log ${challenge.requiredMinutes} min to unlock';
      case _RequireType.stopwatch:
        return 'Submit a timer session to unlock';
      case _RequireType.liftUpdate:
        return 'Update your lifts to unlock';
      case _RequireType.gradeUpdate:
        return 'Update your grade to unlock';
      case _RequireType.fiveKUpdate:
        return 'Update your 5K time to unlock';
      case _RequireType.baselineUpdate:
        return 'Update your baseline to unlock';
      case _RequireType.multiPath:
        return 'Log effort in ${challenge.requiredMinutes} paths to unlock';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.7),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, color: Colors.white.withValues(alpha: 0.25), size: 14),
          const SizedBox(width: 8),
          Text(
            _hintText.toUpperCase(),
            style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.25), letterSpacing: 0.7,
              fontFamily: '.SF Pro Display', height: 1,
            ),
          ),
        ],
      ),
    );
  }
}


class _CompletedRow extends StatelessWidget {
  final Color color;
  final int elo;
  const _CompletedRow({super.key, required this.color, required this.elo});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle_rounded, color: color, size: 17),
        const SizedBox(width: 7),
        Text(
          'COMPLETED',
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: color,
            letterSpacing: 0.9, fontFamily: '.SF Pro Display', height: 1,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          '· +$elo ELO earned',
          style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.30),
            fontFamily: '.SF Pro Display', height: 1,
          ),
        ),
      ],
    );
  }
}

// ─── Background Painter ───────────────────────────────────────────────────────
class _ChallengesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [_kBg0, _kBg1, _kBg0], stops: [0.0, 0.55, 1.0],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(0.85, -0.85), radius: 0.85,
        colors: [_kGold.withValues(alpha: 0.10), Colors.transparent],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(-0.85, 0.70), radius: 0.75,
        colors: [_kPurple.withValues(alpha: 0.09), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
