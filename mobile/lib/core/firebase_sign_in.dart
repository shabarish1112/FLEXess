import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase_identity.dart';

class FirebaseSignIn extends StatefulWidget {
  const FirebaseSignIn({
    super.key,
    required this.onAuthenticated,
    this.link = false,
    this.onBusyChanged,
  });
  final Future<void> Function() onAuthenticated;
  final bool link;
  final ValueChanged<bool>? onBusyChanged;
  @override
  State<FirebaseSignIn> createState() => _FirebaseSignInState();
}

class _FirebaseSignInState extends State<FirebaseSignIn> {
  final phone = TextEditingController(), code = TextEditingController();
  String country = '+91';
  String? verification, error;
  ConfirmationResult? confirmation;
  Timer? timer;
  int cooldown = 0, generation = 0;
  bool busy = false;

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  String safeError(Object e) => e is FirebaseAuthException
      ? switch (e.code) {
          'invalid-verification-code' => 'The code is incorrect. Try again.',
          'session-expired' ||
          'code-expired' => 'The code expired. Request a new one.',
          'too-many-requests' ||
          'quota-exceeded' => 'Too many attempts. Please try later.',
          'credential-already-in-use' ||
          'account-exists-with-different-credential' =>
            'This credential belongs to another account. Sign in with its existing method.',
          'provider-already-linked' => 'This method is already linked.',
          'popup-closed-by-user' ||
          'cancelled-popup-request' => 'Sign-in cancelled.',
          'invalid-phone-number' => 'Enter a valid international phone number.',
          'operation-not-allowed' || 'unauthorized-domain' =>
            'This sign-in method is not configured for this app.',
          _ =>
            'Authentication did not finish. Check your connection and try again.',
        }
      : 'Sign-in did not finish. Retry or continue as guest.';

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = safeError(e));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  void sent() {
    if (!mounted) return;
    setState(() {
      cooldown = 60;
      busy = false;
    });
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || cooldown <= 1) {
        t.cancel();
      }
      if (mounted) setState(() => cooldown = (cooldown - 1).clamp(0, 60));
    });
  }

  Future<void> sendCode() async {
    final entered = phone.text.trim();
    final number = entered.startsWith('+') ? entered : '$country$entered';
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(number)) {
      setState(
        () => error = 'Choose a country code and enter 8–15 digits in total.',
      );
      return;
    }
    final attempt = ++generation;
    if (!FirebaseIdentity.allowsTestNumber(number)) {
      setState(
        () => error =
            'Real SMS is disabled. Phone sign-in accepts configured Firebase test numbers in development only.',
      );
      return;
    }
    sent();
    if (kIsWeb) {
      confirmation = widget.link
          ? await FirebaseIdentity.auth.currentUser!.linkWithPhoneNumber(number)
          : await FirebaseIdentity.auth.signInWithPhoneNumber(number);
      sent();
    } else {
      await FirebaseIdentity.auth.verifyPhoneNumber(
        phoneNumber: number,
        verificationCompleted: (credential) async {
          if (!mounted || attempt != generation) return;
          setState(() => busy = false);
          await run(() async {
            generation++;
            await FirebaseIdentity.credential(credential, link: widget.link);
            await widget.onAuthenticated();
          });
        },
        verificationFailed: (e) {
          if (mounted && attempt == generation) {
            setState(() {
              error = safeError(e);
              busy = false;
            });
          }
        },
        codeSent: (id, _) {
          if (!mounted || attempt != generation) return;
          verification = id;
          sent();
        },
        codeAutoRetrievalTimeout: (id) {
          if (mounted && attempt == generation) {
            setState(() => verification = id);
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (busy) const LinearProgressIndicator(),
      FilledButton.icon(
        onPressed: busy
            ? null
            : () => run(() async {
                generation++;
                await FirebaseIdentity.google(link: widget.link);
                await widget.onAuthenticated();
              }),
        icon: const Icon(Icons.login),
        label: Text(widget.link ? 'Link Google' : 'Continue with Google'),
      ),
      const SizedBox(height: 20),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: DropdownButtonFormField<String>(
              initialValue: country,
              decoration: const InputDecoration(labelText: 'Country'),
              items: const [
                '+91',
                '+1',
                '+44',
                '+61',
                '+49',
                '+33',
                '+81',
                '+971',
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: busy ? null : (s) => setState(() => country = s!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: phone,
              enabled: !busy,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: 'National number or full +country number',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Test numbers only. Real SMS verification is disabled under the ₹0 budget. Use the fictional number and code configured in the development Firebase console.',
      ),
      OutlinedButton(
        onPressed: busy || cooldown > 0 ? null : () => run(sendCode),
        child: Text(
          cooldown > 0 ? 'Retry in ${cooldown}s' : 'Request test code',
        ),
      ),
      if (verification != null || confirmation != null) ...[
        TextField(
          controller: code,
          enabled: !busy,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: '6-digit Firebase test code',
          ),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () => run(() async {
                  if (!RegExp(r'^\d{6}$').hasMatch(code.text)) {
                    setState(
                      () => error =
                          'Enter the six-digit code from your Firebase test configuration.',
                    );
                    return;
                  }
                  generation++;
                  if (kIsWeb) {
                    await confirmation!.confirm(code.text);
                  } else {
                    await FirebaseIdentity.credential(
                      PhoneAuthProvider.credential(
                        verificationId: verification!,
                        smsCode: code.text,
                      ),
                      link: widget.link,
                    );
                  }
                  await widget.onAuthenticated();
                }),
          child: const Text('Verify code'),
        ),
      ],
      if (error != null)
        Semantics(
          liveRegion: true,
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}
