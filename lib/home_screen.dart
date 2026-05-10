import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'gym_dashboard.dart';
import 'academic_dashboard.dart';
import 'running_dashboard.dart';
import 'luminary_dashboard.dart';
import 'groups_screen.dart';
import 'leaderboard_screen.dart';
import 'notifications_screen.dart';
import 'challenges_screen.dart';
import 'social_service.dart';
import 'profile_screen.dart';
import 'rank_utils.dart';

const _kBg0 = Color(0xFF0A0A14);
const _kBg1 = Color(0xFF141428);
const _kAccent = Color(0xFF6E5CFF);

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg0,
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _HomePainter())),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 36),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFB8AEFF)],
                    stops: [0.3, 1.0],
                  ).createShader(bounds),
                  child: const Text(
                    'Endeavour',
                    style: TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.w200,
                      color: Colors.white,
                      letterSpacing: -1.8,
                      fontFamily: '.SF Pro Display',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'choose your path',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    color: Colors.white.withValues(alpha: 0.40),
                    letterSpacing: 1.2,
                    fontFamily: '.SF Pro Display',
                  ),
                ),
                Expanded(
                  child: Center(
                    child: StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseAuth.instance.currentUser?.uid == null
                          ? null
                          : FirebaseFirestore.instance
                              .collection('users')
                              .doc(FirebaseAuth.instance.currentUser!.uid)
                              .snapshots(),
                      builder: (context, snap) {
                        final data =
                            (snap.data?.data() as Map<String, dynamic>?) ?? const {};
                        int asInt(dynamic v) =>
                            v is int ? v : (v is num ? v.toInt() : 0);
                        final gymElo = asInt(data['skillElo']) + asInt(data['effortElo']);
                        final acadElo = asInt(data['academicSkillElo']) +
                            asInt(data['academicEffortElo']);
                        final runElo = asInt(data['runningSkillElo']) +
                            asInt(data['runningEffortElo']);
                        final lumElo = asInt(data['luminarySkillElo']) +
                            asInt(data['luminaryEffortElo']);
                        final gymStreak = asInt(data['gymStreakCount']);
                        final acadStreak = asInt(data['academicStreakCount']);
                        final runStreak = asInt(data['runningStreakCount']);
                        final lumStreak = asInt(data['luminaryStreakCount']);

                        return Wrap(
                          spacing: 24,
                          runSpacing: 28,
                          alignment: WrapAlignment.center,
                          children: [
                            PathCircle(
                              title: 'Gym',
                              icon: Icons.fitness_center_rounded,
                              color: const Color(0xFFFF3B5C),
                              destination: const GymDashboard(),
                              elo: gymElo,
                              streak: gymStreak,
                              ranks: RankUtils.gymRanks,
                            ),
                            PathCircle(
                              title: 'Academics',
                              icon: Icons.auto_stories_rounded,
                              color: const Color(0xFF6E5CFF),
                              destination: const AcademicDashboard(),
                              elo: acadElo,
                              streak: acadStreak,
                              ranks: RankUtils.academicRanks,
                            ),
                            PathCircle(
                              title: 'Running',
                              icon: Icons.directions_run_rounded,
                              color: const Color(0xFF30D158),
                              destination: const RunningDashboard(),
                              elo: runElo,
                              streak: runStreak,
                              ranks: RankUtils.runningRanks,
                            ),
                            PathCircle(
                              title: 'Luminary',
                              icon: Icons.auto_awesome_rounded,
                              color: const Color(0xFFFFD60A),
                              destination: const LuminaryDashboard(),
                              elo: lumElo,
                              streak: lumStreak,
                              ranks: RankUtils.luminaRanks,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 112),
              ],
            ),
          ),
          Positioned(
            bottom: 28,
            left: 20,
            right: 20,
            child: const _GlassBottomBar(),
          ),
        ],
      ),
    );
  }
}

// ─── Wallpaper ────────────────────────────────────────────────────────────────

class _HomePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_kBg0, _kBg1, _kBg0],
        stops: [0.0, 0.6, 1.0],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(-0.5, -1.1),
        radius: 1.0,
        colors: [_kAccent.withValues(alpha: 0.25), Colors.transparent],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(1.1, 0.8),
        radius: 0.8,
        colors: [_kAccent.withValues(alpha: 0.14), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Glass Bottom Bar ─────────────────────────────────────────────────────────

class _GlassBottomBar extends StatelessWidget {
  const _GlassBottomBar();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF12121A).withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.09),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.50),
                blurRadius: 36,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: _kAccent.withValues(alpha: 0.07),
                blurRadius: 28,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BarItem(
                onTap: () {
                  if (uid != null) {
                    HapticFeedback.selectionClick();
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ProfileScreen(targetUid: uid)));
                  }
                },
                child: _ProfileAvatar(uid: uid),
              ),
              _BarItem(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GroupsScreen()));
                },
                child: Icon(Icons.group_rounded, color: Colors.teal.shade300, size: 24),
              ),
              _BarItem(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ChallengesScreen()));
                },
                child: const _ChallengesIcon(),
              ),
              _BarItem(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
                },
                child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFB830), size: 24),
              ),
              StreamBuilder<QuerySnapshot>(
                stream: SocialService().getNotificationsStream(),
                builder: (context, snapshot) {
                  final count = snapshot.data?.docs.length ?? 0;
                  return _BarItem(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(Icons.notifications_rounded, color: Colors.pink.shade300, size: 24),
                        if (count > 0)
                          Positioned(
                            top: -4, right: -6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF12121A),
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                count > 99 ? '99+' : '$count',
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _BarItem({required this.child, required this.onTap});

  @override
  State<_BarItem> createState() => _BarItemState();
}

class _BarItemState extends State<_BarItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.86 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: widget.child,
        ),
      ),
    );
  }
}

