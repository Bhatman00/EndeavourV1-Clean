import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'social_service.dart';

const _kBg0 = Color(0xFF0A0A14);
const _kBg1 = Color(0xFF141428);
const _kAccent = Color(0xFF6E5CFF);
const _kPink = Color(0xFFFF3B5C);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SocialService _socialService = SocialService();

  Widget _buildNotificationItem(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type'] ?? 'unknown';
    final senderUsername = data['senderUsername'] ?? 'Someone';
    final notificationId = doc.id;

    if (type == 'friend_request') {
      return _buildFriendRequestItem(notificationId, data, senderUsername);
    } else if (type == 'group_invite') {
      return _buildGroupInviteItem(notificationId, data, senderUsername);
    } else if (type == 'join_request') {
      return _buildJoinRequestItem(notificationId, data, senderUsername);
    }
    return const SizedBox.shrink();
  }

  Widget _buildFriendRequestItem(String notificationId, Map<String, dynamic> data, String senderUsername) {
    return _buildCardWrapper(
      icon: Icons.person_add_rounded,
      iconColor: _kAccent,
      title: 'Friend Request',
      subtitle: '@$senderUsername wants to be friends',
      onAccept: () async {
        try {
          await _socialService.acceptFriendRequest(notificationId, data['senderId']);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend request accepted!')));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: _kPink));
        }
      },
      onDecline: () async {
        try {
          await _socialService.declineNotification(notificationId);
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: _kPink));
        }
      },
    );
  }

  Widget _buildGroupInviteItem(String notificationId, Map<String, dynamic> data, String senderUsername) {
    final groupName = data['groupName'] ?? 'a group';
    return _buildCardWrapper(
      icon: Icons.group_add_rounded,
      iconColor: Colors.teal.shade300,
      title: 'Group Invite',
      subtitle: '@$senderUsername invited you to $groupName',
      onAccept: () async {
        try {
          await _socialService.acceptGroupInvite(notificationId, data['groupId']);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Joined group!')));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: _kPink));
        }
      },
      onDecline: () async {
        try {
          await _socialService.declineNotification(notificationId);
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: _kPink));
        }
      },
    );
  }

  Widget _buildJoinRequestItem(String notificationId, Map<String, dynamic> data, String senderUsername) {
    final groupName = data['groupName'] ?? 'your group';
    return _buildCardWrapper(
      icon: Icons.group_add_rounded,
      iconColor: Colors.teal.shade300,
      title: 'Join Request',
      subtitle: '@$senderUsername wants to join $groupName',
      onAccept: () async {
        try {
          await _socialService.acceptJoinRequest(notificationId, data['groupId'], data['senderId']);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request accepted!')));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: _kPink));
        }
      },
      onDecline: () async {
        try {
          await _socialService.declineNotification(notificationId);
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: _kPink));
        }
      },
    );
  }

  Widget _buildCardWrapper({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onAccept,
    required VoidCallback onDecline,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, color: iconColor, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700,
                              fontSize: 15, fontFamily: '.SF Pro Display', height: 1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.50),
                              fontSize: 13, fontFamily: '.SF Pro Display', height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onDecline,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
                          ),
                          child: const Center(
                            child: Text(
                              'Decline',
                              style: TextStyle(
                                color: Colors.white54, fontSize: 13,
                                fontWeight: FontWeight.w600, fontFamily: '.SF Pro Display',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: onAccept,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: _kAccent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _kAccent.withValues(alpha: 0.45), width: 0.7),
                          ),
                          child: const Center(
                            child: Text(
                              'Accept',
                              style: TextStyle(
                                color: Colors.white, fontSize: 13,
                                fontWeight: FontWeight.w700, fontFamily: '.SF Pro Display',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg0,
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _NotifPainter())),
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
                      const Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white,
                          letterSpacing: -0.5, fontFamily: '.SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _socialService.getNotificationsStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 1.5));
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: _kPink)),
                          ),
                        );
                      }

                      final rawDocs = snapshot.data?.docs ?? [];
                      final docs = List<QueryDocumentSnapshot>.from(rawDocs);
                      docs.sort((a, b) {
                        final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                        final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                        if (aTime == null && bTime == null) return 0;
                        if (aTime == null) return 1;
                        if (bTime == null) return -1;
                        return bTime.compareTo(aTime);
                      });

                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56, height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                                ),
                                child: Icon(Icons.notifications_none_rounded, color: Colors.white.withValues(alpha: 0.30), size: 28),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No new notifications',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  fontSize: 15, fontFamily: '.SF Pro Display',
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
                        itemCount: docs.length,
                        itemBuilder: (context, index) => _buildNotificationItem(docs[index]),
                      );
                    },
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

class _NotifPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [_kBg0, _kBg1, _kBg0], stops: [0.0, 0.6, 1.0],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(0.7, -0.8), radius: 0.9,
        colors: [_kAccent.withValues(alpha: 0.12), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
