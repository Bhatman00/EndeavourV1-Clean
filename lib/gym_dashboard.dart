import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'rank_utils.dart';
import 'rank_badge_painters.dart';
import 'juice_widgets.dart' hide Curves;
import 'lifting_utils.dart';
import 'stopwatch_service.dart';
import 'anticheat_service.dart';

// Web design tokens: Crimson
const Color _kAccent = Color(0xFFFF3B5C);
const Color _kAccentDim = Color(0xFFCC2440);
const Color _kBg0 = Color(0xFF0F0708);
const Color _kBg1 = Color(0xFF2A0E12);

// ─────────────────────────────────────────────
// State
// ─────────────────────────────────────────────

class GymDashboard extends StatefulWidget {
  const GymDashboard({super.key});
  @override
  State<GymDashboard> createState() => _GymDashboardState();
}

class _GymDashboardState extends State<GymDashboard>
    with WidgetsBindingObserver {
  String _gender = 'male';
  bool _baselineSet = false;
  bool _isLoading = true;
  int _skillElo = 0;
  int _effortElo = 0;
  int _previousTotalElo = 0;
  String? _previousRankName;
  bool _showCelebration = false;
  Rank? _currentRank;

  double _benchValue = 80;
  double _squatValue = 100;
  double _deadliftValue = 120;
  double _bodyweightValue = 75;

  bool _stopwatchRunning = false;
  int _stopwatchSeconds = 0;
  Timer? _stopwatchTimer;
  int _streak = 0;
  double _effortSliderValue = 45;

  int get _totalElo => _skillElo + _effortElo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchUserData();
    _restoreGymStopwatchState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopwatchTimer?.cancel();
    if (_stopwatchRunning) {
      StopwatchService.saveGymStopwatchStart(
        DateTime.now().millisecondsSinceEpoch - (_stopwatchSeconds * 1000),
      );
    } else {
      StopwatchService.clearGymStopwatch();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_stopwatchRunning) {
        _stopwatchTimer?.cancel();
        StopwatchService.saveGymStopwatchStart(
          DateTime.now().millisecondsSinceEpoch - (_stopwatchSeconds * 1000),
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      _restoreGymStopwatchState();
    }
  }

  Future<void> _restoreGymStopwatchState() async {
    final wasRunning = await StopwatchService.isGymStopwatchRunning();
    if (wasRunning && mounted) {
      final elapsed = await StopwatchService.getGymElapsedSeconds();
      setState(() => _stopwatchSeconds = elapsed);
      _startStopwatch();
    }
  }

  void _startStopwatch() {
    if (_stopwatchRunning) return;
    setState(() => _stopwatchRunning = true);
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() => _stopwatchSeconds++);
    });
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
    StopwatchService.clearGymStopwatch();
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
          "You've been grinding for 18+ hours today. That's legendary commitment, but even superheroes need sleep.\n\nYour body builds muscle during rest, not reps. Go eat something ridiculous, watch a terrible movie, and come back tomorrow ready to destroy it again. 💪",
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fine, I\'ll rest 😤',
              style: TextStyle(color: Color(0xFFFF3B5C), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitStopwatchTime() async {
    if (_stopwatchSeconds <= 0) return;
    int mins = (_stopwatchSeconds / 60).round();
    if (mins <= 0) mins = 1;

    // Anticheat: daily effort cap
    final capStatus = await AnticheatService.checkDailyEffortCap(mins, 'gym');
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

    HapticFeedback.lightImpact();
    final newTotal = _totalElo + mins;
    final newRank = RankUtils.getRank(newTotal, RankUtils.gymRanks);
    setState(() {
      _previousTotalElo = _totalElo;
      _effortElo += mins;
      if (_previousRankName != null && newRank.name != _previousRankName) {
        _showCelebration = true;
        _currentRank = newRank;
      }
      _previousRankName = newRank.name;
    });
    _resetStopwatch();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'effortElo': FieldValue.increment(mins),
      }, SetOptions(merge: true));
    }
    // Anticheat: log daily effort + stopwatch flag
    await AnticheatService.logDailyEffort(mins, 'gym', activityFlag: 'gymStopwatchSubmit');
    _updateStreak();
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
            _skillElo = data['skillElo'] ?? 0;
            _effortElo = data['effortElo'] ?? 0;
            _gender = data['gender'] ?? 'male';
            _benchValue = data.containsKey('bench') && (data['bench'] as num) > 0
                ? (data['bench'] as num).toDouble().clamp(20.0, 250.0)
                : _benchValue;
            _squatValue = data.containsKey('squat') && (data['squat'] as num) > 0
                ? (data['squat'] as num).toDouble().clamp(30.0, 300.0)
                : _squatValue;
            _deadliftValue = data.containsKey('deadlift') && (data['deadlift'] as num) > 0
                ? (data['deadlift'] as num).toDouble().clamp(40.0, 350.0)
                : _deadliftValue;
            _bodyweightValue = data.containsKey('bodyweight') && (data['bodyweight'] as num) > 0
                ? (data['bodyweight'] as num).toDouble().clamp(35.0, 180.0)
                : _bodyweightValue;
            _streak = data['gymStreakCount'] as int? ?? 0;
            _currentRank = RankUtils.getRank(_totalElo, RankUtils.gymRanks);
            _previousRankName = _currentRank?.name;
            _baselineSet = data['gymBaselineSet'] == true;
          });
        }
      } catch (e) {
        debugPrint('Error fetching gym data: $e');
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
      final lastDate = data['gymLastActivityDate'] as String?;
      final current = data['gymStreakCount'] as int? ?? 0;
      if (lastDate == today) return;
      final newStreak = lastDate == _yesterdayStr() ? current + 1 : 1;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'gymLastActivityDate': today,
        'gymStreakCount': newStreak,
      }, SetOptions(merge: true));
      if (mounted) setState(() => _streak = newStreak);
    } catch (e) {
      debugPrint('Error updating gym streak: $e');
    }
  }

  void _calculateGymBaseline() async {
    final b = _benchValue.toInt();
    final s = _squatValue.toInt();
    final d = _deadliftValue.toInt();
    final bw = _bodyweightValue;
    if (b == 0 && s == 0 && d == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your stats first!')));
      return;
    }
    if (bw <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your bodyweight!')));
      return;
    }
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final wilks =
          LiftingUtils.calculateWilksScore((b + s + d).toDouble(), bw, _gender);
      final initialSkill = (wilks * 5).toInt();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'bench': b,
          'squat': s,
          'deadlift': d,
          'bodyweight': bw,
          'gender': _gender,
          'skillElo': initialSkill,
          'effortElo': 0,
          'gymBaselineSet': true,
        }, SetOptions(merge: true));
        if (mounted) Navigator.of(context).pop();
        setState(() {
          _previousTotalElo = _totalElo;
          _skillElo = initialSkill;
          _baselineSet = true;
        });
        _updateStreak();
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _showEditLiftsSheet() {
    double benchVal = _benchValue.clamp(20.0, 250.0);
    double squatVal = _squatValue.clamp(30.0, 300.0);
    double deadliftVal = _deadliftValue.clamp(40.0, 350.0);
    double bodyweightVal = _bodyweightValue.clamp(35.0, 180.0);
    String selectedGender = _gender;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161E),
                  border: Border(
                      top: BorderSide(
                          color: Colors.white.withAlpha(25))),
                ),
                child: SafeArea(
                  top: false,
                  child: isLoading
                      ? const SizedBox(
                          height: 120,
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: _kAccent)),
                        )
                      : SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 36,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(31),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Update Lifts',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    fontFamily: '.SF Pro Display',
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              _GymSlider(
                                label: 'Bench Press',
                                value: benchVal,
                                unit: 'kg',
                                min: 20,
                                max: 250,
                                color: _kAccent,
                                onChanged: (v) =>
                                    setSheet(() => benchVal = v),
                              ),
                              const SizedBox(height: 18),
                              _GymSlider(
                                label: 'Squat',
                                value: squatVal,
                                unit: 'kg',
                                min: 30,
                                max: 300,
                                color: _kAccent,
                                onChanged: (v) =>
                                    setSheet(() => squatVal = v),
                              ),
                              const SizedBox(height: 18),
                              _GymSlider(
                                label: 'Deadlift',
                                value: deadliftVal,
                                unit: 'kg',
                                min: 40,
                                max: 350,
                                color: _kAccent,
                                onChanged: (v) =>
                                    setSheet(() => deadliftVal = v),
                              ),
                              const SizedBox(height: 18),
                              _GymSlider(
                                label: 'Bodyweight',
                                value: bodyweightVal,
                                unit: 'kg',
                                min: 35,
                                max: 180,
                                color: const Color(0xFF5C9EFF),
                                onChanged: (v) =>
                                    setSheet(() => bodyweightVal = v),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Text(
                                    'Gender',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withAlpha(140),
                                      fontFamily: '.SF Pro Display',
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  const Spacer(),
                                  _GenderToggle(
                                    value: selectedGender,
                                    onChanged: (v) =>
                                        setSheet(() => selectedGender = v),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
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
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      onTap: () async {
                                        final b = benchVal.toInt();
                                        final s = squatVal.toInt();
                                        final d = deadliftVal.toInt();
                                        final bw = bodyweightVal;
                                        if (b == 0 && s == 0 && d == 0) {
                                          ScaffoldMessenger.of(ctx)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Please enter your stats!')));
                                          return;
                                        }
                                        HapticFeedback.mediumImpact();
                                        setSheet(() => isLoading = true);
                                        try {
                                          // Anticheat: check gym PR suspicion
                                          await AnticheatService.checkGymPR(
                                            newBench: b,
                                            newSquat: s,
                                            newDeadlift: d,
                                            bodyweight: bw,
                                            gender: selectedGender,
                                          );
                                          final wilks =
                                              LiftingUtils.calculateWilksScore(
                                            (b + s + d).toDouble(),
                                            bw,
                                            selectedGender,
                                          );
                                          final newSkill =
                                              (wilks * 5).toInt();
                                          final uid = FirebaseAuth
                                              .instance.currentUser?.uid;
                                          if (uid != null) {
                                            await FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(uid)
                                                .set({
                                              'bench': b,
                                              'squat': s,
                                              'deadlift': d,
                                              'bodyweight': bw,
                                              'gender': selectedGender,
                                              'skillElo': newSkill,
                                            }, SetOptions(merge: true));
                                            // Anticheat: store new Wilks baseline
                                            await AnticheatService.storeGymBaseline(
                                              bench: b,
                                              squat: s,
                                              deadlift: d,
                                              bodyweight: bw,
                                              gender: selectedGender,
                                            );
                                            if (mounted) {
                                              Navigator.of(ctx).pop();
                                              setState(() {
                                                _previousTotalElo =
                                                    _totalElo;
                                                _skillElo = newSkill;
                                                _gender = selectedGender;
                                                _benchValue = b.toDouble();
                                                _squatValue = s.toDouble();
                                                _deadliftValue =
                                                    d.toDouble();
                                                _bodyweightValue = bw;
                                              });
                                            }
                                          }
                                        } catch (e) {
                                          setSheet(
                                              () => isLoading = false);
                                          ScaffoldMessenger.of(ctx)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      'Failed: $e')));
                                        }
                                      },
                                      child: const Center(
                                        child: Text(
                                          'Save',
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
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _addGymEffort() async {
    final mins = _effortSliderValue.toInt();
    if (mins <= 0) return false;

    // Anticheat: daily effort cap
    final capStatus = await AnticheatService.checkDailyEffortCap(mins, 'gym');
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
    final newRank = RankUtils.getRank(newTotal, RankUtils.gymRanks);
    setState(() {
      _previousTotalElo = _totalElo;
      _effortElo += mins;
      _effortSliderValue = 45;
      if (_previousRankName != null && newRank.name != _previousRankName) {
        _showCelebration = true;
        _currentRank = newRank;
      }
      _previousRankName = newRank.name;
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'effortElo': FieldValue.increment(mins)}, SetOptions(merge: true));
    }
    // Anticheat: log daily effort
    await AnticheatService.logDailyEffort(mins, 'gym');
    _updateStreak();
    return true;
  }

  void _showGymEffortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GymEffortSheet(
        sliderValue: _effortSliderValue,
        onSliderChanged: (v) => setState(() => _effortSliderValue = v),
        onAddEffort: _addGymEffort,
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
              onPressed: _showEditLiftsSheet,
            ),
        ],
      ),
      body: Stack(
        children: [
          // Wallpaper
          const SizedBox.expand(child: _GymWallpaper()),
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
                        ? _GymDashboardView(
                            key: const ValueKey('gym-dash'),
                            totalElo: _totalElo,
                            previousTotalElo: _previousTotalElo,
                            skillElo: _skillElo,
                            effortElo: _effortElo,
                            bench: _benchValue.toInt(),
                            squat: _squatValue.toInt(),
                            deadlift: _deadliftValue.toInt(),
                            stopwatchSeconds: _stopwatchSeconds,
                            stopwatchRunning: _stopwatchRunning,
                            onStart: _startStopwatch,
                            onStop: _stopStopwatch,
                            onReset: _resetStopwatch,
                            onSubmit: _submitStopwatchTime,
                            onLogWorkout: _showGymEffortSheet,
                            rank: RankUtils.getRank(
                                _totalElo, RankUtils.gymRanks),
                            streak: _streak,
                          )
                        : _GymOnboardingCard(
                            key: const ValueKey('gym-onboard'),
                            benchValue: _benchValue,
                            squatValue: _squatValue,
                            deadliftValue: _deadliftValue,
                            bodyweightValue: _bodyweightValue,
                            gender: _gender,
                            onBenchChanged: (v) =>
                                setState(() => _benchValue = v),
                            onSquatChanged: (v) =>
                                setState(() => _squatValue = v),
                            onDeadliftChanged: (v) =>
                                setState(() => _deadliftValue = v),
                            onBodyweightChanged: (v) =>
                                setState(() => _bodyweightValue = v),
                            onGenderChanged: (v) =>
                                setState(() => _gender = v),
                            onCalculate: _calculateGymBaseline,
                          ),
                  ),
                if (_showCelebration && _currentRank != null)
                  RankUpCelebration(
                    newRank: _currentRank!,
                    onDismiss: () =>
                        setState(() => _showCelebration = false),
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

class _GymWallpaper extends StatelessWidget {
  const _GymWallpaper();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
        painter: _WallpaperPainter(
            bg0: _kBg0, bg1: _kBg1, accent: _kAccent));
  }
}

