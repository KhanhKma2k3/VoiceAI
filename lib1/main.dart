import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'screens/tts_screen.dart';
import 'screens/stt_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bool loggedIn = await ApiService.isLoggedIn();
  runApp(MyApp(isLoggedIn: loggedIn));
}

class MyApp extends StatefulWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = false;
  Color _primaryColor = const Color(0xFF2563EB);

  void _toggleTheme(bool isDark) {
    setState(() {
      _isDarkMode = isDark;
    });
  }

  void _changePrimaryColor(Color color) {
    setState(() {
      _primaryColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Trợ Lý Âm Thanh',
      theme: AppTheme.getLightTheme(_primaryColor),
      darkTheme: AppTheme.getDarkTheme(_primaryColor),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: widget.isLoggedIn
          ? RootScreen(
        isDarkMode: _isDarkMode,
        primaryColor: _primaryColor,
        onToggleTheme: _toggleTheme,
        onChangeColor: _changePrimaryColor,
      )
          : const LoginScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  final bool isDarkMode;
  final Color primaryColor;
  final Function(bool) onToggleTheme;
  final Function(Color) onChangeColor;

  const RootScreen({
    super.key,
    required this.isDarkMode,
    required this.primaryColor,
    required this.onToggleTheme,
    required this.onChangeColor,
  });

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int currentIndex = 0;

  String _selectedVoice = 'vi-VN-HoaiMyNeural';
  double _selectedRate = 0.0;
  double _selectedPitch = 0.0;

  Future<void> _handleLogout() async {
    await ApiService.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🟢 TẠO TÍNH ĐỘNG THỜI THỜI CHO SCREENS VÀ SETTINGSSCREEN
    final List<Widget> screens = [
      ChatScreen(
        isDarkMode: widget.isDarkMode,
        primaryColor: widget.primaryColor,
        onToggleTheme: widget.onToggleTheme,
        onChangeColor: widget.onChangeColor,
      ),
      const TtsScreen(),
      const SttScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Trợ Lý Âm Thanh"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: "Cài đặt",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StatefulBuilder(
                    builder: (context, setModalState) {
                      return SettingsScreen(
                        currentVoice: _selectedVoice,
                        currentRate: _selectedRate,
                        currentPitch: _selectedPitch,
                        isDarkMode: widget.isDarkMode,
                        primaryColor: widget.primaryColor,
                        onSaveTts: (voice, rate, pitch) {
                          setState(() {
                            _selectedVoice = voice;
                            _selectedRate = rate;
                            _selectedPitch = pitch;
                          });
                        },
                        onToggleTheme: (isDark) {
                          widget.onToggleTheme(isDark);
                          setModalState(() {});
                        },
                        onChangeColor: (color) {
                          widget.onChangeColor(color);
                          setModalState(() {});
                        },
                        onLogout: _handleLogout,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: "Trợ lý AI",
          ),
          NavigationDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over),
            label: "Text to Speech",
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none_outlined),
            selectedIcon: Icon(Icons.mic),
            label: "Speech to Text",
          ),
        ],
      ),
    );
  }
}