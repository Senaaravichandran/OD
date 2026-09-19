import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../utils/validators.dart';

/// Login flow:
///  - Student: college email -> 6-digit code emailed to them -> (first time) name, register no, year, section.
///  - Staff:   college email + staff password -> (first time) name, year, section, batch.
///  - HOD:     HOD email + HOD password.
class LoginScreen extends StatefulWidget {
  final Future<void> Function(AppUser user) onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const primaryBlue = Color(0xFF3350B0);
  static const goldAccent = Color(0xFFD4A429);

  UserRole _role = UserRole.student;
  bool _otpStep = false; // student: waiting for the emailed code
  bool _registering = false; // first-time registration
  String? _regToken; // proof from the server that the student's email was verified
  int _resendIn = 0;
  Timer? _resendTimer;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _batchController = TextEditingController();
  final _otpController = TextEditingController();
  int? _year;
  String? _section;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _rollController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  void _selectRole(UserRole role) {
    if (_isLoading) return;
    setState(() {
      _role = role;
      _resetToStart();
      _emailController.clear();
      _passwordController.clear();
      _nameController.clear();
      _rollController.clear();
      _batchController.clear();
      _year = null;
      _section = null;
    });
  }

  void _resetToStart() {
    _otpStep = false;
    _registering = false;
    _regToken = null;
    _error = null;
    _otpController.clear();
    _resendTimer?.cancel();
    _resendIn = 0;
  }

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendIn <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  Future<void> _resendOtp() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.call('LOGIN', payload: {'role': 'STUDENT', 'email': _emailController.text.trim().toLowerCase()});
      _otpController.clear();
      _startResendCountdown((res['resendAfter'] as num?)?.toInt() ?? 60);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A new code has been sent to your email.')));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _roleKey => switch (_role) {
        UserRole.student => 'STUDENT',
        UserRole.advisor => 'STAFF',
        UserRole.hod => 'HOD',
      };

  String? _validateCredentials() {
    final email = _emailController.text.trim().toLowerCase();
    final emailError = validateCollegeEmail(email);
    if (emailError != null) return emailError;
    if (_role == UserRole.hod && email != AppConfig.hodEmail) {
      return 'Only the official HOD email (${AppConfig.hodEmail}) can sign in here.';
    }
    if (_role != UserRole.hod && email == AppConfig.hodEmail) {
      return 'Use the HOD tab to sign in with this email.';
    }
    if (_role != UserRole.student && _passwordController.text.trim().isEmpty) {
      return 'Enter your password.';
    }
    return null;
  }

  String? _validateRegistration() {
    if (_nameController.text.trim().isEmpty) return 'Enter your full name.';
    if (_role == UserRole.student && _rollController.text.trim().isEmpty) return 'Enter your register number.';
    if (_year == null) return 'Select the year.';
    if (_section == null) return 'Select the section.';
    if (_role == UserRole.advisor) return validateBatch(_batchController.text);
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final error = _registering
        ? _validateRegistration()
        : _otpStep
            ? (RegExp(r'^\d{6}$').hasMatch(_otpController.text.trim()) ? null : 'Enter the 6-digit code sent to your email.')
            : _validateCredentials();
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      'role': _roleKey,
      'email': _emailController.text.trim().toLowerCase(),
      if (_role != UserRole.student) 'password': _passwordController.text.trim(),
    };

    try {
      Map<String, dynamic> res;
      if (_registering) {
        payload.addAll({
          'name': _nameController.text.trim(),
          'year': _year,
          'section': _section,
          if (_role == UserRole.student) 'rollNumber': _rollController.text.trim(),
          if (_role == UserRole.student) 'regToken': _regToken,
          if (_role == UserRole.advisor) 'batch': _batchController.text.trim(),
        });
        res = await ApiClient.call('REGISTER', payload: payload);
      } else if (_otpStep) {
        res = await ApiClient.call('VERIFY_OTP', payload: {
          'email': payload['email'],
          'otp': _otpController.text.trim(),
        });
        if (res['needsRegistration'] == true) {
          _resendTimer?.cancel();
          setState(() {
            _otpStep = false;
            _registering = true;
            _regToken = res['regToken']?.toString();
            _isLoading = false;
          });
          return;
        }
      } else {
        res = await ApiClient.call('LOGIN', payload: payload);
        if (res['otpSent'] == true) {
          setState(() {
            _otpStep = true;
            _isLoading = false;
          });
          _startResendCountdown((res['resendAfter'] as num?)?.toInt() ?? 60);
          return;
        }
        if (res['needsRegistration'] == true) {
          setState(() {
            _registering = true;
            _isLoading = false;
          });
          return;
        }
      }

      final user = AppUser.fromJson(res['user'] as Map<String, dynamic>, res['token'].toString());
      await widget.onLogin(user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  InputDecoration _decoration({String? hint, IconData? icon, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
      suffixIcon: suffix,
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
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 12),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FD),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: primaryBlue.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 6)),
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: primaryBlue),
                ),
              ),
              const Center(
                child: Text(
                  'IT Department · Sri Manakula Vinayagar Eng. College',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 24),

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
                    _buildRoleTab('Staff', UserRole.advisor, Icons.assignment_ind_outlined),
                    _buildRoleTab('HOD', UserRole.hod, Icons.account_balance_outlined),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 8)),
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
                          decoration: BoxDecoration(color: goldAccent, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                          ),
                        ),
                        if (_registering || _otpStep)
                          TextButton(
                            onPressed: _isLoading ? null : () => setState(_resetToStart),
                            child: const Text('Back'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                    const SizedBox(height: 8),

                    if (_registering)
                      ..._buildRegistrationFields()
                    else if (_otpStep)
                      ..._buildOtpFields()
                    else
                      ..._buildCredentialFields(),

                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
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
                                _error!,
                                style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),
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
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _registering
                                    ? 'Register & Continue'
                                    : _otpStep
                                        ? 'Verify Code'
                                        : (_role == UserRole.student ? 'Send Code to Email' : 'Sign In'),
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

  String get _title {
    if (_registering) return _role == UserRole.student ? 'STUDENT REGISTRATION' : 'CLASS ADVISOR DETAILS';
    if (_otpStep) return 'EMAIL VERIFICATION';
    return switch (_role) {
      UserRole.student => 'STUDENT LOGIN',
      UserRole.advisor => 'STAFF LOGIN',
      UserRole.hod => 'HOD LOGIN',
    };
  }

  String get _subtitle {
    if (_registering) {
      return _role == UserRole.student
          ? 'First time here? Tell us your class so your OD reaches the right advisor.'
          : 'Enter the class you are Class Advisor for. Students will choose you when applying for OD.';
    }
    if (_otpStep) return 'We sent a 6-digit code to your college email. It is valid for 10 minutes.';
    return switch (_role) {
      UserRole.student => 'Sign in with your college email ID. A one-time code will be sent to it.',
      UserRole.advisor => 'Sign in with your official email ID and the staff password.',
      UserRole.hod => 'Sign in with the official HOD email ID and password.',
    };
  }

  List<Widget> _buildCredentialFields() {
    return [
      _label(_role == UserRole.hod ? 'Official HOD Email ID' : 'College Email ID (${AppConfig.allowedDomain})'),
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        textInputAction: _role == UserRole.student ? TextInputAction.done : TextInputAction.next,
        onSubmitted: _role == UserRole.student ? (_) => _submit() : null,
        decoration: _decoration(
          hint: _role == UserRole.hod ? AppConfig.hodEmail : 'yourname${AppConfig.allowedDomain}',
          icon: Icons.alternate_email,
        ),
      ),
      if (_role != UserRole.student) ...[
        _label(_role == UserRole.hod ? 'HOD Password' : 'Staff Password'),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: _decoration(
            icon: Icons.lock_outline,
            suffix: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 18,
                color: const Color(0xFF9CA3AF),
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildOtpFields() {
    return [
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 16, color: Color(0xFF1E40AF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _emailController.text.trim().toLowerCase(),
                style: const TextStyle(fontSize: 12, color: Color(0xFF1E40AF), fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      _label('Verification Code'),
      TextField(
        controller: _otpController,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 6,
        autofocus: true,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 10, color: primaryBlue),
        decoration: _decoration(hint: '------').copyWith(counterText: ''),
      ),
      const SizedBox(height: 6),
      Center(
        child: TextButton.icon(
          onPressed: _isLoading || _resendIn > 0 ? null : _resendOtp,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(
            _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      const Text(
        'Check your inbox and spam folder. Never share this code with anyone.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
      ),
    ];
  }

  List<Widget> _buildRegistrationFields() {
    return [
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF1E40AF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _emailController.text.trim().toLowerCase(),
                style: const TextStyle(fontSize: 12, color: Color(0xFF1E40AF), fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      _label('Full Name'),
      TextField(
        controller: _nameController,
        textCapitalization: TextCapitalization.words,
        decoration: _decoration(icon: Icons.badge_outlined),
      ),
      if (_role == UserRole.student) ...[
        _label('Register Number'),
        TextField(
          controller: _rollController,
          textCapitalization: TextCapitalization.characters,
          decoration: _decoration(icon: Icons.numbers),
        ),
      ],
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label(_role == UserRole.student ? 'Year' : 'Class Advisor for Year'),
                DropdownButtonFormField<int>(
                  initialValue: _year,
                  isExpanded: true,
                  hint: const Text('Select'),
                  items: AppConfig.years
                      .map((y) => DropdownMenuItem(value: y, child: Text(yearLabel(y))))
                      .toList(),
                  onChanged: (v) => setState(() => _year = v),
                  decoration: _decoration(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Section'),
                DropdownButtonFormField<String>(
                  initialValue: _section,
                  isExpanded: true,
                  hint: const Text('Select'),
                  items: AppConfig.sections
                      .map((s) => DropdownMenuItem(value: s, child: Text('Sec $s')))
                      .toList(),
                  onChanged: (v) => setState(() => _section = v),
                  decoration: _decoration(),
                ),
              ],
            ),
          ),
        ],
      ),
      if (_role == UserRole.advisor) ...[
        _label('Batch (e.g. 2023-2027)'),
        TextField(
          controller: _batchController,
          keyboardType: TextInputType.datetime,
          maxLength: 9,
          decoration: _decoration(hint: '2023-2027', icon: Icons.date_range_outlined).copyWith(counterText: ''),
        ),
      ],
    ];
  }

  Widget _buildRoleTab(String title, UserRole role, IconData icon) {
    final isSelected = _role == role;

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
