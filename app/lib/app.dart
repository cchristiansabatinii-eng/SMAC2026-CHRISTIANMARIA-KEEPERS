import 'package:flutter/material.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/onboarding/presentation/startup_gate.dart';

class KeepersApp extends StatelessWidget {
  const KeepersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Keepers',
      theme: KeepersTheme.dark(),
      darkTheme: KeepersTheme.dark(),
      home: const StartupGate(),
    );
  }
}
