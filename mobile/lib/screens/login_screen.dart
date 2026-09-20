import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api_client.dart';
import '../services/clerk_session.dart';

/// Bridges a completed Clerk sign-in into an app session.
///
/// Clerk has already verified who the person is, so all this does is trade the
/// Clerk session for an app session and report back whether a profile still
/// needs to be filled in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authState,
    required this.onLogin,
    required this.onNeedsRegistration,
    required this.onSignOut,
  });

  final ClerkAuthState authState;
  final Future<void> Function(AppUser user) onLogin;
  final void Function(String email, String regToken) onNeedsRegistration;
  final Future<void> Function() onSignOut;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _exchange();
  }

  Future<void> _exchange() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ClerkSession.exchange(widget.authState);
      if (!mounted) return;
      if (result.needsRegistration) {
        widget.onNeedsRegistration(result.email ?? '', result.regToken ?? '');
      } else {
        await widget.onLogin(result.user!);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Signing you in…'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                _error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _exchange, child: const Text('Try again')),
              TextButton(
                onPressed: () => widget.onSignOut(),
                child: const Text('Sign out and use another account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
