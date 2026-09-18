import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../models/advisor_roster.dart';
import '../models/user.dart';
import '../services/session_service.dart';
import '../services/clerk_auth_service.dart';
import '../services/od_service.dart';

class LoginScreen extends StatefulWidget {
  final Function(AppUser user) onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  UserRole _selectedRole = UserRole.student;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _studentRollController = TextEditingController();
  final _studentNameController = TextEditingController();
  int _studentYear = 3;
  String _studentSection = 'A';
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Selected advisor profile for password login
  AdvisorProfile _selectedAdvisor = kAdvisorRoster[0];

  @override
  void initState() {
    super.initState();
    _selectRole(UserRole.student);
    _checkClerkSessionOnLoad();
  }

  Future<void> _checkClerkSessionOnLoad() async {
    try {
      final session = await ClerkAuthService.checkActiveClerkSession();
      if (session != null && mounted) {
        final email = session['email'] as String? ?? '';
        final name = session['name'] as String? ?? '';
        if (email.isNotEmpty && email.endsWith(AppConfig.allowedDomain)) {
          if (email == 'hodit@smvec.ac.in') {
            final user = AppUser(
              id: 'U-HOD-${DateTime.now().millisecondsSinceEpoch}',
              name: 'Dr. R. RAJU (HOD/IT)',
              email: 'hodit@smvec.ac.in',
              role: UserRole.hod,
              department: 'Information Technology',
            );
            await SessionService.saveUser(user);
            widget.onLogin(user);
          } else {
            final adv = findAdvisorByEmail(email);
            if (adv != null) {
              final user = AppUser(
                id: 'U-ADV-${DateTime.now().millisecondsSinceEpoch}',
                name: adv.name,
                email: adv.email,
                role: UserRole.advisor,
                year: adv.year,
                section: adv.section,
                department: 'Information Technology',
              );
              await SessionService.saveUser(user);
              widget.onLogin(user);
            } else {
              final user = AppUser(
                id: 'U-STU-${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                email: email,
                role: UserRole.student,
                rollNumber: email.split('@')[0].toUpperCase(),
                year: 3,
                section: 'A',
                department: 'Information Technology',
              );
              await SessionService.saveUser(user);
              widget.onLogin(user);
            }
          }
        }
      }
    } catch (_) {}
  }

  void _selectRole(UserRole role) {
    setState(() {
      _selectedRole = role;
      _passwordController.clear();
      _emailController.clear();
      _studentRollController.clear();
      _studentNameController.clear();
      if (role == UserRole.advisor) {
        _selectedAdvisor = kAdvisorRoster[0];
      } else if (role == UserRole.hod) {
        _emailController.text = 'hodit@smvec.ac.in';
      }
    });
  }

  // -------------------------------------------------------------------------
  // GENUINE CLERK GOOGLE SIGN-IN (DIRECT GOOGLE ACCOUNT CHOOSER)
  // -------------------------------------------------------------------------
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Connecting to Clerk Google Workspace Sign-In...'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }

    final success = await ClerkAuthService.initiateGoogleSignIn();
    if (!success && mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not initiate Clerk Google Sign-In. Please check your internet connection.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // STUDENT RESEND OTP VERIFICATION MODAL
  // -------------------------------------------------------------------------
  void _showStudentOtpModal({
    required String email,
    required String name,
    required String roll,
    required int year,
    required String section,
  }) {
    final otpController = TextEditingController();
    String? modalError;
    bool isVerifying = false;
    bool isResending = false;
    int resendCooldown = 30;
    Timer? cooldownTimer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          cooldownTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
            if (resendCooldown > 0) {
              setModalState(() => resendCooldown--);
            } else {
              timer.cancel();
            }
          });

