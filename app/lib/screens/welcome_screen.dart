import 'package:flutter/material.dart';
import 'package:sahara_app/screens/app_shell.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text( 'Welcome to Sahara', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold), textAlign: TextAlign.center, ),
              const SizedBox(height: 20),
              const Text( 'I am Aastha, an AI companion here to listen. Please remember, I am not a replacement for a medical professional. If you are in a crisis, please contact the national helpline at 14567.', style: TextStyle(fontSize: 16, height: 1.5), textAlign: TextAlign.center, ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const AppShell()),
                  );
                },
                child: const Text('I Understand, Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}