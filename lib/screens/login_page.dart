import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/mera_theme.dart';

class DashboardLoginResult {
  const DashboardLoginResult({required this.profile});

  final Map<String, dynamic> profile;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});

  final ValueChanged<DashboardLoginResult> onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Enter your email address and password.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;

      if (user == null) {
        throw Exception('Unable to authenticate this account.');
      }

      final profile = await _supabase
          .from('staff_profiles')
          .select(
            'id, staff_number, full_name, role, active, '
            'dashboard_access, omc',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        await _supabase.auth.signOut();
        throw Exception('No staff profile is linked to this account.');
      }

      final active = profile['active'] == true;
      final role = profile['role']?.toString().trim().toUpperCase() ?? '';
      final dashboardAccess = profile['dashboard_access'] == true;

      if (!active) {
        await _supabase.auth.signOut();
        throw Exception('This account is inactive.');
      }

      final allowed =
          role == 'ADMIN' ||
          ((role == 'MERA' || role == 'OTHER' || role == 'OMC') &&
              dashboardAccess);

      if (!allowed) {
        await _supabase.auth.signOut();

        throw Exception(
          'This account is not authorized to access the dashboard.',
        );
      }

      if (!mounted) {
        return;
      }

      widget.onLogin(
        DashboardLoginResult(profile: Map<String, dynamic>.from(profile)),
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = error.toString().replaceFirst('Exception: ', '');

      setState(() {
        _errorMessage = message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MeraColors.background,
      body: Stack(
        children: [
          // MERA corporate header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 270,
              decoration: const BoxDecoration(
                color: MeraColors.green,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(34),
                  bottomRight: Radius.circular(34),
                ),
              ),
            ),
          ),

          // Subtle gold corporate accent
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 5,
              color: MeraColors.gold,
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 30,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      const Text(
                        'MALAWI ENERGY REGULATORY AUTHORITY',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.15,
                        ),
                      ),
                      const SizedBox(height: 22),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: MeraColors.border,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            38,
                            30,
                            38,
                            32,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Image.asset(
                                  'assets/images/mera_logo.png',
                                  height: 100,
                                  fit: BoxFit.contain,
                                ),
                              ),

                              const SizedBox(height: 20),

                              const Text(
                                'MERA FUEL CONTROL',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                  color: MeraColors.darkGreen,
                                ),
                              ),

                              const SizedBox(height: 5),

                              const Text(
                                'National Fuel Monitoring Dashboard',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: MeraColors.mutedText,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),

                              const SizedBox(height: 12),

                              Center(
                                child: Container(
                                  width: 58,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: MeraColors.gold,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 30),

                              const Text(
                                'Sign in to Dashboard',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: MeraColors.text,
                                ),
                              ),

                              const SizedBox(height: 14),

                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [
                                  AutofillHints.email,
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Email Address',
                                  prefixIcon: const Icon(
                                    Icons.email_outlined,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onSubmitted: (_) {
                                  if (!_loading) {
                                    _login();
                                  }
                                },
                              ),

                              const SizedBox(height: 16),

                              TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: const [
                                  AutofillHints.password,
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword =
                                            !_obscurePassword;
                                      });
                                    },
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) {
                                  if (!_loading) {
                                    _login();
                                  }
                                },
                              ),

                              if (_errorMessage != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(
                                      alpha: 0.06,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.withValues(
                                        alpha: 0.20,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 24),

                              SizedBox(
                                height: 52,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: MeraColors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                  ),
                                  onPressed: _loading ? null : _login,
                                  icon: _loading
                                      ? const SizedBox(
                                          width: 19,
                                          height: 19,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.login_rounded),
                                  label: Text(
                                    _loading
                                        ? 'SIGNING IN...'
                                        : 'SIGN IN',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 24),
                              const Divider(),
                              const SizedBox(height: 10),

                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.lock_outline,
                                    size: 14,
                                    color: MeraColors.mutedText,
                                  ),
                                  SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Authorized MERA Fuel Control users only',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: MeraColors.mutedText,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        'Malawi Energy Regulatory Authority',
                        style: TextStyle(
                          color: MeraColors.mutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}