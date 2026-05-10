import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_service.dart';

const _kBg0 = Color(0xFF0A0A14);
const _kBg1 = Color(0xFF141428);
const _kAccent = Color(0xFF6E5CFF);
const _kResendCooldown = 60;

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _authService = AuthService();

  // Step 0 = email input, 1 = OTP entry, 2 = success
  int _step = 0;

  // Step 0
  final TextEditingController _emailController = TextEditingController();
  bool _isSendingCode = false;
  String _resolvedEmail = '';

  // Step 1
  final TextEditingController _hiddenController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _cooldownTimer;
  bool _isVerifying = false;
  int _cooldownSeconds = _kResendCooldown;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _hiddenController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _hiddenController.removeListener(_onCodeChanged);
    _hiddenController.dispose();
    _focusNode.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // ── Step 0 ──────────────────────────────────────────────────────────────────

  Future<void> _sendCode() async {
    final input = _emailController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email or username.')),
      );
      return;
    }
    setState(() => _isSendingCode = true);
    try {
      await _authService.sendPasswordResetCode(input);
      _resolvedEmail = input.contains('@') ? input : input;
      _startCooldown();
      if (mounted) {
        setState(() {
          _step = 1;
          _isSendingCode = false;
        });
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _focusNode.requestFocus();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
        setState(() => _isSendingCode = false);
      }
    }
  }

  // ── Step 1 ──────────────────────────────────────────────────────────────────

  void _onCodeChanged() {
    final text = _hiddenController.text;
    if (text.length == 4) _submitCode(text);
    if (mounted) setState(() => _codeError = null);
  }

  Future<void> _submitCode(String code) async {
    if (_isVerifying) return;
    setState(() { _isVerifying = true; _codeError = null; });
    try {
      final email = await _authService.verifyPasswordResetCode(
        _emailController.text.trim(),
        code,
      );
      _resolvedEmail = email;
      if (mounted) setState(() { _step = 2; _isVerifying = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _codeError = e.toString().replaceFirst('Exception: ', '');
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
    if (_cooldownSeconds > 0) return;
    setState(() { _codeError = null; });
    try {
      await _authService.sendPasswordResetCode(_emailController.text.trim());
      _startCooldown();
      _hiddenController.clear();
      if (mounted) _focusNode.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(() => _codeError = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  // ── Shared helpers ───────────────────────────────────────────────────────────

  Widget _backButton() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (_step == 0) {
          Navigator.pop(context);
        } else {
          setState(() {
            _step--;
            _hiddenController.clear();
            _codeError = null;
          });
        }
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
    );
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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg0,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _ForgotPainter())),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(children: [_backButton()]),
                ),
                Expanded(
                  child: _step == 0
                      ? _buildEmailStep()
                      : _step == 1
                          ? _buildCodeStep()
                          : _buildSuccessStep(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 0: email input ──────────────────────────────────────────────────────

  Widget _buildEmailStep() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFB8AEFF)], stops: [0.3, 1.0],
            ).createShader(bounds),
            child: const Text(
              'Forgot\nPassword',
              style: TextStyle(
                fontSize: 38, fontWeight: FontWeight.w200, color: Colors.white,
                letterSpacing: -1.5, fontFamily: '.SF Pro Display', height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Enter your email or username and we'll send a verification code.",
            style: TextStyle(
              fontSize: 13, color: Colors.white.withValues(alpha: 0.45),
              fontFamily: '.SF Pro Display',
            ),
          ),
          const SizedBox(height: 36),
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white, fontFamily: '.SF Pro Display'),
                      onSubmitted: (_) => _sendCode(),
                      decoration: _fieldDecor('Email or Username', Icons.alternate_email_rounded),
                    ),
                    const SizedBox(height: 22),
                    _isSendingCode
                        ? const Center(child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 1.5))
                        : GestureDetector(
                            onTap: _sendCode,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: _kAccent,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [BoxShadow(color: _kAccent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 6))],
                              ),
                              child: const Center(
                                child: Text(
                                  'SEND CODE',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.8, fontFamily: '.SF Pro Display'),
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
    );
  }

  // ── Step 1: OTP entry ────────────────────────────────────────────────────────

  Widget _buildCodeStep() {
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          // Hidden keyboard capture
          Positioned(
            left: -999, top: -999,
            child: SizedBox(
              width: 1, height: 1,
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
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon badge
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: _kAccent.withValues(alpha: 0.35), width: 0.8),
                      ),
                      child: const Icon(Icons.lock_reset_rounded, color: _kAccent, size: 36),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFB8AEFF)], stops: [0.3, 1.0],
                  ).createShader(bounds),
                  child: const Text(
                    'Enter Code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 38, fontWeight: FontWeight.w200, color: Colors.white,
                      letterSpacing: -1.5, fontFamily: '.SF Pro Display',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'A 4-digit code was sent to',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.45), fontFamily: '.SF Pro Display'),
                ),
                const SizedBox(height: 4),
                Text(
                  _emailController.text.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: _kAccent, fontFamily: '.SF Pro Display', fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 36),

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
                            width: 62, height: 72,
                            decoration: BoxDecoration(
                              color: isActive ? _kAccent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isActive
                                    ? _kAccent.withValues(alpha: 0.70)
                                    : (_codeError != null
                                        ? Colors.red.withValues(alpha: 0.55)
                                        : Colors.white.withValues(alpha: 0.12)),
                                width: isActive ? 1.2 : 0.5,
                              ),
                            ),
                            child: Center(
                              child: _isVerifying && digit.isEmpty
                                  ? SizedBox(
                                      width: 18, height: 18,
                                      child: CircularProgressIndicator(color: Colors.white.withValues(alpha: 0.35), strokeWidth: 1.5),
                                    )
                                  : Text(
                                      digit,
                                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: '.SF Pro Display', letterSpacing: -0.5),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 14),
                AnimatedOpacity(
                  opacity: _codeError != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _codeError ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.red.withValues(alpha: 0.80), fontFamily: '.SF Pro Display'),
                  ),
                ),

                const SizedBox(height: 30),

                // Resend card
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
                      ),
                      child: GestureDetector(
                        onTap: _cooldownSeconds > 0 ? null : _resendCode,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: _cooldownSeconds > 0 ? _kAccent.withValues(alpha: 0.35) : _kAccent,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _cooldownSeconds > 0 ? [] : [
                              BoxShadow(color: _kAccent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 6)),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _cooldownSeconds > 0 ? 'RESEND IN ${_cooldownSeconds}s' : 'RESEND CODE',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.8, fontFamily: '.SF Pro Display'),
                            ),
                          ),
                        ),
                      ),
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

  // ── Step 2: success ──────────────────────────────────────────────────────────

  Widget _buildSuccessStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.35), width: 0.8),
                ),
                child: const Icon(Icons.check_rounded, color: Colors.green, size: 38),
              ),
            ),
          ),
          const SizedBox(height: 28),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFB8AEFF)], stops: [0.3, 1.0],
            ).createShader(bounds),
            child: const Text(
              'Identity\nVerified',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 38, fontWeight: FontWeight.w200, color: Colors.white,
                letterSpacing: -1.5, fontFamily: '.SF Pro Display', height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'A password reset link has been sent to',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.45), fontFamily: '.SF Pro Display'),
          ),
          const SizedBox(height: 4),
          Text(
            _resolvedEmail,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: _kAccent, fontFamily: '.SF Pro Display', fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Click the link in that email to set your new password.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.35), fontFamily: '.SF Pro Display', height: 1.55),
          ),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5),
              ),
              child: const Text(
                'Back to Sign In',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: '.SF Pro Display'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForgotPainter extends CustomPainter {
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
        center: const Alignment(0.4, -0.9), radius: 1.0,
        colors: [_kAccent.withValues(alpha: 0.15), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
