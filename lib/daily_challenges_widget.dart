import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'anticheat_service.dart';
import 'moderation_service.dart';

const _kGold = Color(0xFFFFB830);

// ─── Models ───────────────────────────────────────────────────────────────────

enum _Diff { easy, hard, elite }

enum _RequireType {
  effort,
  stopwatch,
  liftUpdate,
  gradeUpdate,
  fiveKUpdate,
  baselineUpdate,
}

class _Challenge {
  final String id;
  final String title;
  final String description;
  final _Diff diff;
  final int elo;
  final IconData icon;
  final _RequireType requireType;
  final int requiredMinutes;
  final bool needsContextTrap;

  const _Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.diff,
    required this.elo,
    required this.icon,
    this.requireType = _RequireType.effort,
    this.requiredMinutes = 0,
    this.needsContextTrap = false,
  });
}

// ─── Pools ────────────────────────────────────────────────────────────────────

const _gymPool = <_Challenge>[
  _Challenge(id: 'g0', title: 'LOG A SESSION', description: "Log at least 15 gym minutes today.", diff: _Diff.easy, elo: 50, icon: Icons.fitness_center_rounded, requireType: _RequireType.effort, requiredMinutes: 15),
  _Challenge(id: 'g1', title: '45 MINUTE WORKOUT', description: "Log at least 45 gym minutes today.", diff: _Diff.hard, elo: 100, icon: Icons.timer_rounded, requireType: _RequireType.effort, requiredMinutes: 45),
  _Challenge(id: 'g2', title: '90 MINUTE GRIND', description: "Log at least 90 gym minutes today.", diff: _Diff.elite, elo: 200, icon: Icons.emoji_events_rounded, requireType: _RequireType.effort, requiredMinutes: 90),
  _Challenge(id: 'g3', title: 'UPDATE YOUR LIFTS', description: "Update your bench, squat, or deadlift today.", diff: _Diff.easy, elo: 50, icon: Icons.trending_up_rounded, requireType: _RequireType.liftUpdate, needsContextTrap: true),
  _Challenge(id: 'g4', title: 'USE THE TIMER', description: "Submit a stopwatch session in gym.", diff: _Diff.hard, elo: 100, icon: Icons.access_time_rounded, requireType: _RequireType.stopwatch),
  _Challenge(id: 'g5', title: '2 HOUR SESSION', description: "Log at least 120 gym minutes today.", diff: _Diff.elite, elo: 200, icon: Icons.local_fire_department_rounded, requireType: _RequireType.effort, requiredMinutes: 120),
  _Challenge(id: 'g6', title: '30 MINUTE WORKOUT', description: "Log at least 30 gym minutes today.", diff: _Diff.hard, elo: 100, icon: Icons.replay_rounded, requireType: _RequireType.effort, requiredMinutes: 30),
];

const _acadPool = <_Challenge>[
  _Challenge(id: 'a0', title: 'STUDY 15 MINUTES', description: "Log at least 15 study minutes today.", diff: _Diff.easy, elo: 50, icon: Icons.auto_stories_rounded, requireType: _RequireType.effort, requiredMinutes: 15),
  _Challenge(id: 'a1', title: 'STUDY 1 HOUR', description: "Log at least 60 study minutes today.", diff: _Diff.hard, elo: 100, icon: Icons.psychology_rounded, requireType: _RequireType.effort, requiredMinutes: 60),
  _Challenge(id: 'a2', title: 'STUDY 3 HOURS', description: "Log at least 180 study minutes today.", diff: _Diff.elite, elo: 200, icon: Icons.functions_rounded, requireType: _RequireType.effort, requiredMinutes: 180),
  _Challenge(id: 'a3', title: 'USE THE TIMER', description: "Submit a stopwatch session in academics.", diff: _Diff.easy, elo: 50, icon: Icons.access_time_rounded, requireType: _RequireType.stopwatch),
  _Challenge(id: 'a4', title: 'STUDY 2 HOURS', description: "Log at least 120 study minutes today.", diff: _Diff.hard, elo: 125, icon: Icons.hourglass_top_rounded, requireType: _RequireType.effort, requiredMinutes: 120),
  _Challenge(id: 'a5', title: 'UPDATE YOUR GRADE', description: "Update your academic grade today.", diff: _Diff.hard, elo: 100, icon: Icons.school_rounded, requireType: _RequireType.gradeUpdate, needsContextTrap: true),
  _Challenge(id: 'a6', title: 'STUDY 4 HOURS', description: "Log at least 240 study minutes today.", diff: _Diff.elite, elo: 200, icon: Icons.workspace_premium_rounded, requireType: _RequireType.effort, requiredMinutes: 240),
];

