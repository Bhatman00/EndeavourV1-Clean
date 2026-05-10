import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'email_verification_screen.dart';
import 'home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EndeavourApp());
}

class EndeavourApp extends StatelessWidget {
  const EndeavourApp({super.key});

  static final Future<FirebaseApp> _firebaseInitialization =
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: _firebaseInitialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: Color(0xFF0F0F13),
              body: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: Color(0xFF0F0F13),
              body: Center(
                child: Text(
                  'Initialization failed. Please restart.',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            fontFamily: '.SF Pro Display',
            textTheme: const TextTheme(
              displayLarge: TextStyle(
                fontFamily: '.SF Pro Display',
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
              displayMedium: TextStyle(
                fontFamily: '.SF Pro Display',
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
              displaySmall: TextStyle(
                fontFamily: '.SF Pro Display',
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
              headlineMedium: TextStyle(
                fontFamily: '.SF Pro Display',
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
              titleLarge: TextStyle(
                fontFamily: '.SF Pro Display',
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              bodyLarge: TextStyle(
                fontFamily: '.SF Pro Display',
                fontWeight: FontWeight.w400,
                letterSpacing: -0.2,
              ),
            ),
          ),
          routes: {
            '/home': (context) => const HomeScreen(),
            '/login': (context) => const LoginScreen(),
          },
          // Automatically route user based on Auth State
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.userChanges(),
            builder: (context, authSnapshot) {
              if (authSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  backgroundColor: Color(0xFF0F0F13),
                  body: Center(child: CircularProgressIndicator(color: Colors.white)),
                );
              }

              if (!authSnapshot.hasData) return const LoginScreen();

              final user = authSnapshot.data!;

              // Existing accounts verified via Firebase email link — let them through.
              if (user.emailVerified) return const HomeScreen();

              // New accounts: gate on Firestore codeVerified flag.
              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, fsSnapshot) {
                  if (fsSnapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      backgroundColor: Color(0xFF0F0F13),
                      body: Center(child: CircularProgressIndicator(color: Colors.white)),
                    );
                  }
                  final data = fsSnapshot.data?.data() as Map<String, dynamic>?;
                  final verified = data?['codeVerified'] == true;
                  return verified ? const HomeScreen() : const EmailVerificationScreen();
                },
              );
            },
          ),
        );
      },
    );
  }
}