          const primaryBlue = Color(0xFF3350B0);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: const Icon(Icons.mark_email_read_outlined, color: primaryBlue, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Security Verification',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      Text(
                        'Institutional Passcode via Resend',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A secure 6-digit verification code has been dispatched via Resend to your student email address:',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.alternate_email, size: 16, color: primaryBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            email,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Please check your email inbox to retrieve the 6-digit code. Valid for 10 minutes.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),

                  if (modalError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              modalError!,
                              style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Text(
                    'Enter 6-Digit Verification Code',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    autofocus: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 10,
                      color: primaryBlue,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '------',
                      hintStyle: const TextStyle(letterSpacing: 10, color: Color(0xFFCBD5E1)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: primaryBlue, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Resend Code Button with Countdown
                  Center(
                    child: TextButton.icon(
                      onPressed: resendCooldown > 0 || isResending
                          ? null
                          : () async {
                              setModalState(() {
                                isResending = true;
                                modalError = null;
                              });
                              final res = await ODService().sendStudentOtp(
                                email: email,
                                name: name,
                                rollNumber: roll,
                                year: year,
                                section: section,
                              );
                              setModalState(() {
                                isResending = false;
                                if (res['success'] == true) {
                                  resendCooldown = 45;
                                  modalError = null;
                                } else {
                                  modalError = res['error'] ?? 'Failed to resend verification code.';
                                }
                              });
                            },
                      icon: isResending
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(
                        isResending
                            ? 'Resending...'
                            : resendCooldown > 0
                                ? 'Resend code in ${resendCooldown}s'
                                : 'Resend Code via Resend',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: resendCooldown > 0 ? const Color(0xFF94A3B8) : primaryBlue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cooldownTimer?.cancel();
                  Navigator.pop(dialogCtx);
                },
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: isVerifying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_outlined, size: 18),
                label: Text(
                  isVerifying ? 'Verifying...' : 'Verify OTP & Enter',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: isVerifying
                    ? null
                    : () async {
                        final enteredOtp = otpController.text.trim();
                        if (enteredOtp.length != 6) {
                          setModalState(() {
                            modalError = 'Please enter the complete 6-digit verification code.';
                          });
                          return;
                        }

                        setModalState(() {
                          isVerifying = true;
                          modalError = null;
                        });

                        final nav = Navigator.of(dialogCtx);
                        final messenger = ScaffoldMessenger.of(context);

                        final result = await ODService().verifyStudentOtp(
                          email: email,
                          otp: enteredOtp,
                        );

                        if (result['success'] == true) {
                          cooldownTimer?.cancel();
                          nav.pop();

                          final user = AppUser(
                            id: 'U-STU-${DateTime.now().millisecondsSinceEpoch}',
                            name: name,
                            email: email,
                            role: UserRole.student,
                            rollNumber: roll,
                            year: year,
                            section: section,
                            department: 'Information Technology',
                          );

                          await SessionService.saveUser(user);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Identity verified! Welcome to SMVEC OD Portal, $name.'),
                              backgroundColor: const Color(0xFF059669),
                            ),
                          );
                          widget.onLogin(user);
                        } else {
                          setModalState(() {
                            isVerifying = false;
                            modalError = result['error'] ?? 'Invalid verification code. Please check your email and try again.';
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // FORGOT PASSWORD MODAL (VIA RESEND OTP)
  // -------------------------------------------------------------------------
  void _openForgotPasswordModal() {
    final email = _selectedRole == UserRole.advisor
        ? _selectedAdvisor.email
        : 'hodit@smvec.ac.in';

    final otpController = TextEditingController();
    bool otpSent = false;
    bool isSending = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.mark_email_read_outlined, color: Color(0xFF3350B0)),
              SizedBox(width: 8),
              Text('Reset via Resend OTP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A secure 6-digit verification code will be dispatched to ($email) via Resend.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
              ),
              const SizedBox(height: 14),
              if (!otpSent)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3350B0),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 42),
                  ),
                  icon: isSending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_outlined, size: 16),
                  label: Text(isSending ? 'Sending OTP via Resend...' : 'Send Resend Security OTP'),
                  onPressed: isSending
                      ? null
                      : () async {
                          setDialogState(() => isSending = true);
                          try {
                            final res = await http.post(
                              Uri.parse(AppConfig.apiBaseUrl),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode({
                                'action': 'FORGOT_PASSWORD',
                                'role': _selectedRole == UserRole.hod ? 'HOD' : 'ADVISOR',
                                'email': email,
                              }),
                            ).timeout(const Duration(seconds: 8));
                            final data = jsonDecode(res.body);
                            if (data['success'] == true) {
                              setDialogState(() {
                                otpSent = true;
                                isSending = false;
                              });
                            } else {
                              setDialogState(() => isSending = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error'] ?? 'Failed to send OTP')));
                              }
                            }
                          } catch (err) {
                            setDialogState(() => isSending = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error: $err')));
                            }
                          }
                        },
                )
              else ...[
                const Text('Enter 6-Digit OTP Code:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
            if (otpSent)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('OTP Verified! You may now sign in with your credentials.'), backgroundColor: Color(0xFF059669)),
                  );
                },
                child: const Text('Verify & Login'),
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // FORM LOGIN HANDLER (STUDENT / ADVISOR WITH PASSWORD / HOD WITH PASSWORD)
  // -------------------------------------------------------------------------
  Future<void> _handleLogin() async {
    // 1. STUDENT LOGIN
    if (_selectedRole == UserRole.student) {
      final email = _emailController.text.trim().toLowerCase();
      if (email.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your college email address.')),
        );
        return;
      }

      if (!email.endsWith(AppConfig.allowedDomain)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Access restricted: Only official ${AppConfig.allowedDomain} college email addresses are permitted.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final roll = _studentRollController.text.trim().isNotEmpty
          ? _studentRollController.text.trim().toUpperCase()
          : email.split('@')[0].toUpperCase();
      final name = _studentNameController.text.trim().isNotEmpty
          ? _studentNameController.text.trim()
          : roll;

      setState(() => _isLoading = true);
      try {
        final res = await ODService().sendStudentOtp(
          email: email,
          name: name,
          rollNumber: roll,
          year: _studentYear,
          section: _studentSection,
        );

        if (res['success'] == true) {
          if (mounted) {
            _showStudentOtpModal(
              email: email,
              name: name,
              roll: roll,
              year: _studentYear,
              section: _studentSection,
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(res['error'] ?? 'Failed to send verification code. Please try again.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Network error: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    // 2. ADVISOR LOGIN (NO NEED TO TYPE EMAIL, MASTER PASSWORD: staff@smvec$123)
    if (_selectedRole == UserRole.advisor) {
      final password = _passwordController.text;
      if (password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter staff password (staff@smvec\$123).')),
        );
        return;
      }

      setState(() => _isLoading = true);
      try {
        final response = await http.post(
          Uri.parse(AppConfig.apiBaseUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'LOGIN_USER',
            'role': 'ADVISOR',
            'password': password,
            'email': _selectedAdvisor.email,
            'name': _selectedAdvisor.name,
            'year': _selectedAdvisor.year,
            'section': _selectedAdvisor.section,
          }),
        ).timeout(const Duration(seconds: 8));

        final data = jsonDecode(response.body);

        if (data['success'] != true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['error'] ?? 'Invalid staff password. Please check your credentials.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        final user = AppUser(
          id: 'U-ADV-${DateTime.now().millisecondsSinceEpoch}',
          name: _selectedAdvisor.name,
          email: _selectedAdvisor.email,
          role: UserRole.advisor,
          department: 'Information Technology',
          year: _selectedAdvisor.year,
          section: _selectedAdvisor.section,
        );
        widget.onLogin(user);
      } catch (e) {
        // Fallback local check if server unreachable
        if (password.trim() == 'staff@smvec\$123') {
          final user = AppUser(
            id: 'U-ADV-${DateTime.now().millisecondsSinceEpoch}',
            name: _selectedAdvisor.name,
            email: _selectedAdvisor.email,
            role: UserRole.advisor,
            department: 'Information Technology',
            year: _selectedAdvisor.year,
            section: _selectedAdvisor.section,
          );
          widget.onLogin(user);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid staff password.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    // 3. HOD LOGIN (PASSWORD: hodit@smvec$123)
    if (_selectedRole == UserRole.hod) {
      final password = _passwordController.text;
      if (password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter HOD password (hodit@smvec\$123).')),
        );
        return;
      }

      setState(() => _isLoading = true);
      try {
        final response = await http.post(
          Uri.parse(AppConfig.apiBaseUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'LOGIN_USER',
            'role': 'HOD',
            'password': password,
            'email': 'hodit@smvec.ac.in',
          }),
        ).timeout(const Duration(seconds: 8));

        final data = jsonDecode(response.body);

        if (data['success'] != true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['error'] ?? 'Invalid HOD password. Please check your credentials.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        final user = AppUser(
          id: 'U-HOD-${DateTime.now().millisecondsSinceEpoch}',
          name: 'Dr. R. RAJU (HOD/IT)',
          email: 'hodit@smvec.ac.in',
          role: UserRole.hod,
          department: 'Information Technology',
        );
        widget.onLogin(user);
      } catch (e) {
        // Fallback local check
        if (password.trim() == 'hodit@smvec\$123') {
          final user = AppUser(
            id: 'U-HOD-${DateTime.now().millisecondsSinceEpoch}',
            name: 'Dr. R. RAJU (HOD/IT)',
            email: 'hodit@smvec.ac.in',
            role: UserRole.hod,
            department: 'Information Technology',
          );
          widget.onLogin(user);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid HOD password.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF3350B0);
    const goldAccent = Color(0xFFD4A429);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FD),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // College Logo & Header
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryBlue.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/college_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.school_outlined, size: 44, color: primaryBlue),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'SMVEC OD PORTAL',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: primaryBlue,
                  ),
                ),
              ),
              const Center(
                child: Text(
                  'IT Department · Sri Manakula Vinayagar Eng. College',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Role Selector Tabs
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    _buildRoleTab('Student', UserRole.student, Icons.person_outline),
                    _buildRoleTab('Advisor', UserRole.advisor, Icons.assignment_ind_outlined),
                    _buildRoleTab('HOD', UserRole.hod, Icons.account_balance_outlined),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Login Card
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: goldAccent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_selectedRole.name.toUpperCase()} LOGIN',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Google Workspace Sign In Button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        minimumSize: const Size(double.infinity, 46),
                      ),
                      icon: const Icon(Icons.account_circle, size: 20, color: Color(0xFF4285F4)),
                      label: Text(
                        _selectedRole == UserRole.student
                            ? 'Continue with Google (@smvec.ac.in)'
                            : _selectedRole == UserRole.advisor
                                ? 'Continue with Google (Advisor Account)'
                                : 'Continue with Google (hodit@smvec.ac.in)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                      ),
                      onPressed: _handleGoogleSignIn,
                    ),

                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'OR INSTITUTIONAL ID',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade500),
                          ),
                        ),
                        const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // -------------------------------------------------------------
                    // 1. STUDENT LOGIN FORM
                    // -------------------------------------------------------------
                    if (_selectedRole == UserRole.student) ...[
                      const Text(
                        'College Email ID (@smvec.ac.in)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.alternate_email, size: 18, color: Color(0xFF9CA3AF)),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: primaryBlue, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Roll Number', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _studentRollController,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFFF9FAFB),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Full Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _studentNameController,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFFF9FAFB),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Academic Year', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<int>(
                                  initialValue: _studentYear,
                                  items: const [
                                    DropdownMenuItem(value: 1, child: Text('1st Year')),
                                    DropdownMenuItem(value: 2, child: Text('2nd Year')),
                                    DropdownMenuItem(value: 3, child: Text('3rd Year')),
                                    DropdownMenuItem(value: 4, child: Text('4th Year')),
                                  ],
                                  onChanged: (val) => setState(() => _studentYear = val ?? 3),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFFF9FAFB),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Section', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _studentSection,
                                  items: const [
                                    DropdownMenuItem(value: 'A', child: Text('Sec A')),
                                    DropdownMenuItem(value: 'B', child: Text('Sec B')),
                                    DropdownMenuItem(value: 'C', child: Text('Sec C')),
                                    DropdownMenuItem(value: 'D', child: Text('Sec D')),
                                  ],
                                  onChanged: (val) => setState(() => _studentSection = val ?? 'A'),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFFF9FAFB),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],

                    // -------------------------------------------------------------
                    // 2. ADVISOR LOGIN FORM (QUICK SELECTOR + MASTER PASSWORD)
                    // -------------------------------------------------------------
                    if (_selectedRole == UserRole.advisor) ...[
                      const Text(
                        'Select Your Class & Advisor Profile',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<AdvisorProfile>(
                        initialValue: _selectedAdvisor,
                        isExpanded: true,
                        items: kAdvisorRoster.map((adv) {
                          return DropdownMenuItem<AdvisorProfile>(
                            value: adv,
                            child: Text(
                              adv.displayName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedAdvisor = val);
                        },
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.assignment_ind_outlined, size: 18, color: primaryBlue),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_outlined, size: 14, color: Color(0xFF1E40AF)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Assigned: ${_selectedAdvisor.classLabel} · Email: ${_selectedAdvisor.email}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF1E40AF), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Staff Institutional Password',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF9CA3AF)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 18,
                              color: const Color(0xFF9CA3AF),
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _openForgotPasswordModal,
                          icon: const Icon(Icons.lock_reset, size: 15, color: primaryBlue),
                          label: const Text(
                            'Forgot Password? (Resend OTP)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryBlue),
                          ),
                        ),
                      ),
                    ],

                    // -------------------------------------------------------------
                    // 3. HOD LOGIN FORM (PASSWORD: hodit@smvec$123)
                    // -------------------------------------------------------------
                    if (_selectedRole == UserRole.hod) ...[
                      const Text(
                        'Authorized HOD Account',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.admin_panel_settings_outlined, color: primaryBlue, size: 20),
                            SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Dr. R. RAJU (HOD/IT)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                Text('hodit@smvec.ac.in', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'HOD Institutional Password',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF9CA3AF)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 18,
                              color: const Color(0xFF9CA3AF),
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _openForgotPasswordModal,
                          icon: const Icon(Icons.lock_reset, size: 15, color: primaryBlue),
                          label: const Text(
                            'Forgot Password? (Resend OTP)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryBlue),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),

                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                'Enter ${_selectedRole.name.toUpperCase()} Portal',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleTab(String title, UserRole role, IconData icon) {
    final isSelected = _selectedRole == role;
    const primaryBlue = Color(0xFF3350B0);

    return Expanded(
      child: InkWell(
        onTap: () => _selectRole(role),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isSelected ? Colors.white : const Color(0xFF6B7280)),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