class _ChallengesIcon extends StatelessWidget {
  const _ChallengesIcon();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Icon(Icons.bolt_rounded, color: Color(0xFFFFD60A), size: 24);
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = (snap.data?.data() as Map<String, dynamic>?) ?? {};
        final savedDate = data['challengeDate'] as String? ?? '';
        final completedIds = List<String>.from(data['completedChallengeIds'] ?? []);
        final today = _todayKey();
        final doneToday = savedDate == today ? completedIds.length : 0;
        // Total = 3 challenges per active path + 1 cross-path bonus if 2+ paths active
        int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
        final gymElo = asInt(data['skillElo']) + asInt(data['effortElo']);
        final acadElo = asInt(data['academicSkillElo']) + asInt(data['academicEffortElo']);
        final runElo = asInt(data['runningSkillElo']) + asInt(data['runningEffortElo']);
        final lumElo = asInt(data['luminarySkillElo']) + asInt(data['luminaryEffortElo']);
        final activePaths = [gymElo, acadElo, runElo, lumElo].where((e) => e > 0).length;
        final total = activePaths * 3 + (activePaths >= 2 ? 1 : 0);
        final remaining = total > 0 ? (total - doneToday).clamp(0, total) : 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFFFFD60A), size: 24),
            if (remaining > 0)
              Positioned(
                top: -4, right: -6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD60A),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF12121A),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    '$remaining',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? uid;
  const _ProfileAvatar({this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid == null) return _shell(const Icon(Icons.person_rounded, color: Colors.white54, size: 18));
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        String? url;
        if (snapshot.hasData && snapshot.data!.exists) {
          url = (snapshot.data!.data() as Map<String, dynamic>?)?['photoUrl'] as String?;
        }
        return _shell(
          url != null
              ? Image.network(url, fit: BoxFit.cover,
                  errorBuilder: (_, e, s) => const Icon(Icons.person_rounded, color: Colors.white54, size: 18))
              : const Icon(Icons.person_rounded, color: Colors.white54, size: 18),
        );
      },
    );
  }

  Widget _shell(Widget child) => Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
        ),
        child: ClipOval(child: child),
      );
}

// ─── Path Circle ──────────────────────────────────────────────────────────────

class PathCircle extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget destination;
  final int elo;
  final int streak;
  final List<Rank> ranks;

  const PathCircle({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.destination,
    this.elo = 0,
    this.streak = 0,
    this.ranks = const [],
  });

  @override
  State<PathCircle> createState() => _PathCircleState();
}

class _PathCircleState extends State<PathCircle> {
  bool _hovered = false;
  bool _pressed = false;

  double get _scale => _pressed ? 0.93 : (_hovered ? 1.08 : 1.0);

  @override
  Widget build(BuildContext context) {
    final progress = widget.ranks.isEmpty
        ? 0.0
        : RankUtils.rankProgress(widget.elo, widget.ranks);
    final hasStreak = widget.streak > 0;
    final hasElo = widget.elo > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.push(context, MaterialPageRoute(builder: (_) => widget.destination));
            },
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              scale: _scale,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutBack,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: _hovered ? 0.35 : 0.0),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 120, height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          color: Colors.white.withValues(alpha: _hovered ? 0.12 : 0.06),
                          border: Border.all(
                            color: widget.color.withValues(alpha: _hovered ? 0.65 : 0.28),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(widget.icon, size: 48, color: widget.color),
                      ),
                    ),
                  ),
                  // Progress ring around the tile
                  if (hasElo && widget.ranks.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _PathProgressPainter(
                            progress: progress,
                            color: widget.color,
                          ),
                        ),
                      ),
                    ),
                  // Streak badge (top-right)
                  if (hasStreak)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9F0A),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: const Color(0xFF0A0A14),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF9F0A).withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_fire_department_rounded,
                                size: 10, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              '${widget.streak}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontFamily: '.SF Pro Display',
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // ELO badge (bottom)
                  if (hasElo)
                    Positioned(
                      bottom: -10,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: widget.color.withValues(alpha: 0.55),
                                width: 0.7,
                              ),
                            ),
                            child: Text(
                              RankUtils.formatElo(widget.elo),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: widget.color,
                                fontFamily: '.SF Pro Display',
                                letterSpacing: 0.1,
                                height: 1,
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
        const SizedBox(height: 14),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: _hovered ? widget.color : Colors.white.withValues(alpha: 0.70),
            letterSpacing: 0.1,
            fontFamily: '.SF Pro Display',
          ),
          child: Text(widget.title),
        ),
      ],
    );
  }
}

class _PathProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  _PathProgressPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3),
      const Radius.circular(29),
    );
    // Compute perimeter arc path
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final total = metrics.fold<double>(0, (acc, m) => acc + m.length);
    final target = total * progress.clamp(0.0, 1.0);

    final ringPath = Path();
    double traversed = 0;
    for (final m in metrics) {
      if (traversed + m.length <= target) {
        ringPath.addPath(m.extractPath(0, m.length), Offset.zero);
        traversed += m.length;
      } else {
        final remain = target - traversed;
        if (remain > 0) {
          ringPath.addPath(m.extractPath(0, remain), Offset.zero);
        }
        break;
      }
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.1),
          color,
          color.withValues(alpha: 0.9),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(ringPath, paint);
  }

  @override
  bool shouldRepaint(covariant _PathProgressPainter old) =>
      old.progress != progress || old.color != color;
}
