import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  double _cloudOpacity = 0.45;

  double get cloudOpacity => _cloudOpacity;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    double savedOpacity = prefs.getDouble('cloudOpacity') ?? 0.45;
    _cloudOpacity = savedOpacity.clamp(0.2, 0.45);
    notifyListeners();
  }

  Future<void> setCloudOpacity(double value) async {
    _cloudOpacity = value.clamp(0.2, 0.45);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cloudOpacity', _cloudOpacity);
  }
}
