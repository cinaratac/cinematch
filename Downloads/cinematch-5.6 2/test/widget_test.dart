import 'package:flutter_test/flutter_test.dart';
import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:fluttergirdi/services/registration_state.dart';

void main() {
  test('Letterboxd cache kayıtları CDN posterini yeniden kullanmaz', () {
    final film = LetterboxdFilm.fromMap({
      'title': 'Saturday Night',
      'url': 'https://letterboxd.com/film/saturday-night-2024/',
      'posterUrl': 'https://a.ltrbxd.com/resized/film-poster/example-crop.jpg',
      'year': 2024,
    });

    expect(film.key, 'film:saturday-night-2024');
    expect(film.posterUrl, isEmpty);
    expect(film.year, 2024);
  });

  test('TMDB katalog anahtarı kararlı üretilir', () {
    expect(CatalogService.canonicalKeyFromTmdb(1010683), 'tmdb:1010683');
  });

  group('kayıt durumu', () {
    test('yalnızca Firebase Auth oturumu tamamlanmış kayıt sayılmaz', () {
      expect(RegistrationState.resolve(), RegistrationStage.profile);
    });

    test('sözleşmeli özel taslak onboarding ekranına döner', () {
      expect(
        RegistrationState.resolve(
          draftData: {'displayName': 'cinema_user', 'termsAccepted': true},
        ),
        RegistrationStage.onboarding,
      );
    });

    test('doğrulanmamış e-posta kaydı kod ekranına gider', () {
      expect(
        RegistrationState.resolve(
          draftData: {
            'displayName': 'cinema_user',
            'termsAccepted': true,
            'authProvider': 'email',
          },
        ),
        RegistrationStage.emailVerification,
      );
    });

    test('doğrulanmış e-posta kaydı ortak onboarding aşamasına gider', () {
      expect(
        RegistrationState.resolve(
          draftData: {
            'displayName': 'cinema_user',
            'termsAccepted': true,
            'authProvider': 'email',
            'emailVerified': true,
          },
        ),
        RegistrationStage.onboarding,
      );
    });

    test('Google ve Apple kayıtları kod ekranını atlar', () {
      for (final provider in ['google', 'apple']) {
        expect(
          RegistrationState.resolve(
            draftData: {
              'displayName': 'cinema_user',
              'termsAccepted': true,
              'authProvider': provider,
            },
          ),
          RegistrationStage.onboarding,
          reason: '$provider kaydı ortak onboarding aşamasına gitmeli',
        );
      }
    });

    test('active işareti zorunlu alanlar olmadan uygulamayı açmaz', () {
      expect(
        RegistrationState.resolve(
          userData: {
            'displayName': 'cinema_user',
            'termsAccepted': true,
            'registrationStatus': 'active',
            'onboardingCompleted': true,
          },
        ),
        RegistrationStage.onboarding,
      );
    });

    test('sunucuda tamamlanmış profil uygulamayı açar', () {
      expect(
        RegistrationState.resolve(
          userData: {
            'displayName': 'cinema_user',
            'termsAccepted': true,
            'age': 24,
            'registrationStatus': 'active',
            'onboardingCompleted': true,
          },
        ),
        RegistrationStage.complete,
      );
    });
  });
}
