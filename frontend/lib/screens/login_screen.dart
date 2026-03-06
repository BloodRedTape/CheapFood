import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../cubit/auth_cubit.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegisterMode = false;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    final login = _loginController.text.trim();
    final password = _passwordController.text;
    if (login.isEmpty || password.isEmpty) return;
    if (_isRegisterMode) {
      context.read<AuthCubit>().register(login, password);
    } else {
      context.read<AuthCubit>().login(login, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: BlocBuilder<AuthCubit, AuthState>(
              builder: (context, state) {
                final isLoading = state is AuthLoading;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isRegisterMode ? 'Register' : 'Sign In',
                      style: ShadTheme.of(context).textTheme.h2,
                    ),
                    const SizedBox(height: 24),
                    ShadInput(
                      controller: _loginController,
                      placeholder: const Text('Login'),
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      controller: _passwordController,
                      placeholder: const Text('Password'),
                      obscureText: true,
                      enabled: !isLoading,
                      onSubmitted: (_) => _submit(context),
                    ),
                    if (state is AuthFailure) ...[
                      const SizedBox(height: 12),
                      ShadAlert.destructive(description: Text(state.message)),
                    ],
                    const SizedBox(height: 16),
                    ShadButton(
                      onPressed: isLoading ? null : () => _submit(context),
                      child: isLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_isRegisterMode ? 'Register' : 'Sign In'),
                    ),
                    const SizedBox(height: 12),
                    ShadButton.outline(
                      onPressed: isLoading
                          ? null
                          : () => setState(() {
                                _isRegisterMode = !_isRegisterMode;
                                _loginController.clear();
                                _passwordController.clear();
                              }),
                      child: Text(
                        _isRegisterMode ? 'Already have an account? Sign In' : "Don't have an account? Register",
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
