import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/splash_controller.dart';
import '../controllers/theme_controller.dart';
import '../controllers/todo_controller.dart';

/// Initial bindings that set up essential controllers when the app starts
/// Ensures theme, splash, and todo controllers are available throughout the app
class InitialBindings extends Bindings {
  @override
  void dependencies() async {
    // Set up core app controllers
    Get.put(XThemeController(), permanent: true); // Theme management
    Get.put(SplashController(), permanent: true); // Splash screen logic

    // Initialize todo controller with error handling - use lazy loading to avoid dependency issues
    Get.lazyPut(() => TodoController(), fenix: true);
  }
}
