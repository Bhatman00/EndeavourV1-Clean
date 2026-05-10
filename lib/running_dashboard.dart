import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'rank_utils.dart';
import 'rank_badge_painters.dart';
import 'juice_widgets.dart' hide Curves;
import 'stopwatch_service.dart';
import 'anticheat_service.dart';

const Color _kAccent    = Color(0xFF30D158);
const Color _kAccentDim = Color(0xFF1E8A3A);
const Color _kBg0       = Color(0xFF070F09);
const Color _kBg1       = Color(0xFF0C1C10);

// 5K time → skill ELO (unified 500–2500 scale).
// Formula: 2,250,000 / totalSec — pure inverse, no offset.
// Anchors:
//   75:00 (4500s) → 500   (Beginner floor)
//   25:00 (1500s) → 1500  (Intermediate)
//   15:00 (900s)  → 2500  (Elite)
int _timeToSkillElo(int minutes, int seconds) {
  final totalSec = (minutes * 60 + seconds).clamp(1, 9999);
  final double elo = 2250000.0 / totalSec;
  return elo.clamp(500.0, 3000.0).toInt();
}

String _paceString(int minutes, int seconds) {
  final totalSec = minutes * 60 + seconds;
  if (totalSec <= 0) return '—';
  // pace per km for a 5K
  final perKmSec = totalSec / 5;
  final m = (perKmSec ~/ 60);
  final s = (perKmSec % 60).round();
  return '$m:${s.toString().padLeft(2, '0')}/km';
}

// ─── State ────────────────────────────────────────────────────────────────────

class RunningDashboard extends StatefulWidget {
  const RunningDashboard({super.key});
  @override
  State<RunningDashboard> createState() => _RunningDashboardState();
}