const _runPool = <_Challenge>[
  _Challenge(id: 'r0', title: 'LOG A RUN', description: "Log at least 10 running minutes today.", diff: _Diff.easy, elo: 50, icon: Icons.directions_run_rounded, requireType: _RequireType.effort, requiredMinutes: 10),
  _Challenge(id: 'r1', title: '30 MINUTE RUN', description: "Log at least 30 running minutes today.", diff: _Diff.hard, elo: 100, icon: Icons.speed_rounded, requireType: _RequireType.effort, requiredMinutes: 30),
  _Challenge(id: 'r2', title: '60 MINUTE RUN', description: "Log at least 60 running minutes today.", diff: _Diff.elite, elo: 200, icon: Icons.emoji_events_rounded, requireType: _RequireType.effort, requiredMinutes: 60),
  _Challenge(id: 'r3', title: 'USE THE TIMER', description: "Submit a stopwatch session in running.", diff: _Diff.easy, elo: 50, icon: Icons.access_time_rounded, requireType: _RequireType.stopwatch),
  _Challenge(id: 'r4', title: '45 MINUTE RUN', description: "Log at least 45 running minutes today.", diff: _Diff.hard, elo: 125, icon: Icons.timeline_rounded, requireType: _RequireType.effort, requiredMinutes: 45),
  _Challenge(id: 'r5', title: 'UPDATE YOUR 5K', description: "Update your 5K personal best today.", diff: _Diff.hard, elo: 100, icon: Icons.flag_rounded, requireType: _RequireType.fiveKUpdate, needsContextTrap: true),
  _Challenge(id: 'r6', title: '90 MIN ENDURANCE', description: "Log at least 90 running minutes today.", diff: _Diff.elite, elo: 200, icon: Icons.bolt_rounded, requireType: _RequireType.effort, requiredMinutes: 90),
];

const _lumPool = <_Challenge>[
  _Challenge(id: 'l0', title: 'LOG A SESSION', description: "Log at least 15 luminary minutes today.", diff: _Diff.easy, elo: 50, icon: Icons.auto_awesome_rounded, requireType: _RequireType.effort, requiredMinutes: 15),
  _Challenge(id: 'l1', title: 'DEEP WORK HOUR', description: "Log at least 60 luminary minutes today.", diff: _Diff.hard, elo: 100, icon: Icons.local_fire_department_rounded, requireType: _RequireType.effort, requiredMinutes: 60),
  _Challenge(id: 'l2', title: 'DEEP WORK 3 HOURS', description: "Log at least 180 luminary minutes today.", diff: _Diff.elite, elo: 200, icon: Icons.brush_rounded, requireType: _RequireType.effort, requiredMinutes: 180),
  _Challenge(id: 'l3', title: 'USE THE TIMER', description: "Submit a stopwatch session in luminary.", diff: _Diff.easy, elo: 50, icon: Icons.access_time_rounded, requireType: _RequireType.stopwatch),
  _Challenge(id: 'l4', title: 'DEEP WORK 2 HOURS', description: "Log at least 120 luminary minutes today.", diff: _Diff.hard, elo: 125, icon: Icons.waves_rounded, requireType: _RequireType.effort, requiredMinutes: 120),
  _Challenge(id: 'l5', title: 'UPDATE BASELINE', description: "Update your weekly deep-work hours today.", diff: _Diff.hard, elo: 100, icon: Icons.tune_rounded, requireType: _RequireType.baselineUpdate, needsContextTrap: true),
  _Challenge(id: 'l6', title: 'DEEP WORK 4 HOURS', description: "Log at least 240 luminary minutes today.", diff: _Diff.elite, elo: 200, icon: Icons.star_rounded, requireType: _RequireType.effort, requiredMinutes: 240),
];

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

