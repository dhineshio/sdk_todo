import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routes/routes.dart';

class OnboardingController extends GetxController {
  void continueToHome() async {
    try {
      final prefs = Get.find<SharedPreferences>();
      await prefs.setBool('onboarding_completed', true);
      Get.offNamed(XRoutes.home);
    } catch (e) {
      // If SharedPreferences is not available, just navigate to home
      // This can happen during initialization
      Get.offNamed(XRoutes.home);
    }
  }
}
