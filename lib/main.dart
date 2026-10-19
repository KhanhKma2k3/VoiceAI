import 'dart:io';

import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'screens/tts_screen.dart';
import 'screens/stt_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/pc_control_screen.dart';
import 'services/api_service.dart';
import 'pc_control/pc_control_bootstrap.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  final bool loggedIn = await ApiService.isLoggedIn();
  // Nếu đã đăng nhập sẵn (mở lại app), khởi động ngay tính năng Điều khiển
  // PC: bản Windows tự thành agent, bản khác tự thành controller.
  if (loggedIn) {
    PcControlBootstrap.start();
  }
  runApp(MyApp(isLoggedIn: loggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    final themeCtrl = ThemeController.instance;
    // Mỗi khi đổi dark mode / màu chủ đạo ở BẤT KỲ màn hình nào, MaterialApp
    // được dựng lại với theme mới.
    return ListenableBuilder(
      listenable: themeCtrl,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Trợ Lý Âm Thanh',
        theme: AppTheme.getLightTheme(themeCtrl.primaryColor),
        darkTheme: AppTheme.getDarkTheme(themeCtrl.primaryColor),
        themeMode: themeCtrl.isDark ? ThemeMode.dark : ThemeMode.light,
        home: isLoggedIn ? const RootScreen() : const LoginScreen(),
      ),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int currentIndex = 0;

  String _selectedVoice = 'vi-VN-HoaiMyNeural';
  double _selectedRate = 0.0;
  double _selectedPitch = 0.0;

  Future<void> _handleLogout() async {
    PcControlBootstrap.stop();
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
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final themeCtrl = ThemeController.instance;
    // 🟢 TẠO TÍNH ĐỘNG THỜI THỜI CHO SCREENS VÀ SETTINGSSCREEN
    // Tab "Điều khiển PC" chỉ có ý nghĩa trên bản KHÔNG PHẢI Windows: bản
    // Windows tự đóng vai trò agent chạy nền, không cần tự điều khiển chính nó.
    final bool showPcControlTab = !Platform.isWindows;

    final List<Widget> screens = [
      ChatScreen(
        isDarkMode: themeCtrl.isDark,
        primaryColor: themeCtrl.primaryColor,
        onToggleTheme: themeCtrl.setDark,
        onChangeColor: themeCtrl.setPrimaryColor,
        selectedVoice: _selectedVoice,
        selectedRate: _selectedRate,
        selectedPitch: _selectedPitch,
      ),
      TtsScreen(
        selectedVoice: _selectedVoice,
        selectedRate: _selectedRate,
        selectedPitch: _selectedPitch,
      ),
      const SttScreen(),
      if (showPcControlTab) const PcControlScreen(),
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
                        isDarkMode: ThemeController.instance.isDark,
                        primaryColor: ThemeController.instance.primaryColor,
                        onSaveTts: (voice, rate, pitch) {
                          setState(() {
                            _selectedVoice = voice;
                            _selectedRate = rate;
                            _selectedPitch = pitch;
                          });
                        },
                        onToggleTheme: (isDark) {
                          ThemeController.instance.setDark(isDark);
                          setModalState(() {});
                        },
                        onChangeColor: (color) {
                          ThemeController.instance.setPrimaryColor(color);
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
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: "Trợ lý AI",
          ),
          const NavigationDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over),
            label: "Text to Speech",
          ),
          const NavigationDestination(
            icon: Icon(Icons.mic_none_outlined),
            selectedIcon: Icon(Icons.mic),
            label: "Speech to Text",
          ),
          if (showPcControlTab)
            const NavigationDestination(
              icon: Icon(Icons.devices_outlined),
              selectedIcon: Icon(Icons.devices),
              label: "Điều khiển PC",
            ),
        ],
      ),
    );
  }
}