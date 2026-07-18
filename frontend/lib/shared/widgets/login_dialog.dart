import 'package:flutter/material.dart';
import 'package:ainas_frontend/services/user_service.dart';
import 'package:ainas_frontend/services/lic_service.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';

Future<bool> showLoginDialog(BuildContext context) async {
  final lic = LicService();
  if (!await lic.hasFeature(LicService.featureMultiuser)) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Multi-user features require a license with multiuser permission')),
    );
    return false;
  }

  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return const _LoginDialog();
        },
      ) ??
      false;
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _isRegisterMode = false;
  bool _isSubmitting = false;
  String? _errorText;
  String _selectedRole = 'user';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _errorText = null;
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorText = l10n.usernamePasswordRequired);
      return;
    }

    if (_isRegisterMode) {
      final confirm = _confirmPasswordController.text.trim();
      if (password != confirm) {
        setState(() => _errorText = l10n.passwordsDoNotMatch);
        return;
      }
      if (password.length < 4) {
        setState(() => _errorText = l10n.passwordTooShort);
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    if (_isRegisterMode) {
      final error = await UserService().register(
        username,
        password,
        role: _selectedRole,
      );
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _isSubmitting = false;
          _errorText = error;
        });
        return;
      }
      setState(() {
        _isRegisterMode = false;
        _isSubmitting = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.registrationSuccess)),
      );
    } else {
      final success = await UserService().login(username, password);
      if (!mounted) return;
      if (!success) {
        setState(() {
          _isSubmitting = false;
          _errorText = l10n.loginFailed;
        });
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(_isRegisterMode ? l10n.registerTitle : l10n.loginTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: l10n.usernameLabel,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n.passwordLabel,
            ),
          ),
          if (_isRegisterMode) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.confirmPasswordLabel,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: InputDecoration(
                labelText: l10n.roleLabel,
              ),
              items: [
                DropdownMenuItem(value: 'user', child: Text(l10n.roleUser)),
                DropdownMenuItem(value: 'admin', child: Text(l10n.roleAdmin)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _selectedRole = v);
              },
            ),
            if (_selectedRole == 'admin')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.adminRegisterOffline,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _isSubmitting ? null : _switchMode,
              child: Text(
                _isRegisterMode ? l10n.switchToLoginHint : l10n.switchToRegisterHint,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelButton),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                )
              : Text(_isRegisterMode ? l10n.registerButton : l10n.loginButton),
        ),
      ],
    );
  }
}