class _RunningDashboardState extends State<RunningDashboard>
    with WidgetsBindingObserver {
  bool _baselineSet  = false;
  bool _isLoading    = true;
  int  _skillElo     = 0;
  int  _effortElo    = 0;
  int  _prevTotalElo = 0;
  String? _prevRankName;
  bool _showCelebration = false;
  Rank? _currentRank;

  double _effortSliderValue = 20;
  int _baseline5kMinutes = 30;
  int _baseline5kSeconds = 0;
  int _streak = 0;

  bool _stopwatchRunning = false;
  int  _stopwatchSeconds = 0;
  Timer? _stopwatchTimer;

  int get _totalElo => _skillElo + _effortElo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchUserData();
    _restoreStopwatchState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopwatchTimer?.cancel();
    if (_stopwatchRunning) {
      StopwatchService.saveRunningStopwatchStart(
        DateTime.now().millisecondsSinceEpoch - (_stopwatchSeconds * 1000),
      );
    } else {
      StopwatchService.clearRunningStopwatch();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_stopwatchRunning) {
        _stopwatchTimer?.cancel();
        StopwatchService.saveRunningStopwatchStart(
          DateTime.now().millisecondsSinceEpoch - (_stopwatchSeconds * 1000),
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      _restoreStopwatchState();
    }
  }

  Future<void> _restoreStopwatchState() async {
    final wasRunning = await StopwatchService.isRunningStopwatchRunning();
    if (wasRunning && mounted) {
      final elapsed = await StopwatchService.getRunningElapsedSeconds();
      setState(() => _stopwatchSeconds = elapsed);
      _startStopwatch();
    }
  }

  void _startStopwatch() {
    if (_stopwatchRunning) return;
    setState(() => _stopwatchRunning = true);
    _stopwatchTimer = Timer.periodic(
      const Duration(seconds: 1), (_) => setState(() => _stopwatchSeconds++));
  }

  void _stopStopwatch() {
    _stopwatchTimer?.cancel();
    setState(() => _stopwatchRunning = false);
  }

  void _resetStopwatch() {
    _stopwatchTimer?.cancel();
    setState(() { _stopwatchRunning = false; _stopwatchSeconds = 0; });
    StopwatchService.clearRunningStopwatch();
  }

  void _showFriendlyCapDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Text('😴', style: TextStyle(fontSize: 28)),
            SizedBox(width: 10),
            Expanded(
              child: Text('Whoa there, champ!',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: const Text(
          "You've been running for 18+ hours today. At this point you're basically Forrest Gump.\n\nRest days aren't weakness — they're where your body actually gets faster. Hydrate, stretch, and come back tomorrow to crush it again. 🏃",
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fine, I\'ll rest 😤',
              style: TextStyle(color: Color(0xFF00C9A7), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitStopwatchTime() async {
    int effortMins = (_stopwatchSeconds / 60).round();
    if (effortMins <= 0) effortMins = 1;

    // Anticheat: daily effort cap
    final capStatus = await AnticheatService.checkDailyEffortCap(effortMins, 'running');
    if (capStatus != DailyCapStatus.allowed) {
      if (mounted) {
        if (capStatus == DailyCapStatus.softCapped) {
          _showFriendlyCapDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Daily effort limit reached (24h max).')),
          );
        }
      }
      return;
    }

    final uid = _uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final current = doc['runningEffortElo'] as int? ?? 0;
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'runningEffortElo': current + effortMins}, SetOptions(merge: true));
        _resetStopwatch();
        // Anticheat: log daily effort + stopwatch flag
        await AnticheatService.logDailyEffort(effortMins, 'running', activityFlag: 'runningStopwatchSubmit');
        _fetchUserData();
        _updateStreak();
      } catch (e) {
        debugPrint('Error submitting run: $e');
      }
    }
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static String _todayStr() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }

  static String _yesterdayStr() {
    final d = DateTime.now().subtract(const Duration(days: 1));
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }

  Future<void> _updateStreak() async {
    final uid = _uid;
    if (uid == null) return;
    final today = _todayStr();
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      final lastDate = data['runningLastActivityDate'] as String?;
      final current = data['runningStreakCount'] as int? ?? 0;
      if (lastDate == today) return;
      final newStreak = lastDate == _yesterdayStr() ? current + 1 : 1;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'runningLastActivityDate': today,
        'runningStreakCount': newStreak,
      }, SetOptions(merge: true));
      if (mounted) setState(() => _streak = newStreak);
    } catch (e) {
      debugPrint('Error updating running streak: $e');
    }
  }

  Future<void> _fetchUserData() async {
    final uid = _uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            _prevTotalElo         = _totalElo;
            _skillElo             = data['runningSkillElo']   ?? 0;
            _effortElo            = data['runningEffortElo']  ?? 0;
            _streak               = data['runningStreakCount'] as int? ?? 0;
            _baseline5kMinutes    = data['running5kMinutes']  ?? 30;
            _baseline5kSeconds    = data['running5kSeconds']  ?? 0;
            _currentRank          = RankUtils.getRank(_totalElo, RankUtils.runningRanks);
            _prevRankName         = _currentRank?.name;
            _baselineSet = data['runningBaselineSet'] == true;
          });
        }
      } catch (e) {
        debugPrint('Error fetching running data: $e');
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveBaseline(int minutes, int seconds, {bool resetEffort = true}) async {
    // Anticheat: check 5K improvement rate
    await AnticheatService.checkRunning5kImprovement(
      newMinutes: minutes,
      newSeconds: seconds,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final newSkillElo = _timeToSkillElo(minutes, seconds);
      final uid = _uid;
      if (uid != null) {
        final data = <String, dynamic>{
          'runningSkillElo':    newSkillElo,
          'running5kMinutes':   minutes,
          'running5kSeconds':   seconds,
          'runningBaselineSet': true,
        };
        if (resetEffort) data['runningEffortElo'] = 0;
        await FirebaseFirestore.instance.collection('users').doc(uid)
            .set(data, SetOptions(merge: true));
        // Anticheat: store 5K baseline
        await AnticheatService.storeRunningBaseline(
          minutes: minutes,
          seconds: seconds,
        );
        if (mounted) Navigator.of(context).pop();
        setState(() {
          _prevTotalElo      = _totalElo;
          _skillElo          = newSkillElo;
          if (resetEffort) _effortElo = 0;
          _baselineSet       = true;
          _baseline5kMinutes = minutes;
          _baseline5kSeconds = seconds;
          _currentRank       = RankUtils.getRank(_totalElo, RankUtils.runningRanks);
        });
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<bool> _addEffort() async {
    final mins = _effortSliderValue.toInt();
    if (mins <= 0) return false;

    // Anticheat: daily effort cap
    final capStatus = await AnticheatService.checkDailyEffortCap(mins, 'running');
    if (capStatus != DailyCapStatus.allowed) {
      if (mounted) {
        if (capStatus == DailyCapStatus.softCapped) {
          _showFriendlyCapDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Daily effort limit reached (24h max).')),
          );
        }
      }
      return false;
    }

    HapticFeedback.lightImpact();
    final newTotal = _totalElo + mins;
    final newRank  = RankUtils.getRank(newTotal, RankUtils.runningRanks);
    setState(() {
      _prevTotalElo       = _totalElo;
      _effortElo         += mins;
      _effortSliderValue  = 20;
      if (_prevRankName != null && newRank.name != _prevRankName) {
        _showCelebration = true;
        _currentRank = newRank;
      }
      _prevRankName = newRank.name;
    });
    final uid = _uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'runningEffortElo': FieldValue.increment(mins)}, SetOptions(merge: true));
    }
    // Anticheat: log daily effort
    await AnticheatService.logDailyEffort(mins, 'running');
    _updateStreak();
    return true;
  }

  void _showEffortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EffortSheet(
        sliderValue: _effortSliderValue,
        onSliderChanged: (v) => setState(() => _effortSliderValue = v),
        onAddEffort: _addEffort,
      ),
    );
  }

  void _showEditBaselineDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _OnboardingCard(
          initialMinutes: _baseline5kMinutes,
          initialSeconds: _baseline5kSeconds,
          onSave: (m, s) async {
            await _saveBaseline(m, s, resetEffort: false);
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg0,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_baselineSet)
            IconButton(
              icon: const Icon(Icons.tune_rounded, size: 20),
              onPressed: _showEditBaselineDialog,
            ),
        ],
      ),
      body: Stack(
        children: [
          const SizedBox.expand(child: _RunningWallpaper()),
          SafeArea(
            child: Stack(
              children: [
                if (_isLoading)
                  const Center(child: CircularProgressIndicator(color: _kAccent))
                else
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: _baselineSet
                        ? _DashboardView(
                            key: const ValueKey('dash'),
                            totalElo:       _totalElo,
                            prevTotalElo:   _prevTotalElo,
                            skillElo:       _skillElo,
                            effortElo:      _effortElo,
                            stopwatchSecs:  _stopwatchSeconds,
                            stopwatchRunning: _stopwatchRunning,
                            onStart:  _startStopwatch,
                            onStop:   _stopStopwatch,
                            onReset:  _resetStopwatch,
                            onSubmit: _submitStopwatchTime,
                            onLogRun: _showEffortSheet,
                            rank: RankUtils.getRank(_totalElo, RankUtils.runningRanks),
                            streak:   _streak,
                            baseline5kMinutes: _baseline5kMinutes,
                            baseline5kSeconds: _baseline5kSeconds,
                          )
                        : _OnboardingCard(
                            key: const ValueKey('onboard'),
                            initialMinutes: _baseline5kMinutes,
                            initialSeconds: _baseline5kSeconds,
                            onSave: _saveBaseline,
                          ),
                  ),
                if (_showCelebration && _currentRank != null)
                  RankUpCelebration(
                    newRank: _currentRank!,
                    onDismiss: () => setState(() => _showCelebration = false),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Wallpaper ────────────────────────────────────────────────────────────────

class _RunningWallpaper extends StatelessWidget {
  const _RunningWallpaper();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _WallpaperPainter(bg0: _kBg0, bg1: _kBg1, accent: _kAccent));
}

class _WallpaperPainter extends CustomPainter {
  final Color bg0, bg1, accent;
  const _WallpaperPainter({required this.bg0, required this.bg1, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [bg0, bg1, bg0], stops: const [0, 0.6, 1],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(-0.6, -1.1), radius: 1.0,
        colors: [accent.withAlpha(80), Colors.transparent],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(1.1, -0.4), radius: 0.8,
        colors: [accent.withAlpha(45), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(_WallpaperPainter old) => false;
}

// ─── Dashboard View ───────────────────────────────────────────────────────────

class _DashboardView extends StatelessWidget {
  final int totalElo, prevTotalElo, skillElo, effortElo;
  final int stopwatchSecs;
  final bool stopwatchRunning;
  final VoidCallback onStart, onStop, onReset, onLogRun;
  final Future<void> Function() onSubmit;
  final Rank rank;
  final int streak;
  final int baseline5kMinutes;
  final int baseline5kSeconds;

  const _DashboardView({
    super.key,
    required this.totalElo, required this.prevTotalElo,
    required this.skillElo, required this.effortElo,
    required this.stopwatchSecs, required this.stopwatchRunning,
    required this.onStart, required this.onStop, required this.onReset,
    required this.onSubmit, required this.onLogRun, required this.rank,
    required this.streak,
    required this.baseline5kMinutes,
    required this.baseline5kSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final progress = RankUtils.rankProgress(totalElo, RankUtils.runningRanks);
    final next     = RankUtils.nextRank(totalElo, RankUtils.runningRanks);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroCard(
            totalElo: totalElo, prevTotalElo: prevTotalElo,
            rank: rank, rankProgress: progress, nextRank: next,
            accent: _kAccent,
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _GlassCard(child: _StatCard(
              label: 'SPEED',
              value: RankUtils.formatElo(skillElo),
              icon: Icons.speed_rounded,
              color: _kAccent,
            ))),
            const SizedBox(width: 10),
            Expanded(child: _GlassCard(child: _StatCard(
              label: 'ENDURANCE',
              value: RankUtils.formatElo(effortElo),
              icon: Icons.local_fire_department_rounded,
              color: const Color(0xFFFF9F0A),
            ))),
          ]),
          const SizedBox(height: 10),
          _RunningSummary(
            totalMinutes: effortElo,
            baseline5kMinutes: baseline5kMinutes,
            baseline5kSeconds: baseline5kSeconds,
            accent: _kAccent,
          ),
          const SizedBox(height: 10),
          _GlassCard(child: _SessionCard(
            seconds: stopwatchSecs, isRunning: stopwatchRunning,
            onStart: onStart, onStop: onStop, onReset: onReset,
            onSubmit: onSubmit, accent: _kAccent,
          )),
          const SizedBox(height: 10),
          _GradientButton(
            label: 'Log Run',
            icon: Icons.directions_run_rounded,
            onTap: onLogRun,
            accent: _kAccent, accentDim: _kAccentDim,
          ),
          const SizedBox(height: 10),
          _StreakCard(streak: streak, accent: _kAccent),
        ],
      ),
    );
  }
}

// ─── Hero Card ────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final int totalElo, prevTotalElo;
  final Rank rank;
  final double rankProgress;
  final Rank? nextRank;
  final Color accent;

  const _HeroCard({
    required this.totalElo, required this.prevTotalElo,
    required this.rank, required this.rankProgress,
    required this.nextRank, required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.8, -1), end: const Alignment(0.8, 1),
              colors: [accent.withAlpha(85), accent.withAlpha(34), Colors.white.withAlpha(5)],
              stops: const [0, 0.6, 1],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: accent.withAlpha(51), width: 0.5),
            boxShadow: [BoxShadow(color: accent.withAlpha(34), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent, Colors.white.withAlpha(71), Colors.transparent,
                    ]),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _RankBadge(
                    accent: accent,
                    size: 80,
                    rankIndex: RankUtils.runningRanks.indexOf(rank),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RankChip(label: rank.name, accent: accent),
                        const SizedBox(height: 4),
                        TweenAnimationBuilder<int>(
                          key: ValueKey(totalElo),
                          tween: IntTween(begin: prevTotalElo, end: totalElo),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, child) => Text(
                            RankUtils.formatElo(v),
                            style: TextStyle(
                              fontFamily: '.SF Pro Display',
                              fontSize: 50, fontWeight: FontWeight.w700,
                              color: Colors.white, height: 1, letterSpacing: -2,
                              shadows: [Shadow(color: accent.withAlpha(140), blurRadius: 28)],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(100),
                          child: LinearProgressIndicator(
                            value: rankProgress,
                            backgroundColor: Colors.white.withAlpha(20),
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                            minHeight: 4,
                          ),
                        ),
                        if (nextRank != null) ...[
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(child: Text(nextRank!.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 9, color: Colors.white.withAlpha(102),
                                    fontFamily: '.SF Pro Display', letterSpacing: 0.3))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent.withAlpha(28),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  '${RankUtils.formatElo(RankUtils.eloToNext(totalElo, RankUtils.runningRanks))} to go',
                                  style: TextStyle(
                                    fontSize: 9, fontWeight: FontWeight.w600,
                                    color: accent.withAlpha(200),
                                    fontFamily: '.SF Pro Display', letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 5),
                          Text('MAX RANK', style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w700,
                            color: accent.withAlpha(200),
                            fontFamily: '.SF Pro Display', letterSpacing: 1.0,
                          )),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Rank Badge ───────────────────────────────────────────────────────────────

class _RankBadge extends StatelessWidget {
  final Color accent;
  final double size;
  final int rankIndex;
  const _RankBadge({
    required this.accent,
    required this.size,
    required this.rankIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: accent.withAlpha(100), blurRadius: 20, spreadRadius: 2)],
      ),
      child: CustomPaint(
        painter: getRankBadgePainter('running', rankIndex, accent),
      ),
    );
  }
}

class _RankChip extends StatelessWidget {
  final String label;
  final Color accent;
  const _RankChip({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withAlpha(51),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: accent.withAlpha(71), width: 0.5),
      ),
      child: Text(label, style: const TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700,
        color: Colors.white, fontFamily: '.SF Pro Display', letterSpacing: 0.5,
      )),
    );
  }
}

