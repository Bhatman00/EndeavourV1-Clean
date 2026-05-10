import 'package:flutter/material.dart';
import 'dart:ui';
import 'auth_service.dart';
import 'forgot_password_screen.dart';

const _kBg0 = Color(0xFF0A0A14);
const _kBg1 = Color(0xFF141428);
const _kAccent = Color(0xFF6E5CFF);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  String _selectedRegion = 'Select region';
  final List<String> _regions = ['Select region', 'OCE', 'Asia', 'Europe', 'NA', 'SA', 'Unknown'];

  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submitAuth() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }

    setState(() => _isLoading = true);

    if (_isLogin) {
      var user = await _authService.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Login Failed. Check your credentials.")),
          );
          setState(() => _isLoading = false);
        }
      }
      // Success: do NOT navigate manually. The authStateChanges() StreamBuilder
      // in main.dart detects the sign-in and routes to EmailVerificationScreen
      // or HomeScreen depending on user.emailVerified.
    } else {
      if (_passwordController.text != _confirmPasswordController.text) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Passwords do not match.")));
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      if (_usernameController.text.trim().isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please choose a username.")));
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      if (_selectedRegion == 'Select region' || _selectedRegion.trim().isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select your region.")));
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      var user = await _authService.signUp(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _usernameController.text.trim(),
        _selectedRegion,
        0, 0, 0, 0,
      );

      if (user != null) {
        // Reset the spinner so the login screen doesn't hang while the
        // StreamBuilder in main.dart swaps in EmailVerificationScreen.
        if (mounted) setState(() => _isLoading = false);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_authService.lastSignUpError ?? "Sign Up failed. Username may be invalid or already in use."),
            ),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  InputDecoration _fieldDecor(String label, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38, fontFamily: '.SF Pro Display', fontSize: 14),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _kAccent.withValues(alpha: 0.6), width: 0.8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg0,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _LoginPainter())),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
              child: Column(
                children: [
                  const SizedBox(height: 56),
                  // Brand header
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
                        fontSize: 44, fontWeight: FontWeight.w200, color: Colors.white,
                        letterSpacing: -1.8, fontFamily: '.SF Pro Display',
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isLogin ? 'welcome back' : 'join the journey',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w300,
                      color: Colors.white.withValues(alpha: 0.38),
                      letterSpacing: 1.4, fontFamily: '.SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Glass form card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isLogin ? "SIGN IN" : "CREATE ACCOUNT",
                              style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.40),
                                letterSpacing: 1.6, fontFamily: '.SF Pro Display',
                              ),
                            ),
                            const SizedBox(height: 20),

                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: Colors.white, fontFamily: '.SF Pro Display'),
                              decoration: _fieldDecor(_isLogin ? "Email or Username" : "Email", Icons.mail_outline_rounded),
                            ),
                            if (!_isLogin) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _usernameController,
                                style: const TextStyle(color: Colors.white, fontFamily: '.SF Pro Display'),
                                decoration: _fieldDecor("Username", Icons.person_outline_rounded),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: _selectedRegion,
                                dropdownColor: const Color(0xFF141428),
                                icon: const Icon(Icons.public_rounded, color: Colors.white38, size: 20),
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: '.SF Pro Display'),
                                decoration: _fieldDecor('Region', Icons.public_rounded),
                                items: _regions.map((r) => DropdownMenuItem<String>(value: r, child: Text(r))).toList(),
                                onChanged: (v) { if (v != null) setState(() => _selectedRegion = v); },
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              style: const TextStyle(color: Colors.white, fontFamily: '.SF Pro Display'),
                              decoration: _fieldDecor("Password", Icons.lock_outline_rounded),
                            ),

                            if (!_isLogin) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _confirmPasswordController,
                                obscureText: true,
                                style: const TextStyle(color: Colors.white, fontFamily: '.SF Pro Display'),
                                decoration: _fieldDecor("Confirm Password", Icons.lock_outline_rounded),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Username must be unique and use letters, numbers, or underscores.",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.30),
                                  fontSize: 11, fontFamily: '.SF Pro Display',
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),

                            _isLoading
                                ? const Center(child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 1.5))
                                : GestureDetector(
                                    onTap: _submitAuth,
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      decoration: BoxDecoration(
                                        color: _kAccent,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _kAccent.withValues(alpha: 0.35),
                                            blurRadius: 24, offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          _isLogin ? "SIGN IN" : "CREATE ACCOUNT",
                                          style: const TextStyle(
                                            fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white,
                                            letterSpacing: 0.8, fontFamily: '.SF Pro Display',
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
                  const SizedBox(height: 20),

                  GestureDetector(
                    onTap: () => setState(() {
                      _isLogin = !_isLogin;
                      _confirmPasswordController.clear();
                    }),
                    child: Text(
                      _isLogin ? "Need an account?  Sign Up" : "Already have an account?  Sign In",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13, fontFamily: '.SF Pro Display', letterSpacing: -0.1,
                      ),
                    ),
                  ),

                  if (_isLogin) ...[
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                      ),
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: _kAccent.withValues(alpha: 0.75),
                          fontSize: 13, fontFamily: '.SF Pro Display', letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginPainter extends CustomPainter {
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
        center: const Alignment(-0.4, -1.0), radius: 1.1,
        colors: [_kAccent.withValues(alpha: 0.22), Colors.transparent],
      ).createShader(rect));
    canvas.drawRect(rect, Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = RadialGradient(
        center: const Alignment(1.1, 0.9), radius: 0.8,
        colors: [_kAccent.withValues(alpha: 0.10), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
