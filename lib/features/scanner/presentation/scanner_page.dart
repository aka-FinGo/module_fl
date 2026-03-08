import 'package:flutter/material.dart';

class ScannerPage extends StatelessWidget {
  const ScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Skanerlash')),
      body: const Center(
        child: Text('Native ML Kit Scanner kamerasi bu yerda bo\'ladi', style: TextStyle(fontSize: 16)),
      ),
    );
  }
}