// ─── Running Summary ──────────────────────────────────────────────────────────
//
// Shows live-feel metrics derived from logged minutes (effortElo stores minutes).
//
class _RunningSummary extends StatelessWidget {
  final int totalMinutes;
  final int baseline5kMinutes;
  final int baseline5kSeconds;
  final Color accent;

  const _RunningSummary({
    required this.totalMinutes,
    required this.baseline5kMinutes,
    required this.baseline5kSeconds,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final totalHours = totalMinutes / 60.0;
    // Approx runs logged — assume average run ≈ 25 minutes
    final runs = (totalMinutes / 25).round();
    final pace = _paceString(baseline5kMinutes, baseline5kSeconds);

    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            _MiniMetric(
              icon: Icons.timer_rounded,
              value: totalHours >= 10
                  ? '${totalHours.toStringAsFixed(0)}h'
                  : '${totalHours.toStringAsFixed(1)}h',
              label: 'TIME',
              color: accent,
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 34, color: Colors.white.withAlpha(18)),
            const SizedBox(width: 14),
            _MiniMetric(
              icon: Icons.flag_circle_rounded,
              value: '$runs',
              label: 'RUNS',
              color: const Color(0xFFFF9F0A),
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 34, color: Colors.white.withAlpha(18)),
            const SizedBox(width: 14),
            _MiniMetric(
              icon: Icons.bolt_rounded,
              value: pace,
              label: '5K PACE',
              color: Colors.white.withAlpha(200),
              small: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool small;
  const _MiniMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: small ? 12 : 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFamily: '.SF Pro Display',
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: Colors.white.withAlpha(115),
              letterSpacing: 0.7,
              fontFamily: '.SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: color.withAlpha(31), borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withAlpha(51), width: 0.5),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700,
              color: Colors.white, fontFamily: '.SF Pro Display', height: 1)),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: Colors.white.withAlpha(89), letterSpacing: 0.8, fontFamily: '.SF Pro Display')),
        ]),
      ]),
    );
  }
}

