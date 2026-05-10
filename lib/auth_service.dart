import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Random _random = Random();
  String? lastSignUpError;

  // --- 1. SIGN IN ---
  Future<User?> signIn(String emailOrUsername, String password) async {
    try {
      String email = emailOrUsername;
      
      // Check if the input is a username (no @ symbol) or email
      if (!emailOrUsername.contains('@')) {
        // Try to find the user by username
        final userData = await getUserByUsername(emailOrUsername);
        if (userData == null) {
          print("Login Error: Username not found");
          return null;
        }
        email = userData['email'] as String;
      }
      
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      print("Login Error: $e");
      return null;
    }
  }

  // --- 2. SIGN UP & SAVE INITIAL DATA ---
  // We pass the lifting stats here so they are saved immediately upon account creation
  Future<User?> signUp(
    String email,
    String password,
    String username,
    String region,
    int bench,
    int squat,
    int deadlift,
    int initialElo,
  ) async {
    try {
      lastSignUpError = null;
      final usernameValue = sanitizeUsername(username);
      if (usernameValue.isEmpty) {
        lastSignUpError =
            'Invalid username. Use only letters, numbers, or underscores.';
        print('Sign Up Error: invalid username');
        return null;
      }

      if (region.trim().isEmpty) {
        lastSignUpError = 'Please select a region.';
        print('Sign Up Error: region missing');
        return null;
      }

      // Create the auth user FIRST so Firestore queries run authenticated
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Track so catch blocks can delete it if any later step fails.
      User? user = result.user;

      if (user == null) {
        lastSignUpError = 'Failed to create account.';
        return null;
      }

      // Now check username uniqueness (user is authenticated)
      if (!(await isUsernameAvailable(usernameValue))) {
        await user.delete();
        lastSignUpError = 'Username is already taken.';
        print('Sign Up Error: username already taken');
        return null;
      }

      print('SignUp Debug: writing /users/${user.uid}');
      await user.updateDisplayName(usernameValue);
      await _firestore.collection('users').doc(user.uid).set({
        'email': email,
        'uid': user.uid,
        'username': usernameValue,
        'usernameLower': usernameValue.toLowerCase(),
        'region': region.trim(),
        'bench': bench,
        'squat': squat,
        'deadlift': deadlift,
        'skillElo': initialElo,
        'effortElo': 0,
        'academicSkillElo': 0,
        'academicEffortElo': 0,
        'artSkillElo': 0,
        'artEffortElo': 0,
        'critiqueTokens': 3,
        'placementArtIds': [],
        'isRankedInArt': false,
        'artSkillMultiplier': 1.0,
        'groupPaths': [],
        'gymBaselineSet': false,
        'academicBaselineSet': false,
        'runningBaselineSet': false,
        'luminaryBaselineSet': false,
        'createdAt': FieldValue.serverTimestamp(),
        'codeVerified': false,
      });

      // Fire-and-forget — failure here must NOT abort signup.
      sendVerificationCode(user.uid, email).catchError((e) {
        print('SignUp: sendVerificationCode failed — $e');
      });

      return user;
    } on FirebaseAuthException catch (e) {
      lastSignUpError = e.message ?? 'Sign Up failed. Please try again.';
      print("Sign Up Error [Auth]: ${e.code} - ${e.message}");
      // No auth user to clean up — the exception came from createUserWithEmailAndPassword itself.
      return null;
    } on FirebaseException catch (e) {
      lastSignUpError = e.message ?? 'Sign Up failed. Please try again.';
      print("Sign Up Error [Firestore]: ${e.code} - ${e.message}");
      // A post-creation Firestore step failed — delete the orphaned auth user.
      try { await _auth.currentUser?.delete(); } catch (_) {}
      return null;
    } catch (e) {
      lastSignUpError = e.toString();
      print("Sign Up Error: $e");
      try { await _auth.currentUser?.delete(); } catch (_) {}
      return null;
    }
  }

  String sanitizeUsername(String username) {
    final sanitized = username.trim();
    if (sanitized.isEmpty) return '';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(sanitized)) return '';
    return sanitized;
  }

  Future<bool> isUsernameAvailable(String username) async {
    final sanitized = sanitizeUsername(username);
    if (sanitized.isEmpty) return false;

    final query = await _firestore
        .collection('users')
        .where('usernameLower', isEqualTo: sanitized.toLowerCase())
        .limit(1)
        .get();
    return query.docs.isEmpty;
  }

  Future<void> updateUsername(String newUsername) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not logged in");

    final sanitized = sanitizeUsername(newUsername);
    if (sanitized.isEmpty) {
      throw Exception(
        "Invalid username. Use only alphanumeric characters and underscores.",
      );
    }

    if (!(await isUsernameAvailable(sanitized))) {
      throw Exception("Username is already taken.");
    }

    // Update Firestore
    await _firestore.collection('users').doc(user.uid).update({
      'username': sanitized,
      'usernameLower': sanitized.toLowerCase(),
    });

    // Update Firebase Auth Display Name
    await user.updateDisplayName(sanitized);
  }

  Future<String> _buildUniqueUsername(String email) async {
    String base = email
        .split('@')
        .first
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
        .toLowerCase();
    if (base.isEmpty) {
      base = 'user${_random.nextInt(9999)}';
    }

    String candidate = base;
    int suffix = 0;

    while (true) {
      final existing = await _firestore
          .collection('users')
          .where('usernameLower', isEqualTo: candidate)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) {
        return candidate;
      }
      suffix += 1;
      candidate = '$base$suffix';
    }
  }

  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('usernameLower', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return query.docs.first.data();
      }
    } catch (e) {
      print('Username lookup failed: $e');
    }
    return null;
  }

  // --- 3. RETRIEVE USER DATA ---
  Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
    } catch (e) {
      print("Error fetching user data: $e");
    }
    return null;
  }

  // --- 4. SIGN OUT ---
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // --- PASSWORD RESET ---
  Future<void> sendPasswordResetEmail(String emailOrUsername) async {
    try {
      String email = emailOrUsername;
      
      // Check if the input is a username (no @ symbol) or email
      if (!emailOrUsername.contains('@')) {
        // Try to find the user by username
        final userData = await getUserByUsername(emailOrUsername);
        if (userData == null) {
          throw Exception("Username not found");
        }
        email = userData['email'] as String;
      }
      
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      print("Password Reset Error [Auth]: ${e.code} - ${e.message}");
      throw Exception(e.message ?? 'Failed to send reset email');
    } catch (e) {
      print("Password Reset Error: $e");
      rethrow;
    }
  }

  // --- PASSWORD RESET OTP (unauthenticated) ---
  Future<void> sendPasswordResetCode(String emailOrUsername) async {
    String email = emailOrUsername;
    if (!emailOrUsername.contains('@')) {
      final userData = await getUserByUsername(emailOrUsername);
      if (userData == null) throw Exception('Username not found.');
      email = userData['email'] as String;
    }

    final code = (1000 + _random.nextInt(9000)).toString();
    final expiry = DateTime.now().add(const Duration(minutes: 10));

    await _firestore.collection('passwordResetCodes').doc(email).set({
      'code': code,
      'expiresAt': Timestamp.fromDate(expiry),
    });

    final response = await http.post(
      Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'service_id': AppConfig.emailJsServiceId,
        'template_id': AppConfig.emailJsTemplateId,
        'user_id': AppConfig.emailJsPublicKey,
        'template_params': {
          'to_email': email,
          'otp_code': code,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('EmailJS error ${response.statusCode}: ${response.body}');
    }
  }

  // Returns the resolved email on success so the caller can display it.
  Future<String> verifyPasswordResetCode(String emailOrUsername, String code) async {
    String email = emailOrUsername;
    if (!emailOrUsername.contains('@')) {
      final userData = await getUserByUsername(emailOrUsername);
      if (userData == null) throw Exception('Username not found.');
      email = userData['email'] as String;
    }

    final doc = await _firestore.collection('passwordResetCodes').doc(email).get();
    if (!doc.exists) throw Exception('No code found. Please request a new one.');

    final data = doc.data()!;
    final storedCode = data['code'] as String?;
    final expiresAt = (data['expiresAt'] as Timestamp).toDate();

    if (storedCode == null || DateTime.now().isAfter(expiresAt)) {
      throw Exception('Code expired. Please request a new one.');
    }
    if (storedCode != code) throw Exception('Incorrect code.');

    await _firestore.collection('passwordResetCodes').doc(email).delete();
    // Send Firebase reset link so the user can actually set a new password.
    await _auth.sendPasswordResetEmail(email: email);
    return email;
  }

  // --- OTP VERIFICATION ---
  Future<void> sendVerificationCode(String uid, String email) async {
    final code = (1000 + _random.nextInt(9000)).toString();
    final expiry = DateTime.now().add(const Duration(minutes: 10));

    await _firestore.collection('verificationCodes').doc(uid).set({
      'code': code,
      'expiresAt': Timestamp.fromDate(expiry),
    });

    final response = await http.post(
      Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'service_id': AppConfig.emailJsServiceId,
        'template_id': AppConfig.emailJsTemplateId,
        'user_id': AppConfig.emailJsPublicKey,
        'template_params': {
          'to_email': email,
          'otp_code': code,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('EmailJS error ${response.statusCode}: ${response.body}');
    }
  }

  Future<bool> verifyCode(String uid, String inputCode) async {
    final doc = await _firestore.collection('verificationCodes').doc(uid).get();
    if (!doc.exists) return false;

    final data = doc.data()!;
    final storedCode = data['code'] as String?;
    final expiresAt = (data['expiresAt'] as Timestamp).toDate();

    if (storedCode == null || DateTime.now().isAfter(expiresAt)) return false;
    if (storedCode != inputCode) return false;

    await _firestore.collection('users').doc(uid).update({'codeVerified': true});
    await _firestore.collection('verificationCodes').doc(uid).delete();
    return true;
  }

  // --- EMAIL VERIFICATION (legacy — kept for existing accounts) ---
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("No user logged in");
    await user.sendEmailVerification();
  }

  // --- UPDATE EMAIL (requires prior reauthenticate call) ---
  // Uses verifyBeforeUpdateEmail: sends a verification link to the new address.
  // Firebase Auth email is only swapped after the user clicks that link.
  // Firestore is updated immediately so the UI stays in sync.
  Future<void> updateEmail(String newEmail) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not logged in");
    await user.verifyBeforeUpdateEmail(newEmail);
    await _firestore.collection('users').doc(user.uid).update({'email': newEmail});
  }

  // --- UPDATE PASSWORD (requires prior reauthenticate call) ---
  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not logged in");
    await user.updatePassword(newPassword);
  }

  // --- RE-AUTHENTICATION ---
  Future<void> reauthenticate(String password) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("No user logged in");
    if (user.email == null) throw Exception("User has no email");

    AuthCredential credential = EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );

    await user.reauthenticateWithCredential(credential);
  }

  // --- 5. PROFILE MANAGEMENT ---
  Future<void> updatePrivacy(bool isPrivate) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).update({
      'isPrivate': isPrivate,
    });
  }

  Future<void> updateProfilePicture(String downloadUrl) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).update({
      'photoUrl': downloadUrl,
    });
    await user.updatePhotoURL(downloadUrl);
  }

  Future<void> deleteUserAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;

    // We try to delete the Auth user FIRST.
    // This is because if it fails due to 'requires-recent-login',
    // we want to catch it before we delete the Firestore doc.
    try {
      await user.delete();
    } catch (e) {
      if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
        throw Exception("reauth-required");
      }
      rethrow;
    }

    // If we reach here, Auth user is deleted.
    // Now we delete the Firestore document.
    // Note: If you have security rules requiring auth, this might fail unless
    // you have a short grace period or use a cloud function.
    // However, for this implementation, we will attempt it immediately.
    try {
      await _firestore.collection('users').doc(uid).delete();
    } catch (e) {
      print("Error deleting Firestore doc (Auth user already gone): $e");
      // We don't rethrow here as the Auth account is already gone,
      // and that's the primary goal for account closure.
    }
  }
}
