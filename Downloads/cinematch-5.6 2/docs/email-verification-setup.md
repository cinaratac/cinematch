# E-posta doğrulama kurulumu

Uygulama, 6 haneli doğrulama e-postalarını Firebase Trigger Email uzantısının
dinlediği `mail` koleksiyonuna yazar. Kod istemciye dönmez; Cloud Functions
tarafında HMAC ile hash'lenerek en fazla 10 dakika saklanır.

## 1. OTP secret'ını tanımla

En az 32 karakterlik, rastgele ve yalnızca bu amaçla kullanılan bir değer
oluşturup Firebase Functions secret'ı olarak kaydet:

```bash
firebase functions:secrets:set EMAIL_OTP_HMAC_SECRET
```

Secret'ı kaynak koda, `.env` dosyasına veya istemci uygulamasına ekleme.

## 2. SMTP gönderimini bağla

Firebase'in resmi Trigger Email uzantısını kur:

```bash
firebase ext:install firebase/firestore-send-email --project movie-matching-8a836
```

Kurulum sorularında:

- E-posta belge koleksiyonu: `mail`
- SMTP bağlantısı: seçilen işlem e-postası sağlayıcısının güvenli SMTP URI'si
- Varsayılan gönderici: `CineMatch <team@cinematchsocial.com>`

Teslimatı yüksek hacimli kişisel Gmail hesabı yerine doğrulanmış alan adına
sahip bir işlem e-postası sağlayıcısıyla yapılandır.

## 3. Backend ve kuralları yayınla

```bash
firebase deploy --only functions:requestPasswordReset,functions:verifyPasswordResetCode,functions:completePasswordReset,functions:requestEmailVerificationCode,functions:verifyEmailVerificationCode,functions:cleanupEmailVerificationMail,functions:completeOnboarding,functions:cancelRegistration,firestore:rules
```

Trigger Email teslimatı `SUCCESS` veya `ERROR` durumuna ulaştığında
`cleanupEmailVerificationMail` kuyruk belgesini siler. Teslim edilmeden kalan
eski belgeler için `mail.expireAt` alanında Firestore TTL politikası açılması da
önerilir.
