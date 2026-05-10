import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'social_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class GroupLeaderboardScreen extends StatefulWidget {
  final String groupName;
  final String groupCode;
  final List<dynamic> memberIds;
  final String leaderId;
  final String groupId;
  final bool isPrivate;

  const GroupLeaderboardScreen({
    super.key,
    required this.groupName,
    required this.groupCode,
    required this.memberIds,
    required this.leaderId,
    required this.groupId,
    this.isPrivate = false,
  });

  @override
  State<GroupLeaderboardScreen> createState() => _GroupLeaderboardScreenState();
}

class _GroupLeaderboardScreenState extends State<GroupLeaderboardScreen> {
  final SocialService _socialService = SocialService();
  String? _uid;
  late List<String> _currentMemberIds;
  String _selectedSort = 'Total Elo';
  final List<String> _sortOptions = [
    'Total Elo',
    'Gym Elo',
    'Academic Elo',
    'Art Elo',
  ];

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _currentMemberIds = List<String>.from(widget.memberIds);
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    return 0;
  }

  int _userElo(Map<String, dynamic>? data) {
    if (data == null) return 0;
    return _toInt(data['skillElo']) +
        _toInt(data['effortElo']) +
        _toInt(data['academicSkillElo']) +
        _toInt(data['academicEffortElo']) +
        _toInt(data['artSkillElo']) +
        _toInt(data['artEffortElo']);
  }

  String _topEndeavour(Map<String, dynamic>? data) {
    if (data == null) return 'Unknown';

    final int gym = _toInt(data['skillElo']) + _toInt(data['effortElo']);
    final int academic =
        _toInt(data['academicSkillElo']) + _toInt(data['academicEffortElo']);
    final int art = _toInt(data['artSkillElo']) + _toInt(data['artEffortElo']);

    if (gym == 0 && academic == 0 && art == 0) return 'Unknown';
    if (gym >= academic && gym >= art) return 'Gym';
    if (academic >= gym && academic >= art) return 'Academic';
    return 'Art';
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

  Future<List<Map<String, dynamic>>> _loadLeaderboardMembers() async {
    final ids = _currentMemberIds;
    final futures = ids.map((id) async {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .get();
      if (!doc.exists) {
        return <String, dynamic>{
          'username': 'Unknown',
          'elo': 0,
          'gymElo': 0,
          'academicElo': 0,
          'artElo': 0,
          'topEndeavour': 'Unknown',
        };
      }
      final data = doc.data() as Map<String, dynamic>;
      final username = (data['username'] as String?)?.trim();
      return {
        'uid': id,
        'username': username != null && username.isNotEmpty
            ? username
            : 'Unknown',
        'photoUrl': data['photoUrl'],
        'elo': _userElo(data),
        'gymElo': _toInt(data['skillElo']) + _toInt(data['effortElo']),
        'academicElo':
            _toInt(data['academicSkillElo']) +
            _toInt(data['academicEffortElo']),
        'artElo': _toInt(data['artSkillElo']) + _toInt(data['artEffortElo']),
        'topEndeavour': _topEndeavour(data),
      };
    });
    final members = await Future.wait(futures);
    members.sort((a, b) {
      if (_selectedSort == 'Gym Elo') {
        return (b['gymElo'] as int).compareTo(a['gymElo'] as int);
      }
      if (_selectedSort == 'Academic Elo') {
        return (b['academicElo'] as int).compareTo(a['academicElo'] as int);
      }
      if (_selectedSort == 'Art Elo') {
        return (b['artElo'] as int).compareTo(a['artElo'] as int);
      }
      return (b['elo'] as int).compareTo(a['elo'] as int);
    });
    return members;
  }

  IconData _endeavourIcon(String endeavour) {
    switch (endeavour.toLowerCase()) {
      case 'gym':
        return Icons.fitness_center;
      case 'academic':
        return Icons.school;
      case 'art':
        return Icons.palette;
      default:
        return Icons.star;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GlbPainter())),
          SafeArea(
            child: Column(
              children: [
                Padding(
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
                      Expanded(
                        child: Text(
                          widget.groupName,
                          style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white,
                            letterSpacing: -0.5, fontFamily: '.SF Pro Display',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadLeaderboardMembers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load leaderboard: ${snapshot.error}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                );
              }
              final members = snapshot.data ?? [];
              final total = members.fold(
                0,
                (acc, member) => acc + (member['elo'] as int),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.groupName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Code: ${widget.groupCode}',
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade300.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Group Elo',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatElo(total),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildGroupActions(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
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
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
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
                  const SizedBox(height: 10),
                  if (members.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'No members in this group yet.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: members.length,
                        itemBuilder: (context, index) {
                          final member = members[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 15.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 40,
                                        child: Text(
                                          '#${index + 1}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                            color: index == 0
                                                ? Colors.amber
                                                : Colors.white70,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white.withValues(
                                            alpha: 0.1,
                                          ),
                                          image: member['photoUrl'] != null
                                              ? DecorationImage(
                                                  image: NetworkImage(
                                                    member['photoUrl']
                                                        as String,
                                                  ),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                        ),
                                        child: member['photoUrl'] == null
                                            ? const Icon(
                                                Icons.person,
                                                size: 18,
                                                color: Colors.white24,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 12),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '@${member['username']}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  _endeavourIcon(
                                                    member['topEndeavour']
                                                        as String,
                                                  ),
                                                  size: 16,
                                                  color: Colors.white54,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  member['topEndeavour']
                                                      as String,
                                                  style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _formatElo(
                                          _selectedSort == 'Gym Elo'
                                              ? member['gymElo'] as int
                                              : _selectedSort == 'Academic Elo'
                                              ? member['academicElo'] as int
                                              : _selectedSort == 'Art Elo'
                                              ? member['artElo'] as int
                                              : member['elo'] as int,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      if (_uid == widget.leaderId &&
                                          member['uid'] != _uid)
                                        _buildMemberManagementMenu(member),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupActions() {
    final bool isMember = widget.memberIds.contains(_uid);

    if (!isMember) {
      bool isRequesting = false;

      return StatefulBuilder(
        builder: (context, setBtnState) {
          if (isRequesting) {
            return SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.teal.shade300,
              ),
            );
          }

          return ElevatedButton(
            onPressed: () async {
              if (widget.isPrivate) {
                setBtnState(() => isRequesting = true);
                try {
                  await _socialService.requestToJoinGroup(
                    widget.groupId,
                    widget.groupName,
                    widget.leaderId,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Join request sent!')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Request failed: $e')),
                    );
                  }
                } finally {
                  if (mounted) setBtnState(() => isRequesting = false);
                }
              } else {
                try {
                  await _socialService.joinGroup(widget.groupId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Joined group!')),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to join: $e')),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade300,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(
              widget.isPrivate ? 'REQUEST' : 'JOIN',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        },
      );
    }

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white70),
      color: const Color(0xFF141428),
      onSelected: (value) async {
        if (value == 'leave') {
          _confirmLeaveGroup();
        } else if (value == 'delete') {
          _confirmDeleteGroup();
        }
      },
      itemBuilder: (context) => [
        if (widget.leaderId != _uid)
          const PopupMenuItem(
            value: 'leave',
            child: Row(
              children: [
                Icon(Icons.exit_to_app, color: Colors.redAccent, size: 20),
                SizedBox(width: 10),
                Text('Leave Group', style: TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
        if (widget.leaderId == _uid)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_forever, color: Colors.redAccent, size: 20),
                SizedBox(width: 10),
                Text('Delete Group', style: TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMemberManagementMenu(Map<String, dynamic> member) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.settings, color: Colors.white38, size: 20),
      color: const Color(0xFF141428),
      onSelected: (value) async {
        if (value == 'kick') {
          _confirmKickMember(member);
        } else if (value == 'leader') {
          _confirmTransferLeadership(member);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'leader',
          child: Row(
            children: [
              Icon(Icons.star, color: Colors.amber, size: 20),
              SizedBox(width: 10),
              Text('Make Leader', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'kick',
          child: Row(
            children: [
              Icon(Icons.person_remove, color: Colors.redAccent, size: 20),
              SizedBox(width: 10),
              Text('Kick Member', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmLeaveGroup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141428),
        title: const Text(
          'Leave Group?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to leave this group?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              nav.pop();
              try {
                await _socialService.leaveGroup(widget.groupId);
                if (mounted) {
                  nav.pop(); // Close leaderboard
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Left group successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Leave',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmKickMember(Map<String, dynamic> member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141428),
        title: Text(
          'Kick @${member['username']}?',
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will remove them from the group.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              nav.pop();
              try {
                await _socialService.kickMember(widget.groupId, member['uid']);
                if (mounted) {
                  setState(() {
                    _currentMemberIds.remove(member['uid']);
                  });
                  messenger.showSnackBar(
                    SnackBar(content: Text('Kicked @${member['username']}')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Kick',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmTransferLeadership(Map<String, dynamic> member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141428),
        title: const Text(
          'Transfer Leadership?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'By making @${member['username']} the leader, you will lose management privileges.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              nav.pop();
              try {
                await _socialService.transferLeadership(
                  widget.groupId,
                  member['uid'],
                );
                if (mounted) {
                  nav.pop(); // Close leaderboard
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Leadership transferred to @${member['username']}',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Transfer',
              style: TextStyle(color: Colors.amber),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteGroup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141428),
        title: const Text(
          'Delete Group?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This action is permanent. All membership data will be lost.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              nav.pop();
              try {
                await _socialService.deleteGroup(widget.groupId);
                if (mounted) {
                  nav.pop(); // Close leaderboard
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Group deleted successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlbPainter extends CustomPainter {
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
        center: const Alignment(0.8, -0.8), radius: 0.9,
        colors: [Color(0xFFFFB830).withValues(alpha: 0.10), Colors.transparent],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(-0.8, 0.8), radius: 0.8,
        colors: [Color(0xFF6E5CFF).withValues(alpha: 0.08), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
