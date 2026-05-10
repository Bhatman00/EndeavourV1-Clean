import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_service.dart';

const _kBg0 = Color(0xFF0A0A14);
const _kBg1 = Color(0xFF141428);
const _kAccent = Color(0xFF6E5CFF);

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _oldController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _showOld = false;
  bool _showNew = false;
  bool _showConfirm = false;
  String? _errorMessage;
  bool _success = false;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final oldPw = _oldController.text;
    final newPw = _newController.text;
    final confirmPw = _confirmController.text;

    if (oldPw.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }
    if (newPw != confirmPw) {
      setState(() => _errorMessage = 'New passwords do not match.');
      return;
    }
    if (newPw.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters.');
      return;
    }

    HapticFeedback.selectionClick();
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      await _authService.reauthenticate(oldPw);
      await _authService.updatePassword(newPw);
      if (mounted) setState(() { _isLoading = false; _success = true; });
    } catch (e) {
      if (mounted) {
        String msg = e.toString().replaceFirst('Exception: ', '');
        if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
          msg = 'Current password is incorrect.';
        }
        setState(() { _isLoading = false; _errorMessage = msg; });
      }
    }
  }

  InputDecoration _fieldDecor(String label, IconData icon, bool visible, VoidCallback toggle) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      suffixIcon: GestureDetector(
        onTap: toggle,
        child: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white38, size: 20),
      ),
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _kBg0,
        body: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _BgPainter())),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () { HapticFeedback.selectionClick(); Navigator.pop(context); },
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
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
                      child: _success ? _buildSuccess() : _buildForm(),
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

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFB8AEFF)], stops: [0.3, 1.0],
          ).createShader(bounds),
          child: const Text(
            'Change\nPassword',
            style: TextStyle(
              fontSize: 38, fontWeight: FontWeight.w200, color: Colors.white,
              letterSpacing: -1.5, fontFamily: '.SF Pro Display', height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Enter your current password and choose a new one.',
          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.45), fontFamily: '.SF Pro Display'),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _oldController,
                    obscureText: !_showOld,
                    style: const TextStyle(color: Colors.white, fontFamily: '.SF Pro Display'),
                    decoration: _fieldDecor('Current Password', Icons.lock_outline_rounded, _showOld, () => setState(() => _showOld = !_showOld)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newController,
                    obscureText: !_showNew,
                    style: const TextStyle(color: Colors.white, fontFamily: '.SF Pro Display'),
                    decoration: _fieldDecor('New Password', Icons.lock_reset_rounded, _showNew, () => setState(() => _showNew = !_showNew)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: !_showConfirm,
                    style: const TextStyle(color: Colors.white, fontFamily: '.SF Pro Display'),
                    onSubmitted: (_) => _submit(),
                    decoration: _fieldDecor('Confirm New Password', Icons.lock_reset_rounded, _showConfirm, () => setState(() => _showConfirm = !_showConfirm)),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.25), width: 0.5),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(fontSize: 13, color: Colors.red.withValues(alpha: 0.85), fontFamily: '.SF Pro Display'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 1.5))
                      : GestureDetector(
                          onTap: _submit,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: _kAccent,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: _kAccent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 6))],
                            ),
                            child: const Center(
                              child: Text(
                                'UPDATE PASSWORD',
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
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
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
        const Text(
          'Password Updated',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Colors.white, fontFamily: '.SF Pro Display', letterSpacing: -0.5),
        ),
        const SizedBox(height: 10),
        Text(
          'Your password has been changed successfully.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.50), fontFamily: '.SF Pro Display', height: 1.6),
        ),
        const SizedBox(height: 36),
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
              'Done',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: '.SF Pro Display'),
            ),
          ),
        ),
      ],
    );
  }
}

class _BgPainter extends CustomPainter {
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
        center: const Alignment(-0.3, -0.9), radius: 1.0,
        colors: [_kAccent.withValues(alpha: 0.14), Colors.transparent],
      ).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
