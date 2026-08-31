import 'package:flutter/material.dart';
import 'package:keepers/ui/home_screen.dart';

class KeepersApp extends StatelessWidget {
  const KeepersApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFFB8C38A);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Keepers',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF11130F),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
