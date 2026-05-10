import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:ui';

import 'group_leaderboard_screen.dart';
import 'social_service.dart';
import 'profile_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  String? _uid;
  final SocialService _socialService = SocialService();
  final TextEditingController _joinCodeController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _groupDescriptionController =
      TextEditingController();
  Widget _buildLoading() {
    return Center(
      child: CircularProgressIndicator(color: Colors.teal.shade300),
    );
  }

  final TextEditingController _groupSearchController = TextEditingController();
  final TextEditingController _friendSearchController = TextEditingController();

  List<Map<String, dynamic>> _groupSearchResults = [];
  List<Map<String, dynamic>> _friendSearchResults = [];
  bool _isSearchingGroups = false;
  bool _isSearchingFriends = false;

  String? _joinError;
  String? _createError;
  String? _createdGroupCode;
  bool _isJoining = false;
  bool _isCreating = false;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  void dispose() {
    _joinCodeController.dispose();
    _groupNameController.dispose();
    _groupDescriptionController.dispose();
    _groupSearchController.dispose();
    _friendSearchController.dispose();
    super.dispose();
  }

  Future<void> _performGroupSearch(String q) async {
    if (q.trim().isEmpty) {
      if (mounted) setState(() => _groupSearchResults = []);
      return;
    }
    setState(() => _isSearchingGroups = true);
    try {
      final results = await _socialService.searchGroups(q);
      if (mounted) setState(() => _groupSearchResults = results);
    } finally {
      if (mounted) setState(() => _isSearchingGroups = false);
    }
  }

  Future<void> _performFriendSearch(String q) async {
    if (q.trim().isEmpty) {
      if (mounted) setState(() => _friendSearchResults = []);
      return;
    }
    setState(() => _isSearchingFriends = true);
    try {
      final results = await _socialService.searchUsers(q);
      if (mounted) setState(() => _friendSearchResults = results);
    } finally {
      if (mounted) setState(() => _isSearchingFriends = false);
    }
  }

  void _showCreateGroupDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A14).withValues(alpha: 0.96),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.all(Radius.circular(2)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      Text(
                        'CREATE GROUP',
                        style: TextStyle(
                          color: Colors.teal.shade300,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Build your group.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 30),
                      TextField(
                        controller: _groupNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration('Group name', Icons.edit),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _groupDescriptionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration(
                          'Description',
                          Icons.description,
                        ),
                      ),
                      const SizedBox(height: 20),
                      StatefulBuilder(
                        builder: (context, setToggleState) {
                          return SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Private Group',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: const Text(
                              'Requires approval from leader to join',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            value: _isPrivate,
                            activeThumbColor: Colors.teal.shade300,
                            onChanged: (val) {
                              setToggleState(() => _isPrivate = val);
                              setModalState(() {});
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: _isCreating
                            ? null
                            : () async {
                                setModalState(() => _isCreating = true);
                                await _createGroup(
                                  _groupNameController.text,
                                  _groupDescriptionController.text,
                                  _isPrivate,
                                );
                                setModalState(() => _isCreating = false);
                                if (mounted && _createError == null) {
                                  Navigator.pop(context);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade300,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(
                          _isCreating ? 'CREATING...' : 'CREATE GROUP',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_createError != null) ...[
                        const SizedBox(height: 15),
                        Text(
                          _createError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: Colors.white38),
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    );
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    return 0;
  }

  int _userElo(Map<String, dynamic>? data) {
    if (data == null) return 0;
    int gymSkill = _toInt(data['skillElo']);
    int gymEffort = _toInt(data['effortElo']);
    int academicSkill = _toInt(data['academicSkillElo']);
    int academicEffort = _toInt(data['academicEffortElo']);
    return gymSkill + gymEffort + academicSkill + academicEffort;
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

  String _topEndeavour(Map<String, dynamic>? data) {
    if (data == null) return 'Unknown';
    int gym = _toInt(data['skillElo']) + _toInt(data['effortElo']);
    int academic =
        _toInt(data['academicSkillElo']) + _toInt(data['academicEffortElo']);

    if (gym == 0 && academic == 0) {
      return 'Unknown';
    }
    return gym >= academic ? 'Gym' : 'Academic';
  }

  String _normalizeGroupCode(String input) {
    return input.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  String _generateGroupCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(6, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  Future<String> _buildUniqueGroupCode() async {
    final groups = FirebaseFirestore.instance.collection('groups');
    for (int i = 0; i < 10; i++) {
      final code = _generateGroupCode();
      final doc = await groups.doc(code).get();
      if (!doc.exists) return code;
    }
    throw Exception('Could not generate unique group code.');
  }

  bool _isPrivate = false;

  Future<void> _createGroup(
    String name,
    String description,
    bool isPrivate,
  ) async {
    if (_uid == null) return;

    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      setState(() => _createError = 'Enter a valid group name.');
      return;
    }

    setState(() {
      _isCreating = true;
      _createError = null;
      _createdGroupCode = null;
    });

    try {
      final code = await _buildUniqueGroupCode();
      final groupRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(code);
      final groupData = {
        'name': cleanName,
        'description': description.trim().isEmpty
            ? 'Join with your friends using the code below.'
            : description.trim(),
        'groupScore': 0,
        'memberCount': 1,
        'members': [_uid],
        'ownerId': _uid,
        'isPrivate': isPrivate,
        'groupCode': code,
        'groupCodeLower': code.toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      await groupRef.set(groupData);
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'groupPaths': FieldValue.arrayUnion([groupRef.path]),
      });

      if (!mounted) return;
      setState(() {
        _createdGroupCode = code;
        _groupNameController.clear();
        _groupDescriptionController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group created successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      final explanation = e.toString().contains('permission-denied')
          ? 'Could not create group: Firebase permission denied. Check Firestore rules for /groups and /users.'
          : 'Could not create group: ${e.toString()}';
      setState(() => _createError = explanation);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(explanation)));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _joinGroupByCode() async {
    if (_uid == null) return;
    final code = _normalizeGroupCode(_joinCodeController.text);
    if (code.isEmpty) {
      setState(() => _joinError = 'Enter a valid group code.');
      return;
    }

    setState(() {
      _isJoining = true;
      _joinError = null;
    });

    try {
      final query = await FirebaseFirestore.instance
          .collection('groups')
          .where('groupCodeLower', isEqualTo: code.toLowerCase())
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() => _joinError = 'Group not found with that code.');
        return;
      }

      final groupDoc = query.docs.first;
      final groupPath = groupDoc.reference.path;
      final userRef = FirebaseFirestore.instance.collection('users').doc(_uid);
      final userSnapshot = await userRef.get();
      final currentPaths = List<String>.from(
        (userSnapshot.data()?['groupPaths'] ?? []) as List<dynamic>,
      );
      if (currentPaths.contains(groupPath)) {
        setState(() => _joinError = 'You are already a member of this group.');
        return;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final groupSnapshot = await transaction.get(groupDoc.reference);
        if (!groupSnapshot.exists) throw Exception('Group no longer exists.');
        transaction.update(groupDoc.reference, {
          'members': FieldValue.arrayUnion([_uid]),
          'memberCount': FieldValue.increment(1),
        });
        transaction.update(userRef, {
          'groupPaths': FieldValue.arrayUnion([groupPath]),
        });
      });

      if (!mounted) return;
      _joinCodeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Joined group successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      final explanation = e.toString().contains('permission-denied')
          ? 'Could not join group: Firebase permission denied.'
          : 'Could not join group: ${e.toString()}';
      setState(() => _joinError = explanation);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(explanation)));
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  // These features were removed to keep the group flow focused on joining by code and viewing My Groups.

  Future<List<Map<String, dynamic>>> _loadGroupMembers(
    List<dynamic> memberIds,
  ) async {
    final ids = memberIds.whereType<String>().toList();
    final futures = ids.map((id) async {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .get();
      if (!doc.exists) {
        return <String, dynamic>{
          'uid': id,
          'username': 'Unknown',
          'elo': 0,
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
        'elo': _userElo(data),
        'topEndeavour': _topEndeavour(data),
      };
    });
    final members = await Future.wait(futures);
    members.sort((a, b) => (b['elo'] as int).compareTo(a['elo'] as int));
    return members;
  }

  void _openGroupLeaderboard(Map<String, dynamic> group) {
    final members = List<String>.from(group['members'] ?? []);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupLeaderboardScreen(
          groupName: group['name'] ?? 'Group',
          groupCode: group['groupCode'] ?? 'UNKNOWN',
          memberIds: members,
          leaderId: group['ownerId'] ?? '',
          groupId: group['groupCode'] ?? '',
          isPrivate: group['isPrivate'] ?? false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A14),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(
          child: Text(
            'Sign in to view groups',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A14),
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _GroupsBgPainter())),
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
                        const Expanded(
                          child: Text(
                            'Groups',
                            style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white,
                              letterSpacing: -0.5, fontFamily: '.SF Pro Display',
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _showCreateGroupDialog,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade300.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.teal.shade300.withValues(alpha: 0.35), width: 0.7),
                                ),
                                child: Icon(Icons.add_rounded, color: Colors.teal.shade300, size: 22),
                              ),
                            ),
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
                        color: Colors.teal.shade300.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: Colors.teal.shade300.withValues(alpha: 0.45), width: 0.7),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white38,
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelStyle: const TextStyle(fontFamily: '.SF Pro Display', fontWeight: FontWeight.w600, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(fontFamily: '.SF Pro Display', fontWeight: FontWeight.w400, fontSize: 13),
                      tabs: const [Tab(text: 'My Groups'), Tab(text: 'My Friends')],
                    ),
                  ),
                  // Content
                  Expanded(child: _GroupsBody(uid: _uid, parent: this)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Extracted body widget to avoid duplicate SafeArea
class _GroupsBody extends StatelessWidget {
  final String? uid;
  final _GroupsScreenState parent;
  const _GroupsBody({required this.uid, required this.parent});

  @override
  Widget build(BuildContext context) {
    if (uid == null) {
      return Center(child: Text('Sign in to view groups', style: TextStyle(color: Colors.white.withValues(alpha: 0.40))));
    }

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final groupsRef = FirebaseFirestore.instance.collection('groups');

    return StreamBuilder<DocumentSnapshot>(
      stream: userRef.snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 1.5));
        }
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final List<String> joinedGroups = List<String>.from(userData?['groupPaths'] ?? []);

        return StreamBuilder<QuerySnapshot>(
          stream: groupsRef.snapshots(),
          builder: (context, groupsSnapshot) {
            if (groupsSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 1.5));
            }
            final groups = groupsSnapshot.data?.docs ?? [];
            final sortedGroups = [...groups];
            sortedGroups.sort((a, b) {
              final aCount = _toInt((a.data() as Map<String, dynamic>)['memberCount']);
              final bCount = _toInt((b.data() as Map<String, dynamic>)['memberCount']);
              return bCount.compareTo(aCount);
            });

            return TabBarView(
              children: [
                RefreshIndicator(
                  onRefresh: () async { await userRef.get(); await groupsRef.get(); },
                  child: _MyGroupsTab(
                    searchController: parent._groupSearchController,
                    onSearch: parent._performGroupSearch,
                    isSearching: parent._isSearchingGroups,
                    searchResults: parent._groupSearchResults,
                    joinedGroups: joinedGroups,
                    sortedGroups: sortedGroups,
                    onOpenLeaderboard: parent._openGroupLeaderboard,
                  ),
                ),
                RefreshIndicator(
                  onRefresh: () async { await userRef.get(); },
                  child: _FriendsTab(
                    searchController: parent._friendSearchController,
                    onSearch: parent._performFriendSearch,
                    isSearching: parent._isSearchingFriends,
                    searchResults: parent._friendSearchResults,
                    friendIdsStream: userRef.collection('friends').snapshots(),
                    uid: uid!,
                    onLoadMembers: parent._loadGroupMembers,
                    formatElo: parent._formatElo,
                    socialService: parent._socialService,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static int _toInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
}

class _MyGroupsTab extends StatelessWidget {
  final TextEditingController searchController;
  final Function(String) onSearch;
  final bool isSearching;
  final List<Map<String, dynamic>> searchResults;
  final List<String> joinedGroups;
  final List<QueryDocumentSnapshot> sortedGroups;
  final Function(Map<String, dynamic>) onOpenLeaderboard;

  const _MyGroupsTab({
    required this.searchController,
    required this.onSearch,
    required this.isSearching,
    required this.searchResults,
    required this.joinedGroups,
    required this.sortedGroups,
    required this.onOpenLeaderboard,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        _SearchBar(
          hint: 'Search groups...',
          controller: searchController,
          onSearch: onSearch,
        ),
        const SizedBox(height: 25),
        if (searchController.text.isNotEmpty) ...[
          const _Header(text: 'GROUP SEARCH'),
          const SizedBox(height: 15),
          if (isSearching)
            Center(
              child: CircularProgressIndicator(color: Colors.teal.shade300),
            )
          else if (searchResults.isEmpty)
            const Center(
              child: Text(
                'No groups found.',
                style: TextStyle(color: Colors.white38),
              ),
            )
          else
            ...searchResults.map(
              (group) => _GroupSearchResultCard(
                group: group,
                isJoined: joinedGroups.contains(
                  FirebaseFirestore.instance.doc(group['path']).path,
                ),
              ),
            ),
        ] else ...[
          const _Header(text: 'MY GROUPS'),
          const SizedBox(height: 15),
          if (joinedGroups.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  'You haven\'t joined any groups yet.\nCreate one or join with a code!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            )
          else
            ...sortedGroups
                .where((doc) => joinedGroups.contains(doc.reference.path))
                .map((doc) {
                  final group = doc.data() as Map<String, dynamic>;
                  return _GroupCard(
                    group: group,
                    onTap: () => onOpenLeaderboard(group),
                  );
                }),
          const SizedBox(height: 25),
          const _Header(text: 'POPULAR GROUPS'),
          const SizedBox(height: 15),
          ...sortedGroups
              .where((doc) => !joinedGroups.contains(doc.reference.path))
              .take(10)
              .map((doc) {
                final group = doc.data() as Map<String, dynamic>;
                return _GroupCard(
                  group: group,
                  isJoined: false,
                  onTap: () => onOpenLeaderboard(group),
                );
              }),
        ],
        const SizedBox(height: 40),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool isJoined;
  final VoidCallback onTap;

  const _GroupCard({
    required this.group,
    this.isJoined = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade300.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.group, color: Colors.teal.shade300),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group['name'] ?? 'Group',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${group['memberCount'] ?? 0} members',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (!isJoined)
              const Icon(Icons.chevron_right, color: Colors.white24)
            else
              const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
          ],
        ),
      ),
    );
  }
}

class _GroupSearchResultCard extends StatefulWidget {
  final Map<String, dynamic> group;
  final bool isJoined;

  const _GroupSearchResultCard({required this.group, required this.isJoined});

  @override
  State<_GroupSearchResultCard> createState() => _GroupSearchResultCardState();
}

class _GroupSearchResultCardState extends State<_GroupSearchResultCard> {
  final SocialService _socialService = SocialService();
  bool _isRequesting = false;

  @override
  Widget build(BuildContext context) {
    final bool isPrivate = widget.group['isPrivate'] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.group['name'] ?? 'Group',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isPrivate) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.lock_outline,
                        color: Colors.white38,
                        size: 14,
                      ),
                    ],
                  ],
                ),
                Text(
                  '${widget.group['memberCount'] ?? 0} members',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          if (widget.isJoined)
            const Text(
              'JOINED',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            )
          else if (_isRequesting)
            SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.teal.shade300,
              ),
            )
          else
            ElevatedButton(
              onPressed: () async {
                if (isPrivate) {
                  setState(() => _isRequesting = true);
                  try {
                    await _socialService.requestToJoinGroup(
                      widget.group['id'],
                      widget.group['name'] ?? 'Group',
                      widget.group['ownerId'],
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
                    if (mounted) setState(() => _isRequesting = false);
                  }
                } else {
                  setState(() => _isRequesting = true);
                  try {
                    await _socialService.joinGroup(widget.group['id']);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Joined group!')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Join failed: $e')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isRequesting = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade300.withValues(alpha: 0.1),
                foregroundColor: Colors.teal.shade300,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isPrivate ? 'REQUEST' : 'JOIN',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  final Function(String) onSearch;

  const _SearchBar({
    required this.hint,
    required this.controller,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        onSubmitted: onSearch,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38),
                  onPressed: () {
                    controller.clear();
                    onSearch('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }
}

class _FriendsTab extends StatelessWidget {
  final TextEditingController searchController;
  final Function(String) onSearch;
  final bool isSearching;
  final List<Map<String, dynamic>> searchResults;
  final Stream<QuerySnapshot> friendIdsStream;
  final String uid;
  final Future<List<Map<String, dynamic>>> Function(List<dynamic>)
  onLoadMembers;
  final String Function(int) formatElo;
  final SocialService socialService;

  const _FriendsTab({
    required this.searchController,
    required this.onSearch,
    required this.isSearching,
    required this.searchResults,
    required this.friendIdsStream,
    required this.uid,
    required this.onLoadMembers,
    required this.formatElo,
    required this.socialService,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        _SearchBar(
          hint: 'Search users by username or ID...',
          controller: searchController,
          onSearch: onSearch,
        ),
        const SizedBox(height: 25),
        if (searchController.text.isNotEmpty) ...[
          const _Header(text: 'SOCIAL SEARCH'),
          const SizedBox(height: 15),
          if (isSearching)
            Center(
              child: CircularProgressIndicator(color: Colors.teal.shade300),
            )
          else if (searchResults.isEmpty)
            const Center(
              child: Text(
                'No users found.',
                style: TextStyle(color: Colors.white38),
              ),
            )
          else
            ...searchResults.map(
              (user) => FriendSearchResultCard(
                user: user,
                uid: uid,
                socialService: socialService,
              ),
            ),
        ] else ...[
          const _Header(text: 'FRIEND LEADERBOARD'),
          const SizedBox(height: 15),
          StreamBuilder<QuerySnapshot>(
            stream: friendIdsStream,
            builder: (context, friendsSnapshot) {
              if (friendsSnapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: Colors.teal.shade300),
                );
              }
              final friendDocs = friendsSnapshot.data?.docs ?? [];
              final friendIds = friendDocs.map((d) => d.id).toList();

              return FutureBuilder<List<Map<String, dynamic>>>(
                future: onLoadMembers([...friendIds, uid]),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: Colors.teal.shade300,
                      ),
                    );
                  }
                  final members = snapshot.data ?? [];
                  if (members.length <= 1) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          'You have no friends yet.\nSearch for friends to compete!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: members.asMap().entries.map((entry) {
                      return FriendLeaderboardItem(
                        member: entry.value,
                        rank: entry.key + 1,
                        uid: uid,
                        formatElo: formatElo,
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }
}

class FriendSearchResultCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final String uid;
  final SocialService socialService;

  const FriendSearchResultCard({
    super.key,
    required this.user,
    required this.uid,
    required this.socialService,
  });

  @override
  Widget build(BuildContext context) {
    final bool isMe = user['uid'] == uid;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.white10,
            child: Icon(Icons.person, color: Colors.white70),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['username'] ?? 'Unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'ID: ${user['uid']}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
          if (!isMe)
            IconButton(
              onPressed: () => socialService.sendFriendRequest(user['uid']),
              icon: Icon(Icons.person_add, color: Colors.teal.shade300),
            )
          else
            const Text(
              'YOU',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
        ],
      ),
    );
  }
}

class FriendLeaderboardItem extends StatelessWidget {
  final Map<String, dynamic> member;
  final int rank;
  final String uid;
  final String Function(int) formatElo;

  const FriendLeaderboardItem({
    super.key,
    required this.member,
    required this.rank,
    required this.uid,
    required this.formatElo,
  });

  @override
  Widget build(BuildContext context) {
    final bool isMe = member['uid'] == uid;
    return GestureDetector(
      onTap: isMe
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => ProfileScreen(targetUid: member['uid']),
                ),
              );
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.teal.shade300.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isMe
                ? Colors.teal.shade300.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Text(
              '#$rank',
              style: TextStyle(
                color: rank == 1
                    ? Colors.amber
                    : (isMe ? Colors.teal.shade300 : Colors.white54),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member['username'] ?? 'User',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Text(
                    'ID: ${member['uid']}',
                    style: const TextStyle(color: Colors.white24, fontSize: 9),
                  ),
                ],
              ),
            ),
            Text(
              '${formatElo(member['elo'] ?? 0)} Elo',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupsBgPainter extends CustomPainter {
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
        center: const Alignment(-0.5, -1.0), radius: 1.0,
        colors: [const Color(0xFF4DB6AC).withValues(alpha: 0.10), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