String _todayStr() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

List<_Challenge> _pickThree(List<_Challenge> pool, int seed) {
  final day = DateTime.now().difference(DateTime(2000, 1, 1)).inDays;
  final base = (day + seed).abs();
  final n = pool.length;
  final i0 = base % n;
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

List<_Challenge> _poolForPath(String path) {
  switch (path) {
    case 'gym':      return _gymPool;
    case 'academic': return _acadPool;
    case 'running':  return _runPool;
    case 'luminary': return _lumPool;
    default:         return _gymPool;
  }
}

int _seedForPath(String path) {
  switch (path) {
    case 'gym':      return 0;
    case 'academic': return 11;
    case 'running':  return 23;
    case 'luminary': return 37;
    default:         return 0;
  }
}

String _effortKey(String path) {
  switch (path) {
    case 'gym':      return 'gym';
    case 'academic': return 'academic';
    case 'running':  return 'running';
    case 'luminary': return 'luminary';
    default:         return 'gym';
  }
}

String _stopwatchFlagKey(String path) {
  switch (path) {
    case 'gym':      return 'gymStopwatchSubmit';
    case 'academic': return 'academicStopwatchSubmit';
    case 'running':  return 'runningStopwatchSubmit';
    case 'luminary': return 'luminaryStopwatchSubmit';
    default:         return 'gymStopwatchSubmit';
  }
}

String _eloField(String path) {
  switch (path) {
    case 'gym':      return 'effortElo';
    case 'academic': return 'academicEffortElo';
    case 'running':  return 'runningEffortElo';
    case 'luminary': return 'luminaryEffortElo';
    default:         return 'effortElo';
  }
}

// ─── Embedded Challenges Section ─────────────────────────────────────────────

class EmbeddedChallengesSection extends StatefulWidget {
  final String path;
  final Color accent;

  const EmbeddedChallengesSection({
    super.key,
    required this.path,
    required this.accent,
  });

  @override
  State<EmbeddedChallengesSection> createState() => _EmbeddedChallengesSectionState();
}

class _EmbeddedChallengesSectionState extends State<EmbeddedChallengesSection> {
  List<_Challenge> _challenges = [];
  final Set<String> _completed = {};
  int _bonusEloToday = 0;
  Map<String, dynamic> _todayEffort = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    final savedDate = data['challengeDate'] as String? ?? '';
    final savedCompleted = List<String>.from(data['completedChallengeIds'] ?? []);
    final savedBonus = (data['challengeBonusEloToday'] as num?)?.toInt() ?? 0;
    final effort = await AnticheatService.getTodayEffort();

    final pool = _poolForPath(widget.path);
    final seed = _seedForPath(widget.path);
    final challenges = _pickThree(pool, seed);

    if (mounted) {
      setState(() {
        _challenges = challenges;
        _todayEffort = effort;
        if (savedDate == _todayStr()) {
          _completed.addAll(savedCompleted);
          _bonusEloToday = savedBonus;
        }
        _loading = false;
      });
    }
  }

  bool _isRequirementMet(_Challenge c) {
    switch (c.requireType) {
      case _RequireType.effort:
        final logged = (_todayEffort[_effortKey(widget.path)] as num?)?.toInt() ?? 0;
        return logged >= c.requiredMinutes;
      case _RequireType.stopwatch:
        return _todayEffort[_stopwatchFlagKey(widget.path)] == true;
      case _RequireType.liftUpdate:
        return _todayEffort['liftUpdate'] == true;
      case _RequireType.gradeUpdate:
        return _todayEffort['gradeUpdate'] == true;
      case _RequireType.fiveKUpdate:
        return _todayEffort['fiveKUpdate'] == true;
      case _RequireType.baselineUpdate:
        return _todayEffort['baselineUpdate'] == true;
    }
  }

  Future<void> _completeChallenge(_Challenge challenge) async {
    if (_completed.contains(challenge.id)) return;
    if (!_isRequirementMet(challenge)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

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
      _eloField(widget.path): FieldValue.increment(challenge.elo),
    });
  }

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
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: '.SF Pro Display'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'What did you change and why?',
                      style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5), fontFamily: '.SF Pro Display'),
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
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kGold, width: 0.7)),
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
                              setDialogState(() => errorText = 'Please provide a specific, detailed response (20+ chars, 3+ words).');
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_challenges.isEmpty) return const SizedBox.shrink();

    final done = _challenges.where((c) => _completed.contains(c.id)).length;
    final allDone = done >= _challenges.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.bolt_rounded, color: widget.accent, size: 15),
            ),
            const SizedBox(width: 10),
            Text(
              'DAILY CHALLENGES',
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: widget.accent, letterSpacing: 1.6,
                fontFamily: '.SF Pro Display', height: 1,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: allDone
                    ? widget.accent.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: allDone ? widget.accent.withValues(alpha: 0.40) : Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (allDone) ...[
                    Icon(Icons.check_rounded, color: widget.accent, size: 10),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    allDone ? 'DONE' : '$done/${_challenges.length}',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: allDone ? widget.accent : Colors.white.withValues(alpha: 0.35),
                      letterSpacing: 0.6, fontFamily: '.SF Pro Display', height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._challenges.map((c) => _EmbeddedChallengeCard(
          challenge: c,
          completed: _completed.contains(c.id),
          requirementMet: _completed.contains(c.id) || _isRequirementMet(c),
          accent: widget.accent,
          onComplete: () => _completeChallenge(c),
        )),
      ],
    );
  }
}

