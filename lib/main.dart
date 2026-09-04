import 'package:flutter/material.dart';
import 'ui/home_screen.dart';

void main() => runApp(const IriseusApp());

class IriseusApp extends StatelessWidget {
  const IriseusApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Iriseus',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomeScreen(),
    );
  }
}