import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';

const _kAccent = Color(0xFF6E5CFF);

/// Glassmorphic re-authentication dialog.
///
/// Usage:
///   final confirmed = await ReauthDialog.show(context);
///   if (!confirmed) return; // user cancelled
///   // safe to call updatePassword / updateEmail / deleteUserAccount
///
/// Returns true if the user successfully re-authenticated, false if cancelled.
class ReauthDialog extends StatefulWidget {
  const ReauthDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.55),
          builder: (_) => const ReauthDialog(),
        ) ??
        false;
  }

  @override
  State<ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<ReauthDialog> {
  final AuthService _authService = AuthService();
  final TextEditingController _pwCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final pw = _pwCtrl.text;
    if (pw.isEmpty) {
      setState(() => _error = 'Please enter your current password.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _authService.reauthenticate(pw);
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.code == 'wrong-password'
              ? 'Incorrect password. Please try again.'
              : (e.message ?? 'Re-authentication failed.');
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Incorrect password. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                const Text(
                  'Confirm Identity',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: '.SF Pro Display',
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Re-enter your current password to continue.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.45),
                    fontFamily: '.SF Pro Display',
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 24),

                // Password field
                TextField(
                  controller: _pwCtrl,
                  obscureText: _obscure,
                  autofocus: true,
                  onSubmitted: (_) => _confirm(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: '.SF Pro Display',
                  ),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: Colors.white38,
                      size: 20,
                    ),
                    suffixIcon: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _obscure = !_obscure);
                      },
                      child: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white38,
                        size: 20,
                      ),
                    ),
                    labelText: 'Current Password',
                    labelStyle: const TextStyle(
                      color: Colors.white38,
                      fontFamily: '.SF Pro Display',
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: _kAccent.withValues(alpha: 0.6),
                        width: 0.8,
                      ),
                    ),
                  ),
                ),

                // Inline error
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFF6B6B),
                      fontFamily: '.SF Pro Display',
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Action row
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).pop(false);
                        },
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                              width: 0.5,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                fontFamily: '.SF Pro Display',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _isLoading ? null : _confirm,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color:
                                _isLoading ? _kAccent.withValues(alpha: 0.5) : _kAccent,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: _isLoading
                                ? []
                                : [
                                    BoxShadow(
                                      color: _kAccent.withValues(alpha: 0.35),
                                      blurRadius: 18,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Center(
                            child: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 1.5,
                                    ),
                                  )
                                : const Text(
                                    'Confirm',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: '.SF Pro Display',
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
}
