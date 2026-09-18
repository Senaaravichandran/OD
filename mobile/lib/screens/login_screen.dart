import 'package:flutter/material.dart';
import '../models/user.dart';

class LoginScreen extends StatefulWidget {
  final Function(AppUser user) onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  UserRole _selectedRole = UserRole.student;
  final _emailController = TextEditingController(text: 'aravindhan.21it@smvec.ac.in');
  final _passwordController = TextEditingController(text: 'password123');
  bool _obscurePassword = true;

  void _selectRole(UserRole role) {
    setState(() {
      _selectedRole = role;
      switch (role) {
        case UserRole.student:
          _emailController.text = 'aravindhan.21it@smvec.ac.in';
          break;
        case UserRole.advisor:
          _emailController.text = 'advisor.it3a@smvec.ac.in';
          break;
        case UserRole.hod:
          _emailController.text = 'hod.it@smvec.ac.in';
          break;
      }
    });
  }

  void _handleLogin() {
    AppUser user;
    switch (_selectedRole) {
      case UserRole.student:
        user = AppUser(
          id: 'U-STU-1',
          name: 'Aravindhan S',
          email: _emailController.text,
          role: UserRole.student,
          rollNumber: '21IT101',
          year: 3,
          section: 'A',
          department: 'Information Technology',
        );
        break;
      case UserRole.advisor:
        user = AppUser(
          id: 'U-ADV-1',
          name: 'Dr. K. Senthil',
          email: _emailController.text,
          role: UserRole.advisor,
          department: 'Information Technology',
          year: 3,
          section: 'A',
        );
        break;
      case UserRole.hod:
        user = AppUser(
          id: 'U-HOD-1',
          name: 'Dr. R. RAJU',
          email: _emailController.text,
          role: UserRole.hod,
          department: 'Information Technology',
        );
        break;
    }
    widget.onLogin(user);
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
              const SizedBox(height: 24),
              // College Logo & Header
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryBlue.withOpacity(0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/college_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.school, size: 48, color: primaryBlue),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'SMVEC OD MANAGER',
                  style: TextStyle(
                    fontSize: 22,
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
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 32),

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
              const SizedBox(height: 24),

              // Login Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Email Field
                    const Text(
                      'College Email ID',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.alternate_email, size: 20, color: Color(0xFF9CA3AF)),
                        hintText: 'name.roll@smvec.ac.in',
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Password Field
                    const Text(
                      'Password / SSO Key',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline, size: 20, color: Color(0xFF9CA3AF)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            size: 20,
                            color: const Color(0xFF9CA3AF),
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        hintText: '••••••••',
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _handleLogin,
                        child: Text(
                          'Enter ${_selectedRole.name.toUpperCase()} Portal',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Reference Architecture Note
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryBlue.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_outlined, color: primaryBlue, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '2-Tier Approval Architecture',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primaryBlue),
                          ),
                          Text(
                            'Student ➔ Class Advisor Review ➔ HOD Final Decision',
                            style: TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
                          ),
                        ],
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? Colors.white : const Color(0xFF6B7280)),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
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
