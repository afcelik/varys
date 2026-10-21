import 'package:flutter/material.dart';

class VarysChatScreen extends StatelessWidget {
  const VarysChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Varys')),
      body: const Center(
        child: Text(
          'Varys',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
        ),
      ),
    );
  }
}