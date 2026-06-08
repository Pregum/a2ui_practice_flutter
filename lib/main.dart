import 'package:flutter/material.dart';

import 'ui/screen/demo_screen.dart';

void main() {
  runApp(const A2uiSupportDemoApp());
}

class A2uiSupportDemoApp extends StatelessWidget {
  const A2uiSupportDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A2UI Support Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3b6ef5),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFf5f6f8),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFe3e7ee)),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0.5,
        ),
        chipTheme: const ChipThemeData(
          side: BorderSide(color: Color(0xFFd5dae2)),
        ),
      ),
      home: const DemoScreen(),
    );
  }
}
