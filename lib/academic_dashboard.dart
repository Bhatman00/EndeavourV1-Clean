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

// Web design tokens: Deep Indigo
const Color _kAccent = Color(0xFF6E5CFF);
const Color _kAccentDim = Color(0xFF4B3BCC);
const Color _kBg0 = Color(0xFF0A0A14);
const Color _kBg1 = Color(0xFF141428);

// ─────────────────────────────────────────────
// State
// ─────────────────────────────────────────────

class AcademicDashboard extends StatefulWidget {
  const AcademicDashboard({super.key});
  @override
  State<AcademicDashboard> createState() => _AcademicDashboardState();
}

class _AcademicDashboardState extends State<AcademicDashboard>
    with WidgetsBindingObserver {
  bool _baselineSet = false;
  bool _isLoading = true;
  int _academicSkillElo = 0;
  int _academicEffortElo = 0;
  int _previousTotalElo = 0;
  String? _previousRankName;
  bool _showCelebration = false;
  Rank? _currentRank;

  double _effortSliderValue = 30;
  String _selectedLevel = 'Bachelors';
  int _selectedGrade = 70;
  int _streak = 0;

  bool _stopwatchRunning = false;
  int _stopwatchSeconds = 0;
  Timer? _stopwatchTimer;

  // Unified 500–2500 scale: grade × multiplier.
  // Primary grade 50 → 500, Bachelors grade 75 → 1500, Above Bach. grade 100 → 2500.
  final Map<String, double> _levelMultipliers = {
    'Primary': 10.0,
    'Secondary': 15.0,
    'Bachelors': 20.0,
    'Above Bachelors': 25.0,
  };

  int get _totalElo => _academicSkillElo + _academicEffortElo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchUserData();
    _restoreAcademicStopwatchState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopwatchTimer?.cancel();
    if (_stopwatchRunning) {
      StopwatchService.saveAcademicStopwatchStart(
        DateTime.now().millisecondsSinceEpoch - (_stopwatchSeconds * 1000),
      );
    } else {
      StopwatchService.clearAcademicStopwatch();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_stopwatchRunning) {
        _stopwatchTimer?.cancel();
        StopwatchService.saveAcademicStopwatchStart(
          DateTime.now().millisecondsSinceEpoch - (_stopwatchSeconds * 1000),
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      _restoreAcademicStopwatchState();
    }
  }

  Future<void> _restoreAcademicStopwatchState() async {
    final wasRunning = await StopwatchService.isAcademicStopwatchRunning();
    if (wasRunning && mounted) {
      final elapsed = await StopwatchService.getAcademicElapsedSeconds();
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
    setState(() {
      _stopwatchRunning = false;
      _stopwatchSeconds = 0;
    });
    StopwatchService.clearAcademicStopwatch();
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
          "You've been studying for 18+ hours today. That's legendary commitment, but your brain is literally begging for a nap.\n\nYou retain more from 8 hours of study + sleep than 18 hours of raw grinding. Go rest, your future self will thank you. 🧠",
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fine, I\'ll rest 😤',
              style: TextStyle(color: Color(0xFF6E5CFF), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitStopwatchTime() async {
    int effortMins = (_stopwatchSeconds / 60).round();
    if (effortMins <= 0) effortMins = 1;

    // Anticheat: daily effort cap
    final capStatus = await AnticheatService.checkDailyEffortCap(effortMins, 'academic');
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

    final uid = await _getCurrentUid();
    if (uid != null) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final currentEffort = doc['academicEffortElo'] as int? ?? 0;
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'academicEffortElo': currentEffort + effortMins,
        }, SetOptions(merge: true));
        _resetStopwatch();
        // Anticheat: log daily effort + stopwatch flag
        await AnticheatService.logDailyEffort(effortMins, 'academic', activityFlag: 'academicStopwatchSubmit');
        _fetchUserData();
        _updateStreak();
      } catch (e) {
        debugPrint('Error submitting stopwatch time: $e');
      }
    }
  }

  Future<String?> _getCurrentUid() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return user.uid;
    return (await FirebaseAuth.instance.authStateChanges()
            .firstWhere((u) => u != null, orElse: () => null))
        ?.uid;
  }

  Future<void> _fetchUserData() async {
    final uid = await _getCurrentUid();
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            _previousTotalElo = _totalElo;
            _academicSkillElo = data['academicSkillElo'] ?? 0;
            _academicEffortElo = data['academicEffortElo'] ?? 0;
            _selectedLevel = data['academicLevelString'] ?? _selectedLevel;
            _selectedGrade = (data['academicGrade'] is int)
                ? data['academicGrade'] as int
                : _selectedGrade;
            _streak = data['academicStreakCount'] as int? ?? 0;
            _currentRank =
                RankUtils.getRank(_totalElo, RankUtils.academicRanks);
            _previousRankName = _currentRank?.name;
            _baselineSet = data['academicBaselineSet'] == true;
          });
        }
      } catch (e) {
        debugPrint('Error fetching academic data: $e');
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  static String _todayStr() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }

  static String _yesterdayStr() {
    final d = DateTime.now().subtract(const Duration(days: 1));
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }

  Future<void> _updateStreak() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final today = _todayStr();
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      final lastDate = data['academicLastActivityDate'] as String?;
      final current = data['academicStreakCount'] as int? ?? 0;
      if (lastDate == today) return;
      final newStreak = lastDate == _yesterdayStr() ? current + 1 : 1;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'academicLastActivityDate': today,
        'academicStreakCount': newStreak,
      }, SetOptions(merge: true));
      if (mounted) setState(() => _streak = newStreak);
    } catch (e) {
      debugPrint('Error updating academic streak: $e');
    }
  }

  Future<void> _saveAcademicBaseline(int gradeValue,
      {bool resetEffort = true}) async {
    if (gradeValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a valid grade!')));
      return;
    }

    // Anticheat: check grade jump correlation
    await AnticheatService.checkAcademicGradeJump(newGrade: gradeValue);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final multiplier = _levelMultipliers[_selectedLevel]!;
      final initialSkill = (gradeValue * multiplier).round();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final updateData = {
          'academicSkillElo': initialSkill,
          'academicGrade': gradeValue,
          'academicMultiplier': multiplier,
          'academicLevelString': _selectedLevel,
          'academicBaselineSet': true,
        };
        if (resetEffort) updateData['academicEffortElo'] = 0;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(updateData, SetOptions(merge: true));
        // Anticheat: store grade baseline
        await AnticheatService.storeAcademicBaseline(grade: gradeValue);
        if (mounted) Navigator.of(context).pop();
        setState(() {
          _previousTotalElo = _totalElo;
          _academicSkillElo = initialSkill;
          if (resetEffort) _academicEffortElo = 0;
          _baselineSet = true;
          _currentRank =
              RankUtils.getRank(_totalElo, RankUtils.academicRanks);
        });
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<bool> _addEffort() async {
    final mins = _effortSliderValue.toInt();
    if (mins <= 0) return false;

    // Anticheat: daily effort cap
    final capStatus = await AnticheatService.checkDailyEffortCap(mins, 'academic');
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
    final newRank = RankUtils.getRank(newTotal, RankUtils.academicRanks);
    setState(() {
      _previousTotalElo = _totalElo;
      _academicEffortElo += mins;
      _effortSliderValue = 30;
      if (_previousRankName != null && newRank.name != _previousRankName) {
        _showCelebration = true;
        _currentRank = newRank;
      }
      _previousRankName = newRank.name;
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'academicEffortElo': FieldValue.increment(mins),
      }, SetOptions(merge: true));
    }
    // Anticheat: log daily effort
    await AnticheatService.logDailyEffort(mins, 'academic');
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
        rank: RankUtils.getRank(_totalElo, RankUtils.academicRanks),
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
          selectedLevel: _selectedLevel,
          selectedGrade: _selectedGrade,
          levelMultipliers: _levelMultipliers,
          onLevelChanged: (v) => setState(() => _selectedLevel = v!),
          onGradeChanged: (v) => setState(() => _selectedGrade = v),
          onCalculate: (g) async {
            await _saveAcademicBaseline(g, resetEffort: false);
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
          // Wallpaper
          const SizedBox.expand(child: _AcademicWallpaper()),
          SafeArea(
            child: Stack(
              children: [
                if (_isLoading)
                  const Center(
                      child: CircularProgressIndicator(color: _kAccent))
                else
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: _baselineSet
                        ? _AcademicDashboardView(
                            key: const ValueKey('dash'),
                            totalElo: _totalElo,
                            previousTotalElo: _previousTotalElo,
                            skillElo: _academicSkillElo,
                            effortElo: _academicEffortElo,
                            stopwatchSeconds: _stopwatchSeconds,
                            stopwatchRunning: _stopwatchRunning,
                            onStart: _startStopwatch,
                            onStop: _stopStopwatch,
                            onReset: _resetStopwatch,
                            onSubmit: _submitStopwatchTime,
                            onLogEffort: _showEffortSheet,
                            rank: RankUtils.getRank(
                                _totalElo, RankUtils.academicRanks),
                            levelString: _selectedLevel,
                            streak: _streak,
                          )
                        : _OnboardingCard(
                            key: const ValueKey('onboard'),
                            selectedLevel: _selectedLevel,
                            selectedGrade: _selectedGrade,
                            levelMultipliers: _levelMultipliers,
                            onLevelChanged: (v) =>
                                setState(() => _selectedLevel = v!),
                            onGradeChanged: (v) =>
                                setState(() => _selectedGrade = v),
                            onCalculate: _saveAcademicBaseline,
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

// ─────────────────────────────────────────────
// Wallpaper
// ─────────────────────────────────────────────

class _AcademicWallpaper extends StatelessWidget {
  const _AcademicWallpaper();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _WallpaperPainter(
      bg0: _kBg0, bg1: _kBg1, accent: _kAccent,
    ));
  }
}

class _WallpaperPainter extends CustomPainter {
  final Color bg0, bg1, accent;
  _WallpaperPainter({required this.bg0, required this.bg1, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    // Base linear gradient
    canvas.drawRect(rect, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [bg0, bg1, bg0],
        stops: const [0, 0.6, 1],
      ).createShader(rect));
    // Top-left accent glow
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(-0.6, -1.1),
        radius: 1.0,
        colors: [accent.withAlpha(89), Colors.transparent],
      ).createShader(rect));
    // Right-side accent
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(1.1, -0.4),
        radius: 0.8,
        colors: [accent.withAlpha(48), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(_WallpaperPainter old) => false;
}

// ─────────────────────────────────────────────
// Dashboard View
// ─────────────────────────────────────────────

class _AcademicDashboardView extends StatelessWidget {
  final int totalElo;
  final int previousTotalElo;
  final int skillElo;
  final int effortElo;
  final int stopwatchSeconds;
  final bool stopwatchRunning;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final Future<void> Function() onSubmit;
  final VoidCallback onLogEffort;
  final Rank rank;
  final String levelString;
  final int streak;

  const _AcademicDashboardView({
    super.key,
    required this.totalElo,
    required this.previousTotalElo,
    required this.skillElo,
    required this.effortElo,
    required this.stopwatchSeconds,
    required this.stopwatchRunning,
    required this.onStart,
    required this.onStop,
    required this.onReset,
    required this.onSubmit,
    required this.onLogEffort,
    required this.rank,
    required this.levelString,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final progress = RankUtils.rankProgress(totalElo, RankUtils.academicRanks);
    final next = RankUtils.nextRank(totalElo, RankUtils.academicRanks);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroCard(
            totalElo: totalElo,
            previousTotalElo: previousTotalElo,
            rank: rank,
            rankProgress: progress,
            nextRank: next,
            rankImagePath: RankUtils.getAcademicRankImage(rank),
            accent: _kAccent,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _GlassCard(
                  child: _StatCardContent(
                    label: 'KNOWLEDGE',
                    value: RankUtils.formatElo(skillElo),
                    icon: Icons.menu_book_rounded,
                    color: const Color(0xFF9B8CFF),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GlassCard(
                  child: _StatCardContent(
                    label: 'STUDY TIME',
                    value: RankUtils.formatElo(effortElo),
                    icon: Icons.hourglass_top_rounded,
                    color: const Color(0xFFFF8A50),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AcademicSummary(
            totalMinutes: effortElo,
            level: levelString,
            accent: _kAccent,
          ),
          const SizedBox(height: 10),
          _GlassCard(
            child: _SessionCardContent(
              seconds: stopwatchSeconds,
              isRunning: stopwatchRunning,
              onStart: onStart,
              onStop: onStop,
              onReset: onReset,
              onSubmit: onSubmit,
              accent: _kAccent,
            ),
          ),
          const SizedBox(height: 10),
          _GradientActionButton(
            label: 'Log Study Time',
            icon: Icons.bolt_rounded,
            onTap: onLogEffort,
            accent: _kAccent,
            accentDim: _kAccentDim,
          ),
          const SizedBox(height: 10),
          _StreakCard(streak: streak, accent: _kAccent),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Hero Card (web: accentGlassSurface)
// ─────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final int totalElo;
  final int previousTotalElo;
  final Rank rank;
  final double rankProgress;
  final Rank? nextRank;
  final String rankImagePath;
  final Color accent;

  const _HeroCard({
    required this.totalElo,
    required this.previousTotalElo,
    required this.rank,
    required this.rankProgress,
    required this.nextRank,
    required this.rankImagePath,
    required this.accent,
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
              begin: const Alignment(-0.8, -1),
              end: const Alignment(0.8, 1),
              colors: [
                accent.withAlpha(85),
                accent.withAlpha(34),
                Colors.white.withAlpha(5),
              ],
              stops: const [0, 0.6, 1],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: accent.withAlpha(51), width: 0.5),
            boxShadow: [
              BoxShadow(
                color: accent.withAlpha(34),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Top shine
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withAlpha(71),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _RankBadge(
                    accent: accent,
                    size: 80,
                    rankIndex: RankUtils.academicRanks.indexOf(rank),
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
                          tween: IntTween(
                              begin: previousTotalElo, end: totalElo),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, child) => Text(
                            RankUtils.formatElo(v),
                            style: TextStyle(
                              fontFamily: '.SF Pro Display',
                              fontSize: 50,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1,
                              letterSpacing: -2,
                              shadows: [
                                Shadow(
                                  color: accent.withAlpha(140),
                                  blurRadius: 28,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(100),
                          child: LinearProgressIndicator(
                            value: rankProgress,
                            backgroundColor: Colors.white.withAlpha(20),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(accent),
                            minHeight: 4,
                          ),
                        ),
                        if (nextRank != null) ...[
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  nextRank!.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white.withAlpha(102),
                                    fontFamily: '.SF Pro Display',
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent.withAlpha(28),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  '${RankUtils.formatElo(RankUtils.eloToNext(totalElo, RankUtils.academicRanks))} to go',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: accent.withAlpha(200),
                                    fontFamily: '.SF Pro Display',
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 5),
                          Text(
                            'MAX RANK',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: accent.withAlpha(200),
                              fontFamily: '.SF Pro Display',
                              letterSpacing: 1.0,
                            ),
                          ),
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

// ─────────────────────────────────────────────
// Rank Badge (drawn, no PNG)
// ─────────────────────────────────────────────

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
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(100),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CustomPaint(
        painter: getRankBadgePainter('academic', rankIndex, accent),
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
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontFamily: '.SF Pro Display',
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Academic Summary
// ─────────────────────────────────────────────
//
// Minutes-based metrics surfaced from effort ELO (minutes accumulated).
//
class _AcademicSummary extends StatelessWidget {
  final int totalMinutes;
  final String level;
  final Color accent;
  const _AcademicSummary({
    required this.totalMinutes,
    required this.level,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final totalHours = totalMinutes / 60.0;
    // Approx sessions ~40min
    final sessions = (totalMinutes / 40).round();

    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            _MiniMetric(
              icon: Icons.schedule_rounded,
              value: totalHours >= 10
                  ? '${totalHours.toStringAsFixed(0)}h'
                  : '${totalHours.toStringAsFixed(1)}h',
              label: 'TOTAL',
              color: accent,
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 34, color: Colors.white.withAlpha(18)),
            const SizedBox(width: 14),
            _MiniMetric(
              icon: Icons.edit_note_rounded,
              value: '$sessions',
              label: 'SESSIONS',
              color: const Color(0xFFFF8A50),
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 34, color: Colors.white.withAlpha(18)),
            const SizedBox(width: 14),
            _MiniMetric(
              icon: Icons.school_rounded,
              value: _levelShort(level),
              label: 'LEVEL',
              color: Colors.white.withAlpha(200),
              small: true,
            ),
          ],
        ),
      ),
    );
  }

  String _levelShort(String level) {
    switch (level) {
      case 'Primary':
        return 'PRI';
      case 'Secondary':
        return 'SEC';
      case 'Bachelors':
        return 'BACH';
      case 'Above Bachelors':
        return 'MAS+';
    }
    return level;
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

// ─────────────────────────────────────────────
// Stat Card Content
// ─────────────────────────────────────────────

class _StatCardContent extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCardContent({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withAlpha(31),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withAlpha(51), width: 0.5),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 19,
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
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withAlpha(89),
                  letterSpacing: 0.8,
                  fontFamily: '.SF Pro Display',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Session Timer Content
// ─────────────────────────────────────────────

class _SessionCardContent extends StatelessWidget {
  final int seconds;
  final bool isRunning;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final Future<void> Function() onSubmit;
  final Color accent;

  const _SessionCardContent({
    required this.seconds,
    required this.isRunning,
    required this.onStart,
    required this.onStop,
    required this.onReset,
    required this.onSubmit,
    required this.accent,
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
      child: Row(
        children: [
          Icon(Icons.timer_outlined,
              size: 15, color: Colors.white.withAlpha(76)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmt(seconds),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontFamily: '.SF Pro Display',
                  letterSpacing: -0.5,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '+$mins ELO on log',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withAlpha(89),
                  fontFamily: '.SF Pro Display',
                ),
              ),
            ],
          ),
          const Spacer(),
          _PillBtn(
            onTap: isRunning ? onStop : onStart,
            label: isRunning ? 'Pause' : 'Start',
            icon: isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: isRunning
                ? Colors.white.withAlpha(25)
                : accent.withAlpha(230),
            textColor: Colors.white,
          ),
          const SizedBox(width: 6),
          _SmallIconBtn(
            icon: Icons.refresh_rounded,
            onTap: onReset,
            color: Colors.white.withAlpha(18),
            iconColor: Colors.white.withAlpha(102),
          ),
          if (seconds > 0) ...[
            const SizedBox(width: 6),
            _PillBtn(
              onTap: () {
                HapticFeedback.mediumImpact();
                onSubmit();
              },
              label: 'Log',
              icon: Icons.check_rounded,
              color: accent,
              textColor: Colors.white,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Gradient Action Button (web: "Commit" style)
// ─────────────────────────────────────────────

class _GradientActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;
  final Color accentDim;

  const _GradientActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.accent,
    required this.accentDim,
  });

  @override
  State<_GradientActionButton> createState() => _GradientActionButtonState();
}

class _GradientActionButtonState extends State<_GradientActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.8, -1),
              end: const Alignment(0.8, 1),
              colors: [widget.accent, widget.accentDim],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: widget.accent.withAlpha(100),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontFamily: '.SF Pro Display',
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Effort Bottom Sheet
// ─────────────────────────────────────────────

class _EffortSheet extends StatefulWidget {
  final double sliderValue;
  final ValueChanged<double> onSliderChanged;
  final Future<bool> Function() onAddEffort;
  final Rank rank;

  const _EffortSheet({
    required this.sliderValue,
    required this.onSliderChanged,
    required this.onAddEffort,
    required this.rank,
  });

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
            color: const Color(0xFF16161E),
            border: Border(
                top: BorderSide(color: Colors.white.withAlpha(25))),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 22),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(31),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Study Session',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontFamily: '.SF Pro Display',
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'How long did you study?',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withAlpha(102),
                            fontFamily: '.SF Pro Display',
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _kAccent.withAlpha(31),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: _kAccent.withAlpha(76)),
                      ),
                      child: Text(
                        '${_localValue.toInt()} min',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFamily: '.SF Pro Display',
                        ),
                      ),
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
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 11),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 18),
                  ),
                  child: Slider(
                    value: _localValue,
                    min: 5,
                    max: 180,
                    divisions: 35,
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
                    Text('5m',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withAlpha(64),
                            fontFamily: '.SF Pro Display')),
                    Text('3h',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withAlpha(64),
                            fontFamily: '.SF Pro Display')),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _saving
                            ? [const Color(0xFF34C759), const Color(0xFF2A9D47)]
                            : [_kAccent, _kAccentDim],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: (_saving
                              ? const Color(0xFF34C759)
                              : _kAccent).withAlpha(100),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
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
                        child: Center(
                          child: Text(
                            _saving ? 'Saved ✓' : 'Log Effort',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontFamily: '.SF Pro Display',
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
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

// ─────────────────────────────────────────────
// Onboarding Card
// ─────────────────────────────────────────────

class _OnboardingCard extends StatefulWidget {
  final String selectedLevel;
  final int selectedGrade;
  final Map<String, double> levelMultipliers;
  final ValueChanged<String?> onLevelChanged;
  final ValueChanged<int> onGradeChanged;
  final Function(int) onCalculate;

  const _OnboardingCard({
    super.key,
    required this.selectedLevel,
    required this.selectedGrade,
    required this.levelMultipliers,
    required this.onLevelChanged,
    required this.onGradeChanged,
    required this.onCalculate,
  });

  @override
  State<_OnboardingCard> createState() => _OnboardingCardState();
}

class _OnboardingCardState extends State<_OnboardingCard> {
  late String _level;
  late int _grade;

  @override
  void initState() {
    super.initState();
    _level = widget.selectedLevel;
    _grade = widget.selectedGrade;
  }

  @override
  Widget build(BuildContext context) {
    final previewElo = (_grade *
            (widget.levelMultipliers[_level] ?? 1.0))
        .round();

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
              border: Border.all(
                  color: _kAccent.withAlpha(56)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _kAccent.withAlpha(38),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _kAccent.withAlpha(56)),
                      ),
                      child: const Icon(Icons.school_rounded,
                          color: _kAccent, size: 23),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Academic Setup',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontFamily: '.SF Pro Display',
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Set your starting ELO',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withAlpha(102),
                            fontFamily: '.SF Pro Display',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _kAccent.withAlpha(20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kAccent.withAlpha(46)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        RankUtils.formatElo(previewElo),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFamily: '.SF Pro Display',
                          height: 1,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Starting ELO',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withAlpha(89),
                          fontFamily: '.SF Pro Display',
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _fieldLabel('Education Level'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.white.withAlpha(25)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: DropdownButton<String>(
                      value: _level,
                      dropdownColor: const Color(0xFF1C1C24),
                      underline: const SizedBox.shrink(),
                      iconEnabledColor: _kAccent,
                      isExpanded: true,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                        fontFamily: '.SF Pro Display',
                      ),
                      items: widget.levelMultipliers.keys
                          .map((l) =>
                              DropdownMenuItem(value: l, child: Text(l)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _level = v);
                          widget.onLevelChanged(v);
                          HapticFeedback.selectionClick();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _fieldLabel('Current Grade (WAM)'),
                    Text(
                      '$_grade%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontFamily: '.SF Pro Display',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: _kAccent,
                    inactiveTrackColor: Colors.white.withAlpha(25),
                    trackHeight: 4,
                    thumbColor: _kAccent,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 11),
                    overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 18),
                  ),
                  child: Slider(
                    value: _grade.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    onChanged: (v) {
                      setState(() => _grade = v.toInt());
                      widget.onGradeChanged(v.toInt());
                      HapticFeedback.selectionClick();
                    },
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_kAccent, _kAccentDim],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _kAccent.withAlpha(100),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          widget.onCalculate(_grade);
                        },
                        child: const Center(
                          child: Text(
                            'Set Academic ELO',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontFamily: '.SF Pro Display',
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
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

  Widget _fieldLabel(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white.withAlpha(115),
          fontFamily: '.SF Pro Display',
          letterSpacing: 0.6,
        ),
      );
}

// ─────────────────────────────────────────────
// Streak Card
// ─────────────────────────────────────────────

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

// ─────────────────────────────────────────────
// Shared primitives
// ─────────────────────────────────────────────

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
            border: Border.all(
              color: Colors.white.withAlpha(31),
              width: 0.5,
            ),
          ),
          child: Stack(
            children: [
              // Top shine (web: 1px absolute gradient)
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withAlpha(71),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PillBtn extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final Color color;
  final Color textColor;

  const _PillBtn({
    required this.onTap,
    required this.label,
    required this.icon,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: textColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
                fontFamily: '.SF Pro Display',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  final Color iconColor;

  const _SmallIconBtn({
    required this.onTap,
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 15, color: iconColor),
      ),
    );
  }
}
