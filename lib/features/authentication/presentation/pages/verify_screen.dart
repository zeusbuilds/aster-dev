import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../view_model/view_model.dart';

/// Verify screen
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, this.email});

  final String? email;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Handles verification form submission
  ///
  /// Validates form and triggers verification with email and code
  void _handleVerify() {
    if (_formKey.currentState?.validate() ?? false) {
      final email = widget.email;
      if (email == null || email.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email not found. Please login again.'),
            backgroundColor: Colors.red,
          ),
        );
        context.go(RoutePaths.login);
        return;
      }

      final code = _codeController.text.trim();
      ref.read(authViewModelProvider.notifier).verify(email, code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authViewModelProvider);
    final theme = Theme.of(context);

    // Listen to state changes
    ref.listen(authViewModelProvider, (previous, next) {
      if (next.isAuthenticated) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.successMessage ?? 'Verification successful!'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to home
        context.go(RoutePaths.skeleton);

        ref.read(authViewModelProvider.notifier).clearSuccess();
      }

      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.red,
          ),
        );
        ref.read(authViewModelProvider.notifier).clearError();
      }
    });

    return Scaffold(
      appBar: CustomAppBar(title: 'Verify', leadingIcon: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                Text(
                  'Enter Verification Code',
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Check your email for the verification code',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (widget.email != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.email!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 48),

                // Code Field
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Verification Code',
                    hintText: 'Enter the 6-digit code',
                    prefixIcon: Icon(Icons.security),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter the verification code';
                    }
                    if (value.length < 4) {
                      return 'Code must be at least 4 digits';
                    }
                    return null;
                  },
                  enabled: !authState.isLoading,
                ),
                const SizedBox(height: 32),

                // Verify Button
                ElevatedButton(
                  onPressed: authState.isLoading ? null : _handleVerify,
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
                const SizedBox(height: 16),

                // Back to Login
                TextButton(
                  onPressed: authState.isLoading
                      ? null
                      : () => context.go(RoutePaths.login),
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
