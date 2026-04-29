import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'main_layout.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _rootIndex = 0;
  final GlobalKey<MainLayoutState> _mainKey = GlobalKey<MainLayoutState>();

  void _showMain() {
    if (_rootIndex != 1) {
      setState(() => _rootIndex = 1);
    }
    _mainKey.currentState?.notifyEnteredFromHome();
  }

  void _showHome() {
    if (_rootIndex == 0) return;
    setState(() => _rootIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _rootIndex,
      children: [
        HomeScreen(onEnterDirectory: _showMain),
        MainLayout(key: _mainKey, onExitToHome: _showHome),
      ],
    );
  }
}