// ─── Session Card ─────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final int seconds;
  final bool isRunning;
  final VoidCallback onStart, onStop, onReset;
  final Future<void> Function() onSubmit;
  final Color accent;

  const _SessionCard({
    required this.seconds, required this.isRunning,
    required this.onStart, required this.onStop, required this.onReset,
    required this.onSubmit, required this.accent,
  });

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final mins = (seconds / 60).round().clamp(1, 999);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(children: [
        Icon(Icons.directions_run_rounded, size: 15, color: Colors.white.withAlpha(76)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(_fmt(seconds), style: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white,
            fontFamily: '.SF Pro Display', letterSpacing: -0.5, height: 1)),
          const SizedBox(height: 2),
          Text('+$mins ELO on log', style: TextStyle(fontSize: 10,
              color: Colors.white.withAlpha(89), fontFamily: '.SF Pro Display')),
        ]),
        const Spacer(),
        _PillBtn(
          onTap: isRunning ? onStop : onStart,
          label: isRunning ? 'Pause' : 'Start',
          icon: isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: isRunning ? Colors.white.withAlpha(25) : accent.withAlpha(230),
          textColor: Colors.white,
        ),
        const SizedBox(width: 6),
        _SmallIconBtn(icon: Icons.refresh_rounded, onTap: onReset,
            color: Colors.white.withAlpha(18), iconColor: Colors.white.withAlpha(102)),
        if (seconds > 0) ...[
          const SizedBox(width: 6),
          _PillBtn(
            onTap: () { HapticFeedback.mediumImpact(); onSubmit(); },
            label: 'Log', icon: Icons.check_rounded,
            color: accent, textColor: Colors.white,
          ),
        ],
      ]),
    );
  }
}

