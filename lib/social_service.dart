import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SocialService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> sendFriendRequest(String targetUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || targetUid == uid) return;

    final userDoc = await _db.collection('users').doc(uid).get();
    final username = userDoc.data()?['username'] ?? 'Someone';

    await _db
        .collection('notifications')
        .doc('fr_${uid}_$targetUid') // Global unique ID for friend request
        .set({
          'type': 'friend_request',
          'senderId': uid,
          'senderUsername': username,
          'recipientId': targetUid,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> acceptFriendRequest(
    String notificationId,
    String requesterUid,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final batch = _db.batch();

    // Mark notification as accepted
    final notifRef = _db.collection('notifications').doc(notificationId);
    batch.update(notifRef, {'status': 'accepted'});

    // Add friend to my list
    final myFriendRef = _db
        .collection('users')
        .doc(uid)
        .collection('friends')
        .doc(requesterUid);
    batch.set(myFriendRef, {
      'friendUid': requesterUid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Add me to their list
    final theirFriendRef = _db
        .collection('users')
        .doc(requesterUid)
        .collection('friends')
        .doc(uid);
    batch.set(theirFriendRef, {
      'friendUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
    } catch (e) {
      print("Error accepting friend request: $e");
      rethrow;
    }
  }

  Future<void> declineNotification(String notificationId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db.collection('notifications').doc(notificationId).update({
        'status': 'declined',
      });
    } catch (e) {
      print("Error declining notification: $e");
      rethrow;
    }
  }

  Future<void> sendGroupInvite(
    String targetUid,
    String groupId,
    String groupName,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || targetUid == uid) return;

    final userDoc = await _db.collection('users').doc(uid).get();
    final username = userDoc.data()?['username'] ?? 'Someone';

    await _db
        .collection('notifications')
        .doc(
          'gi_${groupId}_${uid}_$targetUid',
        ) // Global unique ID for group invite
        .set({
          'type': 'group_invite',
          'senderId': uid,
          'senderUsername': username,
          'recipientId': targetUid,
          'groupId': groupId,
          'groupName': groupName,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> acceptGroupInvite(String notificationId, String groupId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final groupRef = _db.collection('groups').doc(groupId);
    final userRef = _db.collection('users').doc(uid);

    try {
      await _db.runTransaction((transaction) async {
        final groupSnapshot = await transaction.get(groupRef);
        final userSnapshot = await transaction.get(userRef);

        if (groupSnapshot.exists) {
          final groupPath = groupRef.path;

          final List<String> currentPaths = List<String>.from(
            userSnapshot.data()?['groupPaths'] ?? [],
          );
          if (!currentPaths.contains(groupPath)) {
            transaction.update(groupRef, {
              'members': FieldValue.arrayUnion([uid]),
              'memberCount': FieldValue.increment(1),
            });

            transaction.update(userRef, {
              'groupPaths': FieldValue.arrayUnion([groupPath]),
            });
          }
        }
      });

      // Update notification
      await _db.collection('notifications').doc(notificationId).update({
        'status': 'accepted',
      });
    } catch (e) {
      print("Failed to join group: $e");
      rethrow;
    }
  }

  Stream<QuerySnapshot> getNotificationsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _db
        .collection('notifications')
        .where('recipientId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  Future<List<Map<String, dynamic>>> searchGroups(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // Search by exact code
    final codeQuery = await _db
        .collection('groups')
        .where('groupCode', isEqualTo: cleanQuery.toUpperCase())
        .get();

    if (codeQuery.docs.isNotEmpty) {
      return codeQuery.docs
          .map((d) => {...d.data(), 'id': d.id, 'path': d.reference.path})
          .toList();
    }

    // Search by name prefix
    final nameQuery = await _db
        .collection('groups')
        .where('name', isGreaterThanOrEqualTo: cleanQuery)
        .where('name', isLessThanOrEqualTo: '$cleanQuery\uf8ff')
        .limit(10)
        .get();

    return nameQuery.docs
        .map((d) => {...d.data(), 'id': d.id, 'path': d.reference.path})
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // Search by exact UID
    final uidQuery = await _db
        .collection('users')
        .where('uid', isEqualTo: cleanQuery)
        .get();

    if (uidQuery.docs.isNotEmpty) {
      return uidQuery.docs.map((d) => d.data()).toList();
    }

    // Search by username prefix
    final usernameQuery = await _db
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: cleanQuery)
        .where('username', isLessThanOrEqualTo: '$cleanQuery\uf8ff')
        .limit(10)
        .get();

    return usernameQuery.docs.map((d) => d.data()).toList();
  }

  Future<void> transferLeadership(String groupId, String newLeaderUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final groupRef = _db.collection('groups').doc(groupId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(groupRef);
      if (!snapshot.exists) throw Exception('Group not found');
      if (snapshot.data()?['ownerId'] != uid) {
        throw Exception('Only the leader can transfer leadership');
      }

      transaction.update(groupRef, {'ownerId': newLeaderUid});
    });
  }

  Future<void> kickMember(String groupId, String memberUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final groupRef = _db.collection('groups').doc(groupId);
    final userRef = _db.collection('users').doc(memberUid);

    await _db.runTransaction((transaction) async {
      final groupSnap = await transaction.get(groupRef);
      if (!groupSnap.exists) throw Exception('Group not found');
      if (groupSnap.data()?['ownerId'] != uid) {
        throw Exception('Only the leader can kick members');
      }
      if (memberUid == uid) throw Exception('You cannot kick yourself');

      final groupPath = groupRef.path;

      transaction.update(groupRef, {
        'members': FieldValue.arrayRemove([memberUid]),
        'memberCount': FieldValue.increment(-1),
      });

      transaction.update(userRef, {
        'groupPaths': FieldValue.arrayRemove([groupPath]),
      });
    });
  }

  Future<void> leaveGroup(String groupId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final groupRef = _db.collection('groups').doc(groupId);
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((transaction) async {
      final groupSnap = await transaction.get(groupRef);
      if (!groupSnap.exists) throw Exception('Group not found');

      if (groupSnap.data()?['ownerId'] == uid) {
        throw Exception(
          'Leader cannot leave without transferring leadership or deleting the group',
        );
      }

      final groupPath = groupRef.path;

      transaction.update(groupRef, {
        'members': FieldValue.arrayRemove([uid]),
        'memberCount': FieldValue.increment(-1),
      });

      transaction.update(userRef, {
        'groupPaths': FieldValue.arrayRemove([groupPath]),
      });
    });
  }

  Future<void> requestToJoinGroup(
    String groupId,
    String groupName,
    String leaderId,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userDoc = await _db.collection('users').doc(uid).get();
    final username = userDoc.data()?['username'] ?? 'Someone';

    await _db.collection('notifications').doc('jr_${groupId}_$uid').set({
      'type': 'join_request',
      'senderId': uid,
      'senderUsername': username,
      'recipientId': leaderId,
      'groupId': groupId,
      'groupName': groupName,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> acceptJoinRequest(
    String notificationId,
    String groupId,
    String requesterUid,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final groupRef = _db.collection('groups').doc(groupId);
    final userRef = _db.collection('users').doc(requesterUid);

    await _db.runTransaction((transaction) async {
      final groupSnap = await transaction.get(groupRef);
      if (!groupSnap.exists) throw Exception('Group not found');
      if (groupSnap.data()?['ownerId'] != uid) {
        throw Exception('Only the leader can accept join requests');
      }

      final groupPath = groupRef.path;

      transaction.update(groupRef, {
        'members': FieldValue.arrayUnion([requesterUid]),
        'memberCount': FieldValue.increment(1),
      });

      transaction.update(userRef, {
        'groupPaths': FieldValue.arrayUnion([groupPath]),
      });
    });

    await _db.collection('notifications').doc(notificationId).update({
      'status': 'accepted',
    });
  }

  Future<void> joinGroup(String groupId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final groupRef = _db.collection('groups').doc(groupId);
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((transaction) async {
      final groupSnap = await transaction.get(groupRef);
      if (!groupSnap.exists) throw Exception('Group not found');

      final members = List<String>.from(groupSnap.data()?['members'] ?? []);
      if (members.contains(uid)) throw Exception('Already a member');

      final isPrivate = groupSnap.data()?['isPrivate'] ?? false;
      if (isPrivate) {
        throw Exception('This group is private. Please send a join request.');
      }

      final groupPath = groupRef.path;

      transaction.update(groupRef, {
        'members': FieldValue.arrayUnion([uid]),
        'memberCount': FieldValue.increment(1),
      });

      transaction.update(userRef, {
        'groupPaths': FieldValue.arrayUnion([groupPath]),
      });
    });
  }

  Future<void> deleteGroup(String groupId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final groupRef = _db.collection('groups').doc(groupId);

    final snap = await groupRef.get();
    if (!snap.exists) return;
    if (snap.data()?['ownerId'] != uid) {
      throw Exception('Only the leader can delete the group');
    }

    final memberIds = List<String>.from(snap.data()?['members'] ?? []);
    final groupPath = groupRef.path;

    final batch = _db.batch();

    // Delete group doc
    batch.delete(groupRef);

    // Remove group from all members' groupPaths
    for (final memberId in memberIds) {
      batch.update(_db.collection('users').doc(memberId), {
        'groupPaths': FieldValue.arrayRemove([groupPath]),
      });
    }

    await batch.commit();
  }
}
