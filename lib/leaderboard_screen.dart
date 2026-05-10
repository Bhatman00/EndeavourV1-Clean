import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_screen.dart';

class LeaderboardUser {
  final String uid;
  final String username;
  final String? photoUrl;
  final int totalElo;
  final int gymElo;
  final int academicElo;
  final int artElo;
  final int runningElo;
  final int luminaryElo;
  final String topEndeavour;
  final String region;

  LeaderboardUser({
    required this.uid,
    required this.username,
    this.photoUrl,
    required this.totalElo,
    required this.gymElo,
    required this.academicElo,
    required this.artElo,
    required this.runningElo,
    required this.luminaryElo,
    required this.topEndeavour,
    required this.region,
  });
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _selectedRegion = 'All';
  final List<String> _regions = [
    'All',
    'OCE',
    'Asia',
    'Europe',
    'NA',
    'SA',
    'Unknown',
  ];

  String _selectedSort = 'Total Elo';
  final List<String> _sortOptions = [
    'Total Elo',
    'Gym Elo',
    'Academic Elo',
    'Running Elo',
    'Luminary Elo',
  ];

  late Future<List<LeaderboardUser>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _usersFuture = _loadUsers();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    return 0;
  }

  String _formatElo(int elo) {
    if (elo < 1000) return elo.toString();
    if (elo < 1000000) {
      return '${(elo / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}K';
    }
    if (elo < 1000000000) {
      return '${(elo / 1000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}M';
    }
    return '${(elo / 1000000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}B';
  }

  String _topEndeavour(Map<String, dynamic> data) {
    final int gym = _toInt(data['skillElo']) + _toInt(data['effortElo']);
    final int academic =
        _toInt(data['academicSkillElo']) + _toInt(data['academicEffortElo']);
    final int running =
        _toInt(data['runningSkillElo']) + _toInt(data['runningEffortElo']);
    final int luminary =
        _toInt(data['luminarySkillElo']) + _toInt(data['luminaryEffortElo']);

    final Map<String, int> scores = {
      'Gym': gym,
      'Academic': academic,
      'Running': running,
      'Luminary': luminary,
    };
    final total = scores.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return 'Unknown';
    final top = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return top.key;
  }

  Future<List<LeaderboardUser>> _loadUsers() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final users = snapshot.docs
        .where((doc) => doc.data()['isPrivate'] != true)
        // Anticheat: filter shadowbanned users (but always show current user)
        .where((doc) => doc.id == currentUid || doc.data()['isShadowbanned'] != true)
        .map((doc) {
          final data = doc.data();
          final uid = doc.id;
          final username = (data['username'] as String?)?.trim();
          final region = (data['region'] as String?)?.trim() ?? 'Unknown';
          final gymElo = _toInt(data['skillElo']) + _toInt(data['effortElo']);
          final academicElo =
              _toInt(data['academicSkillElo']) +
              _toInt(data['academicEffortElo']);
          final artElo =
              _toInt(data['artSkillElo']) + _toInt(data['artEffortElo']);
          final runningElo = _toInt(data['runningSkillElo']) +
              _toInt(data['runningEffortElo']);
          final luminaryElo = _toInt(data['luminarySkillElo']) +
              _toInt(data['luminaryEffortElo']);
          final totalElo =
              gymElo + academicElo + runningElo + luminaryElo + artElo;

          return LeaderboardUser(
            uid: uid,
            username: username != null && username.isNotEmpty
                ? username
                : 'Unknown',
            photoUrl: data['photoUrl'],
            totalElo: totalElo,
            gymElo: gymElo,
            academicElo: academicElo,
            artElo: artElo,
            runningElo: runningElo,
            luminaryElo: luminaryElo,
            topEndeavour: _topEndeavour(data),
            region: region.isNotEmpty ? region : 'Unknown',
          );
        })
        .toList();

    return users;
  }

  List<LeaderboardUser> _filterByRegion(List<LeaderboardUser> users) {
    if (_selectedRegion == 'All') return users;
    return users.where((user) => user.region == _selectedRegion).toList();
  }

  IconData _getSkillIcon(String skill) {
    switch (skill.toLowerCase()) {
      case 'gym':
        return Icons.fitness_center_rounded;
      case 'academic':
        return Icons.auto_stories_rounded;
      case 'running':
        return Icons.directions_run_rounded;
      case 'luminary':
        return Icons.auto_awesome_rounded;
      case 'art':
        return Icons.palette_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A14),
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _LbPainter())),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                width: 40, height: 40,
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
                        const Text(
                          'Leaderboards',
                          style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white,
                            letterSpacing: -0.5, fontFamily: '.SF Pro Display',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Glass tab bar
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                    ),
                    child: TabBar(
                      indicator: BoxDecoration(
                        color: const Color(0xFF6E5CFF).withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0xFF6E5CFF).withValues(alpha: 0.55), width: 0.7),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white38,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelStyle: const TextStyle(fontFamily: '.SF Pro Display', fontWeight: FontWeight.w600, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(fontFamily: '.SF Pro Display', fontWeight: FontWeight.w400, fontSize: 13),
                      tabs: const [Tab(text: 'Global'), Tab(text: 'Regional')],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: FutureBuilder<List<LeaderboardUser>>(
                      future: _usersFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 1.5));
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Failed to load leaderboard: ${snapshot.error}',
                                style: const TextStyle(color: Colors.redAccent)),
                          );
                        }
                        final users = snapshot.data ?? [];
                        final sortedUsers = [...users];
                        sortedUsers.sort((a, b) {
                          if (_selectedSort == 'Gym Elo') return b.gymElo.compareTo(a.gymElo);
                          if (_selectedSort == 'Academic Elo') return b.academicElo.compareTo(a.academicElo);
                          if (_selectedSort == 'Running Elo') return b.runningElo.compareTo(a.runningElo);
                          if (_selectedSort == 'Luminary Elo') return b.luminaryElo.compareTo(a.luminaryElo);
                          return b.totalElo.compareTo(a.totalElo);
                        });
                        final regionalUsers = _filterByRegion(sortedUsers);
                        return TabBarView(
                          children: [
                            _buildTabContent(sortedUsers, isRegional: false),
                            _buildTabContent(regionalUsers, isRegional: true),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(
    List<LeaderboardUser> allUsersList, {
    required bool isRegional,
  }) {
    List<LeaderboardUser> displayUsers = allUsersList.take(500).toList();

    String? myUid = FirebaseAuth.instance.currentUser?.uid;
    int myRank = allUsersList.indexWhere((u) => u.uid == myUid) + 1;
    LeaderboardUser? me;
    if (myRank > 0) me = allUsersList[myRank - 1];

    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 10),
            isRegional ? _buildFilters() : _buildSortSelector(),
            const SizedBox(height: 10),
            Expanded(
              child: _buildLeaderboardList(
                displayUsers,
                bottomPadding: me != null ? 120 : 20,
              ),
            ),
          ],
        ),
        if (me != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0A0A14).withValues(alpha: 0.0),
                    const Color(0xFF0A0A14).withValues(alpha: 0.95),
                    const Color(0xFF0A0A14),
                  ],
                ),
              ),
              child: LeaderboardCard(
                user: me,
                rank: myRank,
                selectedSort: _selectedSort,
                isMine: true,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSortSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSort,
                isExpanded: true,
                dropdownColor: const Color(0xFF141428),
                icon: Icon(Icons.sort, color: Colors.white54, size: 18),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: '.SF Pro Display',
                ),
                items: _sortOptions.map((String sortStr) {
                  return DropdownMenuItem<String>(
                    value: sortStr,
                    child: Text(sortStr),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedSort = newValue);
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRegion,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF141428),
                      icon: const Icon(Icons.public, color: Colors.white54),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      items: _regions.map((String region) {
                        return DropdownMenuItem<String>(
                          value: region,
                          child: Text(
                            region == 'All' ? 'All Regions' : region,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() => _selectedRegion = newValue);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedSort,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF141428),
                      icon: const Icon(Icons.sort, color: Colors.white54),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      items: _sortOptions.map((String sortStr) {
                        return DropdownMenuItem<String>(
                          value: sortStr,
                          child: Text(sortStr, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() => _selectedSort = newValue);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardList(
    List<LeaderboardUser> users, {
    double bottomPadding = 20,
  }) {
    if (users.isEmpty) {
      return const Center(
        child: Text('No users found.', style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(12, 6, 12, bottomPadding),
      itemCount: users.length,
      itemBuilder: (context, index) => LeaderboardCard(
        user: users[index],
        rank: index + 1,
        selectedSort: _selectedSort,
      ),
    );
  }
}

class _LbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF0A0A14), Color(0xFF141428), Color(0xFF0A0A14)],
        stops: [0.0, 0.6, 1.0],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(0.8, -0.9), radius: 0.85,
        colors: [const Color(0xFFFFB830).withValues(alpha: 0.08), Colors.transparent],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(-0.8, 0.7), radius: 0.75,
        colors: [const Color(0xFF6E5CFF).withValues(alpha: 0.10), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class LeaderboardCard extends StatelessWidget {
  final LeaderboardUser user;
  final int rank;
  final String selectedSort;
  final bool isMine;

  const LeaderboardCard({
    super.key,
    required this.user,
    required this.rank,
    required this.selectedSort,
    this.isMine = false,
  });

  String _formatElo(int elo) {
    if (elo < 1000) return elo.toString();
    if (elo < 1000000) {
      return '${(elo / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}K';
    }
    if (elo < 1000000000) {
      return '${(elo / 1000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}M';
    }
    return '${(elo / 1000000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}B';
  }

  IconData _getSkillIcon(String skill) {
    switch (skill.toLowerCase()) {
      case 'gym':
        return Icons.fitness_center_rounded;
      case 'academic':
        return Icons.auto_stories_rounded;
      case 'running':
        return Icons.directions_run_rounded;
      case 'luminary':
        return Icons.auto_awesome_rounded;
      case 'art':
        return Icons.palette_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileScreen(targetUid: user.uid),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isMine
                      ? Colors.amber.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: rank == 1 ? Colors.amber : Colors.white54,
                        fontFamily: '.SF Pro Display',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                      image: user.photoUrl != null
                          ? DecorationImage(
                              image: NetworkImage(user.photoUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: user.photoUrl == null
                        ? const Icon(
                            Icons.person,
                            size: 20,
                            color: Colors.white24,
                          )
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontFamily: '.SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Icon(
                              _getSkillIcon(user.topEndeavour),
                              size: 10,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                user.topEndeavour,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white54,
                                  letterSpacing: -0.2,
                                  fontFamily: '.SF Pro Display',
                                  height: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                user.region,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 9,
                                  fontFamily: '.SF Pro Display',
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Text(
                          _formatElo(
                            selectedSort == 'Gym Elo'
                                ? user.gymElo
                                : selectedSort == 'Academic Elo'
                                ? user.academicElo
                                : selectedSort == 'Running Elo'
                                ? user.runningElo
                                : selectedSort == 'Luminary Elo'
                                ? user.luminaryElo
                                : user.totalElo,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: '.SF Pro Display',
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
      ),
    );
  }
}
