// lib/screens/otp_login_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../service/auth_service.dart';

class OtpLoginScreen extends StatefulWidget {
  const OtpLoginScreen({super.key});
  @override
  State<OtpLoginScreen> createState() => _OtpLoginScreenState();
}

class _OtpLoginScreenState extends State<OtpLoginScreen> {
  final _auth = AuthService();
  final _emailPhoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isCodeSent = false;
  bool _isLoading = false;
  String? _error;

  Future<void> _sendOtp() async {
    final input = _emailPhoneController.text.trim();
    if (input.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      if (input.contains('@')) {
        await _auth.signInWithOtp(input);
      } else {
        await _auth.signInWithPhoneOtp(
          input.startsWith('+') ? input : '+380$input',
        );
      }
      setState(() => _isCodeSent = true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.length < 6) return;
    setState(() => _isLoading = true);
    try {
      final input = _emailPhoneController.text.trim();
      await _auth.verifyOtp(
        phone: _emailPhoneController.text,
        token: _otpController.text,
        type: input.contains('@') ? 'email' : 'sms',
      );
    } catch (e) {
      setState(() => _error = 'Invalid code');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login with OTP')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.message, size: 100, color: Colors.deepPurple),
            const SizedBox(height: 32),
            Text(
              _isCodeSent ? 'Enter verification code' : 'Enter email or phone',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _emailPhoneController,
              keyboardType: _isCodeSent
                  ? TextInputType.number
                  : TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: _isCodeSent ? 'Code' : 'Email or Phone (+380...)',
                prefixIcon: Icon(_isCodeSent ? Icons.lock : Icons.person),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _isCodeSent ? _verifyOtp() : _sendOtp(),
            ),
            if (!_isCodeSent) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendOtp,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Send Code'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '6-digit code',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _verifyOtp(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Verify'),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to email/password login'),
            ),
          ],
        ),
      ),
    );
  }
}