// ─── Gradient Button ──────────────────────────────────────────────────────────

class _GradientButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color accent, accentDim;
  const _GradientButton({required this.label, required this.icon,
      required this.onTap, required this.accent, required this.accentDim});

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); HapticFeedback.mediumImpact(); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.8, -1), end: const Alignment(0.8, 1),
              colors: [widget.accent, widget.accentDim],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: widget.accent.withAlpha(100), blurRadius: 20, offset: const Offset(0, 6))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(widget.label, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white,
                fontFamily: '.SF Pro Display', letterSpacing: -0.2)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Effort Sheet ─────────────────────────────────────────────────────────────

class _EffortSheet extends StatefulWidget {
  final double sliderValue;
  final ValueChanged<double> onSliderChanged;
  final Future<bool> Function() onAddEffort;

  const _EffortSheet({required this.sliderValue, required this.onSliderChanged, required this.onAddEffort});

  @override
  State<_EffortSheet> createState() => _EffortSheetState();
}

class _EffortSheetState extends State<_EffortSheet> {
  bool _saving = false;
  late double _localValue;

  @override
  void initState() {
    super.initState();
    _localValue = widget.sliderValue;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1A10),
            border: Border(top: BorderSide(color: Colors.white.withAlpha(25))),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 22),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(31),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Run Session', style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
                        fontFamily: '.SF Pro Display', letterSpacing: -0.4)),
                      Text('How long did you run?', style: TextStyle(
                        fontSize: 12, color: Colors.white.withAlpha(102), fontFamily: '.SF Pro Display')),
                    ]),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _kAccent.withAlpha(31), borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kAccent.withAlpha(76)),
                      ),
                      child: Text('${_localValue.toInt()} min', style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white,
                        fontFamily: '.SF Pro Display')),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: _kAccent,
                    inactiveTrackColor: Colors.white.withAlpha(25),
                    trackHeight: 4,
                    thumbColor: _kAccent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                  ),
                  child: Slider(
                    value: _localValue, min: 5, max: 120, divisions: 23,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _localValue = v);
                      widget.onSliderChanged(v);
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('5m', style: TextStyle(fontSize: 11,
                        color: Colors.white.withAlpha(64), fontFamily: '.SF Pro Display')),
                    Text('2h', style: TextStyle(fontSize: 11,
                        color: Colors.white.withAlpha(64), fontFamily: '.SF Pro Display')),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _saving
                            ? [const Color(0xFF34C759), const Color(0xFF2A9D47)]
                            : [_kAccent, _kAccentDim],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(
                        color: (_saving ? const Color(0xFF34C759) : _kAccent).withAlpha(100),
                        blurRadius: 20, offset: const Offset(0, 6))],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          if (_saving) return;
                          HapticFeedback.mediumImpact();
                          setState(() => _saving = true);
                          final ok = await widget.onAddEffort();
                          if (ok && mounted) Navigator.of(context).pop();
                          if (mounted) setState(() => _saving = false);
                        },
                        child: Center(child: Text(_saving ? 'Saved ✓' : 'Log Run',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                              color: Colors.white, fontFamily: '.SF Pro Display', letterSpacing: -0.2))),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Onboarding Card ──────────────────────────────────────────────────────────