class _WallpaperPainter extends CustomPainter {
  final Color bg0, bg1, accent;
  _WallpaperPainter(
      {required this.bg0, required this.bg1, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bg0, bg1, bg0],
            stops: const [0, 0.6, 1],
          ).createShader(rect));
    canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.srcOver
          ..shader = RadialGradient(
            center: const Alignment(-0.6, -1.1),
            radius: 1.0,
            colors: [accent.withAlpha(89), Colors.transparent],
          ).createShader(rect));
    canvas.drawRect(
        rect,
        Paint()
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

class _GymDashboardView extends StatelessWidget {
  final int totalElo;
  final int previousTotalElo;
  final int skillElo;
  final int effortElo;
  final int bench;
  final int squat;
  final int deadlift;
  final int stopwatchSeconds;
  final bool stopwatchRunning;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final Future<void> Function() onSubmit;
  final VoidCallback onLogWorkout;
  final Rank rank;
  final int streak;

  const _GymDashboardView({
    super.key,
    required this.totalElo,
    required this.previousTotalElo,
    required this.skillElo,
    required this.effortElo,
    required this.bench,
    required this.squat,
    required this.deadlift,
    required this.stopwatchSeconds,
    required this.stopwatchRunning,
    required this.onStart,
    required this.onStop,
    required this.onReset,
    required this.onSubmit,
    required this.onLogWorkout,
    required this.rank,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final progress = RankUtils.rankProgress(totalElo, RankUtils.gymRanks);
    final next = RankUtils.nextRank(totalElo, RankUtils.gymRanks);
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
            rankImagePath: RankUtils.getGymRankImage(rank),
            accent: _kAccent,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _GlassCard(
                  child: _StatCardContent(
                    label: 'STRENGTH',
                    value: RankUtils.formatElo(skillElo),
                    icon: Icons.bolt_rounded,
                    color: const Color(0xFFFF8C6B),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GlassCard(
                  child: _StatCardContent(
                    label: 'VOLUME',
                    value: RankUtils.formatElo(effortElo),
                    icon: Icons.local_fire_department_rounded,
                    color: const Color(0xFFFF6B85),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LiftsRow(
            bench: bench,
            squat: squat,
            deadlift: deadlift,
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
          _GradientButton(
            label: 'Log Workout',
            icon: Icons.fitness_center_rounded,
            onTap: onLogWorkout,
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
              Positioned(
                top: 0,
                left: 0,
                right: 0,
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
                    rankIndex: RankUtils.gymRanks.indexOf(rank),
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
                                  '${RankUtils.formatElo(RankUtils.eloToNext(totalElo, RankUtils.gymRanks))} to go',
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
        painter: getRankBadgePainter('gym', rankIndex, accent),
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
// Lifts Row — bento style 3-chip card
// ─────────────────────────────────────────────

class _LiftsRow extends StatelessWidget {
  final int bench;
  final int squat;
  final int deadlift;

  const _LiftsRow({
    required this.bench,
    required this.squat,
    required this.deadlift,
  });

  @override
  Widget build(BuildContext context) {
    final total = bench + squat + deadlift;
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.fitness_center_rounded,
                        size: 12, color: Colors.white.withAlpha(110)),
                    const SizedBox(width: 5),
                    Text(
                      'BIG THREE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withAlpha(130),
                        letterSpacing: 0.8,
                        fontFamily: '.SF Pro Display',
                      ),
                    ),
                  ],
                ),
                Text(
                  'Total: $total kg',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _kAccent.withAlpha(230),
                    fontFamily: '.SF Pro Display',
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _LiftChip(label: 'Bench', value: bench, icon: Icons.view_week_rounded)),
                Container(width: 1, height: 32, color: Colors.white.withAlpha(20)),
                Expanded(child: _LiftChip(label: 'Squat', value: squat, icon: Icons.height_rounded)),
                Container(width: 1, height: 32, color: Colors.white.withAlpha(20)),
                Expanded(child: _LiftChip(label: 'Deadlift', value: deadlift, icon: Icons.arrow_upward_rounded)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LiftChip extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  const _LiftChip({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white.withAlpha(130)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFamily: '.SF Pro Display',
                height: 1,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              'kg',
              style: TextStyle(
                fontSize: 9,
                color: Colors.white.withAlpha(102),
                fontFamily: '.SF Pro Display',
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.white.withAlpha(89),
            letterSpacing: 0.4,
            fontFamily: '.SF Pro Display',
          ),
        ),
      ],
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
            icon: isRunning
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
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
// Gym Onboarding Card
// ─────────────────────────────────────────────

class _GymOnboardingCard extends StatefulWidget {
  final double benchValue;
  final double squatValue;
  final double deadliftValue;
  final double bodyweightValue;
  final String gender;
  final ValueChanged<double> onBenchChanged;
  final ValueChanged<double> onSquatChanged;
  final ValueChanged<double> onDeadliftChanged;
  final ValueChanged<double> onBodyweightChanged;
  final ValueChanged<String> onGenderChanged;
  final VoidCallback onCalculate;

  const _GymOnboardingCard({
    super.key,
    required this.benchValue,
    required this.squatValue,
    required this.deadliftValue,
    required this.bodyweightValue,
    required this.gender,
    required this.onBenchChanged,
    required this.onSquatChanged,
    required this.onDeadliftChanged,
    required this.onBodyweightChanged,
    required this.onGenderChanged,
    required this.onCalculate,
  });

  @override
  State<_GymOnboardingCard> createState() => _GymOnboardingCardState();
}

class _GymOnboardingCardState extends State<_GymOnboardingCard> {
  @override
  Widget build(BuildContext context) {
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
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _kAccent.withAlpha(31),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _kAccent.withAlpha(51)),
                      ),
                      child: const Icon(Icons.fitness_center_rounded,
                          color: _kAccent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Gym Setup',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontFamily: '.SF Pro Display',
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Set your lifting baseline',
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
                const SizedBox(height: 28),
                _GymSlider(
                  label: 'Bench Press',
                  value: widget.benchValue,
                  unit: 'kg',
                  min: 20,
                  max: 250,
                  color: _kAccent,
                  onChanged: widget.onBenchChanged,
                ),
                const SizedBox(height: 18),
                _GymSlider(
                  label: 'Squat',
                  value: widget.squatValue,
                  unit: 'kg',
                  min: 30,
                  max: 300,
                  color: _kAccent,
                  onChanged: widget.onSquatChanged,
                ),
                const SizedBox(height: 18),
                _GymSlider(
                  label: 'Deadlift',
                  value: widget.deadliftValue,
                  unit: 'kg',
                  min: 40,
                  max: 350,
                  color: _kAccent,
                  onChanged: widget.onDeadliftChanged,
                ),
                const SizedBox(height: 18),
                _GymSlider(
                  label: 'Bodyweight',
                  value: widget.bodyweightValue,
                  unit: 'kg',
                  min: 35,
                  max: 180,
                  color: const Color(0xFF5C9EFF),
                  onChanged: widget.onBodyweightChanged,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      'Gender',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withAlpha(140),
                        fontFamily: '.SF Pro Display',
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    _GenderToggle(
                      value: widget.gender,
                      onChanged: widget.onGenderChanged,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
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
                          widget.onCalculate();
                        },
                        child: const Center(
                          child: Text(
                            'Start My Journey',
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
}

// ─────────────────────────────────────────────
// Gym Slider
// ─────────────────────────────────────────────

class _GymSlider extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final double min;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;

  const _GymSlider({
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withAlpha(191),
                fontFamily: '.SF Pro Display',
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withAlpha(36),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withAlpha(51), width: 0.5),
              ),
              child: Text(
                '${value.toInt()} $unit',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFamily: '.SF Pro Display',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            inactiveTrackColor: Colors.white.withAlpha(25),
            trackHeight: 4,
            thumbColor: color,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 11),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) ~/ 5).clamp(1, 100),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Gender Toggle
// ─────────────────────────────────────────────

class _GenderToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _GenderToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ['male', 'female'].map((g) {
        final sel = value == g;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(g);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: EdgeInsets.only(left: g == 'male' ? 0 : 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: sel
                  ? const LinearGradient(colors: [_kAccent, _kAccentDim])
                  : null,
              color: sel ? null : Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: sel
                    ? _kAccent.withAlpha(200)
                    : Colors.white.withAlpha(25),
                width: 0.5,
              ),
            ),
            child: Text(
              g[0].toUpperCase() + g.substring(1),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sel
                    ? Colors.white
                    : Colors.white.withAlpha(102),
                fontFamily: '.SF Pro Display',
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
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
              // Top shine
              Positioned(
                top: 0,
                left: 0,
                right: 0,
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
        padding:
            const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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

// ─────────────────────────────────────────────
// Gradient Button
// ─────────────────────────────────────────────

class _GradientButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color accent, accentDim;
  const _GradientButton({
    required this.label, required this.icon,
    required this.onTap, required this.accent, required this.accentDim,
  });

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

// ─────────────────────────────────────────────
// Gym Effort Sheet
// ─────────────────────────────────────────────

class _GymEffortSheet extends StatefulWidget {
  final double sliderValue;
  final ValueChanged<double> onSliderChanged;
  final Future<bool> Function() onAddEffort;

  const _GymEffortSheet({
    required this.sliderValue,
    required this.onSliderChanged,
    required this.onAddEffort,
  });

  @override
  State<_GymEffortSheet> createState() => _GymEffortSheetState();
}

class _GymEffortSheetState extends State<_GymEffortSheet> {
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
            color: const Color(0xFF1A0A0E),
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
                      const Text('Log Workout', style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
                        fontFamily: '.SF Pro Display', letterSpacing: -0.4)),
                      Text('How long did you train?', style: TextStyle(
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
                    value: _localValue, min: 15, max: 180, divisions: 33,
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
                    Text('15m', style: TextStyle(fontSize: 11,
                        color: Colors.white.withAlpha(64), fontFamily: '.SF Pro Display')),
                    Text('3h', style: TextStyle(fontSize: 11,
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
                        child: Center(child: Text(_saving ? 'Saved ✓' : 'Log Workout',
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