// ─── Challenge Card ───────────────────────────────────────────────────────────

class _EmbeddedChallengeCard extends StatefulWidget {
  final _Challenge challenge;
  final bool completed;
  final bool requirementMet;
  final Color accent;
  final VoidCallback onComplete;

  const _EmbeddedChallengeCard({
    required this.challenge,
    required this.completed,
    required this.requirementMet,
    required this.accent,
    required this.onComplete,
  });

  @override
  State<_EmbeddedChallengeCard> createState() => _EmbeddedChallengeCardState();
}

class _EmbeddedChallengeCardState extends State<_EmbeddedChallengeCard>
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
  void didUpdateWidget(_EmbeddedChallengeCard old) {
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
    final color = widget.accent;
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
                              width: 36, height: 36,
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
                                      Text('+${c.elo}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kGold, fontFamily: '.SF Pro Display', height: 1)),
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
                            fontSize: 13,
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
                                  : _LockedButton(key: const ValueKey('locked'), challenge: c),
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
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

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
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: widget.color, letterSpacing: 0.9, fontFamily: '.SF Pro Display', height: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedButton extends StatelessWidget {
  final _Challenge challenge;
  const _LockedButton({super.key, required this.challenge});

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
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.25), letterSpacing: 0.7, fontFamily: '.SF Pro Display', height: 1),
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
        Text('COMPLETED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.9, fontFamily: '.SF Pro Display', height: 1)),
        const SizedBox(width: 7),
        Text('· +$elo ELO earned', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.30), fontFamily: '.SF Pro Display', height: 1)),
      ],
    );
  }
}