class _OnboardingCard extends StatefulWidget {
  final int initialMinutes, initialSeconds;
  final Future<void> Function(int minutes, int seconds) onSave;

  const _OnboardingCard({
    super.key,
    required this.initialMinutes,
    required this.initialSeconds,
    required this.onSave,
  });

  @override
  State<_OnboardingCard> createState() => _OnboardingCardState();
}

class _OnboardingCardState extends State<_OnboardingCard> {
  late int _minutes;
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _minutes = widget.initialMinutes;
    _seconds = widget.initialSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final previewElo = _timeToSkillElo(_minutes, _seconds);
    final timeStr = '${_minutes.toString().padLeft(2, '0')}:${_seconds.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kAccent.withAlpha(56)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color: _kAccent.withAlpha(38), borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _kAccent.withAlpha(56)),
                    ),
                    child: const Icon(Icons.directions_run_rounded, color: _kAccent, size: 23),
                  ),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Running Setup', style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white,
                      fontFamily: '.SF Pro Display', letterSpacing: -0.5)),
                    Text('Enter your best 5K time', style: TextStyle(
                      fontSize: 12, color: Colors.white.withAlpha(102), fontFamily: '.SF Pro Display')),
                  ]),
                ]),
                const SizedBox(height: 24),
                // ELO preview
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _kAccent.withAlpha(20), borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kAccent.withAlpha(46)),
                  ),
                  child: Column(children: [
                    Text(RankUtils.formatElo(previewElo), textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700,
                          color: Colors.white, fontFamily: '.SF Pro Display', height: 1, letterSpacing: -1)),
                    const SizedBox(height: 3),
                    Text('Starting ELO', style: TextStyle(fontSize: 10,
                        color: Colors.white.withAlpha(89), fontFamily: '.SF Pro Display', letterSpacing: 0.6)),
                  ]),
                ),
                const SizedBox(height: 22),
                // Time display
                Center(
                  child: Text(timeStr, style: TextStyle(
                    fontSize: 42, fontWeight: FontWeight.w200, color: Colors.white,
                    fontFamily: '.SF Pro Display', letterSpacing: -2,
                    shadows: [Shadow(color: _kAccent.withAlpha(120), blurRadius: 24)],
                  )),
                ),
                const SizedBox(height: 4),
                Center(child: Text('5K TIME', style: TextStyle(
                  fontSize: 10, letterSpacing: 1.5, color: Colors.white.withAlpha(70),
                  fontFamily: '.SF Pro Display', fontWeight: FontWeight.w600))),
                const SizedBox(height: 6),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withAlpha(25), width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.speed_rounded, size: 11, color: _kAccent.withAlpha(200)),
                        const SizedBox(width: 4),
                        Text(
                          _paceString(_minutes, _seconds),
                          style: TextStyle(
                            fontSize: 11, color: Colors.white.withAlpha(180),
                            fontFamily: '.SF Pro Display', fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _fieldLabel('MINUTES  (${_minutes}m)'),
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: _kAccent,
                    inactiveTrackColor: Colors.white.withAlpha(25),
                    trackHeight: 4, thumbColor: _kAccent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                  ),
                  child: Slider(
                    value: _minutes.toDouble(), min: 12, max: 60, divisions: 48,
                    onChanged: (v) {
                      setState(() => _minutes = v.toInt());
                      HapticFeedback.selectionClick();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                _fieldLabel('SECONDS  (${_seconds}s)'),
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: _kAccent.withAlpha(180),
                    inactiveTrackColor: Colors.white.withAlpha(25),
                    trackHeight: 4, thumbColor: _kAccent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                  ),
                  child: Slider(
                    value: _seconds.toDouble(), min: 0, max: 59, divisions: 59,
                    onChanged: (v) {
                      setState(() => _seconds = v.toInt());
                      HapticFeedback.selectionClick();
                    },
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_kAccent, _kAccentDim]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(
                          color: _kAccent.withAlpha(100), blurRadius: 20, offset: const Offset(0, 6))],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          widget.onSave(_minutes, _seconds);
                        },
                        child: const Center(child: Text('Set Running ELO',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                              color: Colors.white, fontFamily: '.SF Pro Display', letterSpacing: -0.2))),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(text, style: TextStyle(
    fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(115),
    fontFamily: '.SF Pro Display', letterSpacing: 0.6));
}

