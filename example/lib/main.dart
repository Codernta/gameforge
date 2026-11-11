import 'package:flutter/material.dart';

import 'src/coin_rush_screen.dart';

void main() {
  runApp(const CoinRushApp());
}

/// Root widget for the Coin Rush GameForge example game.
class CoinRushApp extends StatelessWidget {
  const CoinRushApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coin Rush — GameForge Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CoinRushScreen(),
    );
  }
}
