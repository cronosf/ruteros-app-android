import 'package:flutter/material.dart';
import '../../core/terms_content.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terminos y condiciones')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(termsAndConditionsText, style: const TextStyle(height: 1.5)),
      ),
    );
  }
}
