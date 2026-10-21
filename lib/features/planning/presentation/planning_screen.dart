import 'package:flutter/material.dart';

class PlanningScreen extends StatelessWidget {
  const PlanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planning')),
      body: const Center(
        child: Text(
          'Planning',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
        ),
      ),
    );
  }
}