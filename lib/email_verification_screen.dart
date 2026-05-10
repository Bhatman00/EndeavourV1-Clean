import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';

const _kBg0 = Color(0xFF0A0A14);
const _kBg1 = Color(0xFF141428);
const _kAccent = Color(0xFF6E5CFF);
const _kResendCooldown = 60;

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _hiddenController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _cooldownTimer;
  bool _isSending = false;
  bool _isVerifying = false;
  int _cooldownSeconds = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _hiddenController.addListener(_onCodeChanged);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _focusNode.requestFocus();
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _resendCode();
    });
  }

  @override
  void dispose() {
    _hiddenController.removeListener(_onCodeChanged);
    _hiddenController.dispose();
    _focusNode.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _onCodeChanged() {
    final text = _hiddenController.text;
    if (text.length == 4) _submitCode(text);
    setState(() => _errorMessage = null);
  }

  Future<void> _submitCode(String code) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final ok = await _authService.verifyCode(uid, code);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _errorMessage = 'Incorrect or expired code.';
          _isVerifying = false;
        });
        _hiddenController.clear();
        _focusNode.requestFocus();
      }
      // On success: StreamBuilder in main.dart detects codeVerified == true and routes to HomeScreen.
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Verification failed. Please try again.';
          _isVerifying = false;
        });
        _hiddenController.clear();
        _focusNode.requestFocus();
      }
    }
  }

  void _startCooldown() {
    setState(() => _cooldownSeconds = _kResendCooldown);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _cooldownSeconds--;
        if (_cooldownSeconds <= 0) t.cancel();
      });
    });
  }

  Future<void> _resendCode() async {
    if (_isSending || _cooldownSeconds > 0) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    HapticFeedback.selectionClick();
    setState(() { _isSending = true; _errorMessage = null; });

    try {
      await _authService.sendVerificationCode(user.uid, user.email ?? '');
      if (mounted) {
        _startCooldown();
        _hiddenController.clear();
        _focusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
        _startCooldown();
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _signOut() async {
    HapticFeedback.selectionClick();
    await _authService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email address';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg0,
        body: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _BgPainter())),
            // Hidden text field captures keyboard input
            Positioned(
              left: -999,
              top: -999,
              child: SizedBox(
                width: 1,
                height: 1,
                child: TextField(
                  controller: _hiddenController,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(counterText: ''),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _signOut,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
                                ),
                                child: Text(
                                  'Sign Out',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 13,
                                    fontFamily: '.SF Pro Display',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: GestureDetector(
                      onTap: () => _focusNode.requestFocus(),
                      behavior: HitTestBehavior.opaque,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 48, 28, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Icon badge
                            ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: _kAccent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(26),
                                    border: Border.all(color: _kAccent.withValues(alpha: 0.35), width: 0.8),
                                  ),
                                  child: const Icon(Icons.mark_email_unread_outlined, color: _kAccent, size: 36),
                                ),
                              ),
                            ),

                            const SizedBox(height: 32),

                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Colors.white, Color(0xFFB8AEFF)],
                                stops: [0.3, 1.0],
                              ).createShader(bounds),
                              child: const Text(
                                'Enter Code',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w200,
                                  color: Colors.white,
                                  letterSpacing: -1.5,
                                  fontFamily: '.SF Pro Display',
                                  height: 1.1,
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            Text(
                              'A 4-digit code was sent to',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.45), fontFamily: '.SF Pro Display'),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 15, color: _kAccent, fontFamily: '.SF Pro Display', fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.25), width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.orange.withValues(alpha: 0.7), size: 14),
                                  const SizedBox(width: 7),
                                  Text(
                                    'Check your spam / junk folder',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.withValues(alpha: 0.75), fontFamily: '.SF Pro Display'),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 40),

                            // OTP boxes
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(4, (i) {
                                final digit = i < _hiddenController.text.length ? _hiddenController.text[i] : '';
                                final isActive = i == _hiddenController.text.length && !_isVerifying;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 7),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 200),
                                        width: 62,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? _kAccent.withValues(alpha: 0.18)
                                              : Colors.white.withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isActive
                                                ? _kAccent.withValues(alpha: 0.70)
                                                : (_errorMessage != null
                                                    ? Colors.red.withValues(alpha: 0.55)
                                                    : Colors.white.withValues(alpha: 0.12)),
                                            width: isActive ? 1.2 : 0.5,
                                          ),
                                        ),
                                        child: Center(
                                          child: _isVerifying && digit.isEmpty
                                              ? SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(
                                                    color: Colors.white.withValues(alpha: 0.35),
                                                    strokeWidth: 1.5,
                                                  ),
                                                )
                                              : Text(
                                                  digit,
                                                  style: const TextStyle(
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                    fontFamily: '.SF Pro Display',
                                                    letterSpacing: -0.5,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),

                            const SizedBox(height: 16),

                            AnimatedOpacity(
                              opacity: _errorMessage != null ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                _errorMessage ?? '',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.red.withValues(alpha: 0.80),
                                  fontFamily: '.SF Pro Display',
                                ),
                              ),
                            ),

                            const SizedBox(height: 32),

                            // Resend button
                            ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 13,
                                            height: 13,
                                            child: CircularProgressIndicator(
                                              color: Colors.white.withValues(alpha: 0.25),
                                              strokeWidth: 1.5,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Tap anywhere to bring up keyboard',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.white.withValues(alpha: 0.35),
                                              fontFamily: '.SF Pro Display',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      _isSending
                                          ? const Center(
                                              child: SizedBox(
                                                height: 20,
                                                width: 20,
                                                child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 1.5),
                                              ),
                                            )
                                          : GestureDetector(
                                              onTap: _cooldownSeconds > 0 ? null : _resendCode,
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 280),
                                                padding: const EdgeInsets.symmetric(vertical: 16),
                                                decoration: BoxDecoration(
                                                  color: _cooldownSeconds > 0
                                                      ? _kAccent.withValues(alpha: 0.35)
                                                      : _kAccent,
                                                  borderRadius: BorderRadius.circular(16),
                                                  boxShadow: _cooldownSeconds > 0
                                                      ? []
                                                      : [
                                                          BoxShadow(
                                                            color: _kAccent.withValues(alpha: 0.35),
                                                            blurRadius: 24,
                                                            offset: const Offset(0, 6),
                                                          ),
                                                        ],
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    _cooldownSeconds > 0
                                                        ? 'RESEND IN ${_cooldownSeconds}s'
                                                        : 'RESEND CODE',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w700,
                                                      color: Colors.white,
                                                      letterSpacing: 0.8,
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
                          ],
                        ),
                      ),
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
}

class _BgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kBg0, _kBg1, _kBg0],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.srcOver
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.85),
          radius: 1.0,
          colors: [_kAccent.withValues(alpha: 0.13), Colors.transparent],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
