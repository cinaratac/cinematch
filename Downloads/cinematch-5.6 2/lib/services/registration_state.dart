enum RegistrationStage { profile, emailVerification, onboarding, complete }

class RegistrationState {
  const RegistrationState._();

  static RegistrationStage resolve({
    Map<String, dynamic>? userData,
    Map<String, dynamic>? draftData,
  }) {
    if (_isComplete(userData)) return RegistrationStage.complete;
    final baseProfile = _hasAcceptedBaseProfile(draftData)
        ? draftData
        : (_hasAcceptedBaseProfile(userData) ? userData : null);
    if (baseProfile == null) return RegistrationStage.profile;
    if (_requiresEmailVerification(baseProfile)) {
      return RegistrationStage.emailVerification;
    }
    return RegistrationStage.onboarding;
  }

  static bool _isComplete(Map<String, dynamic>? data) {
    if (data == null) return false;
    final age = data['age'];
    final validAge = age is num && age >= 13 && age <= 120;
    if (!validAge || data['termsAccepted'] != true) return false;

    final explicitlyComplete =
        data['registrationStatus'] == 'active' &&
        data['onboardingCompleted'] == true;

    // Eski, durum alanları eklenmeden önce onboarding'i tamamlamış hesaplar.
    final legacyComplete = !data.containsKey('registrationStatus');
    return explicitlyComplete || legacyComplete;
  }

  static bool _hasAcceptedBaseProfile(Map<String, dynamic>? data) {
    if (data == null || data['termsAccepted'] != true) return false;
    final displayName = (data['displayName'] ?? '').toString().trim();
    return displayName.isNotEmpty;
  }

  static bool _requiresEmailVerification(Map<String, dynamic> data) {
    return data['authProvider'] == 'email' && data['emailVerified'] != true;
  }
}
