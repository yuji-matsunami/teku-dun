import 'package:flutter/material.dart';

import 'ui/health_page.dart';

class TekuDunApp extends StatelessWidget {
  const TekuDunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teku Dun',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3f51b5)),
        useMaterial3: true,
      ),
      home: const HealthPage(),
    );
  }
}