// ─── Streak Card ──────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  final int streak;
  final Color accent;
  const _StreakCard({required this.streak, required this.accent});

  double get _multiplier => 1.0 + streak * 0.05;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A).withAlpha(28),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0xFFFF9F0A).withAlpha(46), width: 0.5),
                  ),
                  child: const Icon(Icons.local_fire_department_rounded,
                      color: Color(0xFFFF9F0A), size: 19),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(text: TextSpan(children: [
                      TextSpan(
                        text: streak == 0 ? '—' : '$streak',
                        style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700,
                          color: Colors.white, fontFamily: '.SF Pro Display', letterSpacing: -0.3),
                      ),
                      if (streak > 0) TextSpan(
                        text: ' day${streak == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400,
                            color: Colors.white.withAlpha(180), fontFamily: '.SF Pro Display'),
                      ),
                    ])),
                    Text(
                      streak == 0 ? 'Log today to start a streak' : 'Keep going — don\'t break it!',
                      style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(89),
                          fontFamily: '.SF Pro Display'),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(28),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withAlpha(65), width: 0.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('×${_multiplier.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                              color: Colors.white, fontFamily: '.SF Pro Display', letterSpacing: -0.2)),
                      Text('BOOST', style: TextStyle(fontSize: 8, color: Colors.white.withAlpha(140),
                          fontFamily: '.SF Pro Display', letterSpacing: 0.7, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: List.generate(7, (i) {
                final daysAgo = 6 - i;
                final d = today.subtract(Duration(days: daysAgo));
                final label = ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1];
                final isActive = daysAgo < streak;
                final isToday = daysAgo == 0;
                return Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive
                              ? (isToday ? accent : accent.withAlpha(155))
                              : Colors.white.withAlpha(isToday ? 28 : 15),
                          border: Border.all(
                            color: isToday ? accent.withAlpha(200) : Colors.transparent,
                            width: 1.5,
                          ),
                          boxShadow: isActive && isToday
                              ? [BoxShadow(color: accent.withAlpha(90), blurRadius: 8, spreadRadius: 1)]
                              : null,
                        ),
                        child: isActive
                            ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                            : (isToday
                                ? Icon(Icons.circle_outlined, size: 11, color: Colors.white.withAlpha(90))
                                : null),
                      ),
                      const SizedBox(height: 4),
                      Text(label,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                            color: Colors.white.withAlpha(isActive ? 160 : 50),
                            fontFamily: '.SF Pro Display',
                          )),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared primitives ────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(18),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withAlpha(31), width: 0.5),
          ),
          child: Stack(children: [
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.transparent, Colors.white.withAlpha(71), Colors.transparent,
                  ]),
                ),
              ),
            ),
            child,
          ]),
        ),
      ),
    );
  }
}

class _PillBtn extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final Color color, textColor;
  const _PillBtn({required this.onTap, required this.label, required this.icon,
      required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: textColor, fontFamily: '.SF Pro Display')),
        ]),
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color color, iconColor;
  const _SmallIconBtn({required this.onTap, required this.icon, required this.color, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 15, color: iconColor),
      ),
    );
  }
}
