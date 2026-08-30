import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final TextEditingController _pinCtrl = TextEditingController();
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _tryBiometrics();
  }

  Future<void> _tryBiometrics() async {
    final success = await AuthService.authenticateBiometric();
    if (success) {
      widget.onUnlocked();
    }
  }

  Future<void> _verifyPin() async {
    final savedPin = await AuthService.getSavedPin();
    if (_pinCtrl.text == savedPin) {
      widget.onUnlocked();
    } else {
      setState(() {
        _errorMsg = 'Código PIN incorreto!';
        _pinCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey[900],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/logo_rb.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.lock, size: 36, color: Colors.blueGrey),
                ),
              ),
              const SizedBox(height: 16),
              const Text('CCTV Motorista', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const Text('Aplicação Bloqueada', style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 24),
              TextField(
                controller: _pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, color: Colors.white, letterSpacing: 8),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'PIN',
                  hintStyle: const TextStyle(color: Colors.white38, letterSpacing: 0),
                  filled: true,
                  fillColor: Colors.white12,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _verifyPin(),
              ),
              if (_errorMsg.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_errorMsg, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _verifyPin,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[700]),
                    child: const Text('Entrar', style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.fingerprint, size: 32, color: Colors.white),
                    tooltip: 'Usar Biometria / Facial',
                    onPressed: _tryBiometrics,
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}