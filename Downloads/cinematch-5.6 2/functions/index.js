/* eslint-disable */
const functions = require("firebase-functions/v1"); // v1 Triggerlar için
const { onCall, HttpsError } = require("firebase-functions/v2/https"); // v2 Callable fonksiyonlar için
const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require("crypto");
const sanitizeHtml = require("sanitize-html");

// Firebase Admin'i başlat
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const NEWS_ADMIN_UIDS = new Set([
  "RfpPtaZfaKYueG9b2dd2ASScqOO2",
  "ZkXr7PmQ4WV0iRIVR7uUUwfNS8N2",
  "mNCWixSnJSa6tE1hZs4iZwn3Du43",
]);

function cleanText(value, maxLength = 20000) {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, maxLength);
}

function makeSlug(value) {
  return cleanText(value, 160)
    .toLocaleLowerCase("tr-TR")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/ı/g, "i")
    .replace(/ğ/g, "g")
    .replace(/ü/g, "u")
    .replace(/ş/g, "s")
    .replace(/ö/g, "o")
    .replace(/ç/g, "c")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 120);
}

function normalizeOnboardingPeople(value) {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  return value.slice(0, 20).reduce((items, raw) => {
    if (!raw || typeof raw !== "object") return items;
    const id = Number(raw.id);
    const name = cleanText(raw.name, 100);
    if (!Number.isInteger(id) || id <= 0 || !name || seen.has(id)) return items;
    seen.add(id);
    const profilePath = cleanText(raw.profile_path, 200);
    items.push({
      id,
      name,
      profile_path: /^\/[A-Za-z0-9._-]+$/.test(profilePath) ? profilePath : null,
    });
    return items;
  }, []);
}

function onboardingProfilePhotoPath(uid) {
  return `profile_images/${uid}/avatar.jpg`;
}

function onboardingProfileBucket() {
  const projectId = cleanText(
    process.env.GCLOUD_PROJECT || admin.app().options.projectId,
    120
  );
  if (!/^[a-z0-9][a-z0-9-]{3,118}[a-z0-9]$/.test(projectId)) {
    throw new Error("firebase-project-id-unavailable");
  }
  return admin.storage().bucket(`${projectId}.firebasestorage.app`);
}

async function validateOnboardingProfilePhoto(uid, rawPath, rawUrl) {
  const expectedPath = onboardingProfilePhotoPath(uid);
  const profilePhotoPath = cleanText(rawPath, 240);
  const photoUrl = cleanText(rawUrl, 1600);
  if (profilePhotoPath !== expectedPath || !photoUrl) {
    throw new HttpsError(
      "invalid-argument",
      "Profil fotoğrafı yüklemeniz gerekiyor."
    );
  }

  try {
    const bucket = onboardingProfileBucket();
    const parsed = new URL(photoUrl);
    const match = parsed.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
    const objectPath = match ? decodeURIComponent(match[2]) : "";
    if (parsed.protocol !== "https:" ||
        parsed.hostname !== "firebasestorage.googleapis.com" ||
        !match ||
        decodeURIComponent(match[1]) !== bucket.name ||
        objectPath !== expectedPath ||
        parsed.searchParams.get("alt") !== "media" ||
        !parsed.searchParams.get("token")) {
      throw new Error("invalid-download-url");
    }

    const [metadata] = await bucket.file(expectedPath).getMetadata();
    const size = Number(metadata.size);
    const customMetadata = metadata.metadata || {};
    if (metadata.contentType !== "image/jpeg" ||
        !Number.isFinite(size) ||
        size <= 0 ||
        size > 5 * 1024 * 1024 ||
        customMetadata.ownerUid !== uid ||
        customMetadata.purpose !== "onboarding_profile") {
      throw new Error("invalid-image-metadata");
    }
  } catch (error) {
    console.error("Onboarding profil fotoğrafı doğrulanamadı:", uid, error.message);
    throw new HttpsError(
      "failed-precondition",
      "Profil fotoğrafı doğrulanamadı. Lütfen yeniden yükleyin."
    );
  }
  return { profilePhotoPath, photoURL: photoUrl };
}

const EMAIL_VERIFICATION_TTL_MS = 10 * 60 * 1000;
const EMAIL_VERIFICATION_RESEND_MS = 60 * 1000;
const EMAIL_VERIFICATION_WINDOW_MS = 60 * 60 * 1000;
const EMAIL_VERIFICATION_MAX_SENDS = 5;
const EMAIL_VERIFICATION_MAX_ATTEMPTS = 5;
const PASSWORD_RESET_RESEND_MS = 60 * 1000;
const PASSWORD_RESET_WINDOW_MS = 60 * 60 * 1000;
const PASSWORD_RESET_MAX_SENDS = 5;
const PASSWORD_RESET_OTP_TTL_MS = 10 * 60 * 1000;
const PASSWORD_RESET_SESSION_TTL_MS = 10 * 60 * 1000;
const PASSWORD_RESET_MAX_ATTEMPTS = 5;

function normalizedEmail(value) {
  return cleanText(value, 254).toLowerCase();
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (Number.isFinite(Number(value._seconds))) return Number(value._seconds) * 1000;
  return 0;
}

function authProviderIds(userRecord) {
  return new Set((userRecord.providerData || [])
    .map((provider) => cleanText(provider.providerId, 80))
    .filter(Boolean));
}

function hasTrustedFederatedEmail(userRecord) {
  const providers = authProviderIds(userRecord);
  if (providers.has("apple.com")) return true;
  return providers.has("google.com") && userRecord.emailVerified === true;
}

function emailOtpSecret() {
  const secret = process.env.EMAIL_OTP_HMAC_SECRET || "";
  if (secret.length < 32) {
    throw new HttpsError(
      "failed-precondition",
      "E-posta doğrulama servisi henüz yapılandırılmamış."
    );
  }
  return secret;
}

function hashEmailOtp(uid, email, code) {
  return crypto
    .createHmac("sha256", emailOtpSecret())
    .update(`${uid}:${email}:${code}`)
    .digest("hex");
}

function safeHashEquals(left, right) {
  if (!/^[a-f0-9]{64}$/.test(left) || !/^[a-f0-9]{64}$/.test(right)) {
    return false;
  }
  return crypto.timingSafeEqual(Buffer.from(left, "hex"), Buffer.from(right, "hex"));
}

function passwordResetRequestKey(email) {
  return crypto
    .createHash("sha256")
    .update(`password-reset:${email}`)
    .digest("hex");
}

function hashPasswordResetOtp(uid, email, code) {
  return crypto
    .createHmac("sha256", emailOtpSecret())
    .update(`password-reset:otp:${uid}:${email}:${code}`)
    .digest("hex");
}

function hashPasswordResetSession(token) {
  return crypto
    .createHash("sha256")
    .update(`password-reset:session:${token}`)
    .digest("hex");
}

exports.requestPasswordReset = onCall(
  { enforceAppCheck: true, secrets: ["EMAIL_OTP_HMAC_SECRET"] },
  async (request) => {
    let email = normalizedEmail(request.data && request.data.email);
    if (request.auth && request.auth.uid) {
      const authenticatedUser = await admin.auth().getUser(request.auth.uid);
      email = normalizedEmail(authenticatedUser.email);
    }
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new HttpsError("invalid-argument", "Geçerli bir e-posta adresi girin.");
    }

    const db = admin.firestore();
    const requestRef = db
      .collection("password_reset_requests")
      .doc(passwordResetRequestKey(email));
    let authUser = null;
    try {
      authUser = await admin.auth().getUserByEmail(email);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
    const eligible = authUser !== null &&
      authProviderIds(authUser).has("password") &&
      authUser.disabled !== true;
    const subjectUid = eligible ? authUser.uid : "missing";
    const code = crypto.randomInt(0, 1000000).toString().padStart(6, "0");
    const codeHash = hashPasswordResetOtp(subjectUid, email, code);
    const nowMs = Date.now();
    const now = admin.firestore.Timestamp.fromMillis(nowMs);
    const rateLimit = await db.runTransaction(async (transaction) => {
      const requestDoc = await transaction.get(requestRef);
      const previous = requestDoc.exists ? requestDoc.data() || {} : {};
      const previousSentAt = timestampMillis(previous.lastSentAt);
      const retryAfterMs = PASSWORD_RESET_RESEND_MS - (nowMs - previousSentAt);
      if (previousSentAt > 0 && retryAfterMs > 0) {
        return { allowed: false, retryAfterSeconds: Math.ceil(retryAfterMs / 1000) };
      }

      let windowStartedAtMs = timestampMillis(previous.windowStartedAt);
      let sentCount = Number(previous.sentCount) || 0;
      if (!windowStartedAtMs || nowMs - windowStartedAtMs >= PASSWORD_RESET_WINDOW_MS) {
        windowStartedAtMs = nowMs;
        sentCount = 0;
      }
      if (sentCount >= PASSWORD_RESET_MAX_SENDS) {
        throw new HttpsError(
          "resource-exhausted",
          "Saatlik şifre sıfırlama sınırına ulaştınız. Lütfen daha sonra tekrar deneyin."
        );
      }

      transaction.set(requestRef, {
        email,
        subjectUid,
        codeHash,
        codeExpiresAt: admin.firestore.Timestamp.fromMillis(
          nowMs + PASSWORD_RESET_OTP_TTL_MS
        ),
        attempts: 0,
        lastSentAt: now,
        windowStartedAt: admin.firestore.Timestamp.fromMillis(windowStartedAtMs),
        sentCount: sentCount + 1,
        sessionHash: admin.firestore.FieldValue.delete(),
        sessionExpiresAt: admin.firestore.FieldValue.delete(),
        verifiedAt: admin.firestore.FieldValue.delete(),
        expireAt: admin.firestore.Timestamp.fromMillis(
          nowMs + 24 * 60 * 60 * 1000
        ),
        updatedAt: now,
      }, { merge: true });
      return { allowed: true, retryAfterSeconds: 60 };
    });

    if (!rateLimit.allowed) {
      return { ok: true, ...rateLimit };
    }

    if (!eligible) {
      return { ok: true, sent: true, retryAfterSeconds: 60 };
    }

    const mailData = {
      to: email,
      category: "password_reset",
      expireAt: admin.firestore.Timestamp.fromMillis(
        nowMs + 24 * 60 * 60 * 1000
      ),
      message: {
        subject: "CineMatch şifre sıfırlama kodun",
        text: `CineMatch şifre sıfırlama kodun: ${code}. Kod 10 dakika geçerlidir. Bu isteği sen yapmadıysan kodu kimseyle paylaşma.`,
        html: `
          <div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px;color:#1f2937">
            <h2 style="color:#2E7D32">CineMatch</h2>
            <p>Şifreni yenilemek için aşağıdaki kodu uygulamaya gir:</p>
            <div style="font-size:34px;font-weight:700;letter-spacing:10px;padding:18px 0;color:#2E7D32">${code}</div>
            <p>Kod 10 dakika geçerlidir. Bu isteği sen yapmadıysan kodu kimseyle paylaşma.</p>
          </div>
        `,
      },
      createdAt: now,
    };
    if (request.auth && request.auth.uid === authUser.uid) {
      mailData.ownerUid = authUser.uid;
    }
    await db.collection("mail").add(mailData);
    return { ok: true, sent: true, retryAfterSeconds: 60 };
  }
);

exports.verifyPasswordResetCode = onCall(
  { enforceAppCheck: true, secrets: ["EMAIL_OTP_HMAC_SECRET"] },
  async (request) => {
    let email = normalizedEmail(request.data && request.data.email);
    if (request.auth && request.auth.uid) {
      const authenticatedUser = await admin.auth().getUser(request.auth.uid);
      email = normalizedEmail(authenticatedUser.email);
    }
    const code = cleanText(request.data && request.data.code, 6);
    if (!email || !/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "6 haneli kodu eksiksiz girin.");
    }

    let authUser;
    try {
      authUser = await admin.auth().getUserByEmail(email);
    } catch (error) {
      if (error.code === "auth/user-not-found") {
        throw new HttpsError("permission-denied", "Kod geçersiz veya süresi dolmuş.");
      }
      throw error;
    }
    if (!authProviderIds(authUser).has("password") || authUser.disabled === true) {
      throw new HttpsError("permission-denied", "Kod geçersiz veya süresi dolmuş.");
    }

    const db = admin.firestore();
    const requestRef = db
      .collection("password_reset_requests")
      .doc(passwordResetRequestKey(email));
    const sessionToken = crypto.randomBytes(32).toString("hex");
    const sessionHash = hashPasswordResetSession(sessionToken);
    const submittedHash = hashPasswordResetOtp(authUser.uid, email, code);
    const nowMs = Date.now();
    const now = admin.firestore.Timestamp.fromMillis(nowMs);
    const result = await db.runTransaction(async (transaction) => {
      const requestDoc = await transaction.get(requestRef);
      const data = requestDoc.exists ? requestDoc.data() || {} : {};
      const attempts = Number(data.attempts) || 0;
      const expired = timestampMillis(data.codeExpiresAt) <= nowMs;
      const validIdentity = data.subjectUid === authUser.uid &&
        normalizedEmail(data.email) === email;
      if (!requestDoc.exists || expired || !validIdentity ||
          attempts >= PASSWORD_RESET_MAX_ATTEMPTS) {
        return { verified: false, locked: attempts >= PASSWORD_RESET_MAX_ATTEMPTS };
      }
      if (!safeHashEquals(cleanText(data.codeHash, 64), submittedHash)) {
        const nextAttempts = attempts + 1;
        transaction.set(requestRef, {
          attempts: nextAttempts,
          updatedAt: now,
        }, { merge: true });
        return {
          verified: false,
          locked: nextAttempts >= PASSWORD_RESET_MAX_ATTEMPTS,
        };
      }

      transaction.set(requestRef, {
        sessionHash,
        sessionExpiresAt: admin.firestore.Timestamp.fromMillis(
          nowMs + PASSWORD_RESET_SESSION_TTL_MS
        ),
        verifiedAt: now,
        codeHash: admin.firestore.FieldValue.delete(),
        codeExpiresAt: admin.firestore.FieldValue.delete(),
        attempts: admin.firestore.FieldValue.delete(),
        updatedAt: now,
      }, { merge: true });
      return { verified: true, locked: false };
    });

    if (!result.verified) {
      throw new HttpsError(
        result.locked ? "resource-exhausted" : "permission-denied",
        result.locked
          ? "Çok fazla hatalı kod girildi. Yeni kod isteyin."
          : "Kod geçersiz veya süresi dolmuş."
      );
    }
    return { ok: true, resetToken: sessionToken };
  }
);

exports.completePasswordReset = onCall(
  { enforceAppCheck: true },
  async (request) => {
    let email = normalizedEmail(request.data && request.data.email);
    if (request.auth && request.auth.uid) {
      const authenticatedUser = await admin.auth().getUser(request.auth.uid);
      email = normalizedEmail(authenticatedUser.email);
    }
    const resetToken = cleanText(request.data && request.data.resetToken, 64);
    const rawPassword = request.data && request.data.newPassword;
    const newPassword = typeof rawPassword === "string" ? rawPassword : "";
    if (!email || !/^[a-f0-9]{64}$/.test(resetToken)) {
      throw new HttpsError("permission-denied", "Şifre yenileme oturumu geçersiz.");
    }
    if (newPassword.length < 8 || newPassword.length > 128) {
      throw new HttpsError(
        "invalid-argument",
        "Yeni şifre en az 8 karakter olmalıdır."
      );
    }

    let authUser;
    try {
      authUser = await admin.auth().getUserByEmail(email);
    } catch (error) {
      if (error.code === "auth/user-not-found") {
        throw new HttpsError("permission-denied", "Şifre yenileme oturumu geçersiz.");
      }
      throw error;
    }
    if (!authProviderIds(authUser).has("password") || authUser.disabled === true) {
      throw new HttpsError("permission-denied", "Şifre yenileme oturumu geçersiz.");
    }

    const db = admin.firestore();
    const requestRef = db
      .collection("password_reset_requests")
      .doc(passwordResetRequestKey(email));
    const submittedSessionHash = hashPasswordResetSession(resetToken);
    const nowMs = Date.now();
    const now = admin.firestore.Timestamp.fromMillis(nowMs);
    const authorized = await db.runTransaction(async (transaction) => {
      const requestDoc = await transaction.get(requestRef);
      const data = requestDoc.exists ? requestDoc.data() || {} : {};
      const valid = requestDoc.exists &&
        data.subjectUid === authUser.uid &&
        normalizedEmail(data.email) === email &&
        timestampMillis(data.sessionExpiresAt) > nowMs &&
        safeHashEquals(cleanText(data.sessionHash, 64), submittedSessionHash);
      if (!valid) return false;
      transaction.set(requestRef, {
        sessionHash: admin.firestore.FieldValue.delete(),
        processingHash: submittedSessionHash,
        processingStartedAt: now,
        updatedAt: now,
      }, { merge: true });
      return true;
    });
    if (!authorized) {
      throw new HttpsError("permission-denied", "Şifre yenileme oturumu geçersiz veya süresi dolmuş.");
    }

    try {
      await admin.auth().updateUser(authUser.uid, { password: newPassword });
      await admin.auth().revokeRefreshTokens(authUser.uid);
      await requestRef.delete();
    } catch (error) {
      await db.runTransaction(async (transaction) => {
        const requestDoc = await transaction.get(requestRef);
        const data = requestDoc.exists ? requestDoc.data() || {} : {};
        if (safeHashEquals(
          cleanText(data.processingHash, 64),
          submittedSessionHash
        ) && timestampMillis(data.sessionExpiresAt) > Date.now()) {
          transaction.set(requestRef, {
            sessionHash: submittedSessionHash,
            processingHash: admin.firestore.FieldValue.delete(),
            processingStartedAt: admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      });
      if (["auth/invalid-password", "auth/password-does-not-meet-requirements"]
        .includes(error.code)) {
        throw new HttpsError(
          "invalid-argument",
          "Bu şifre güvenlik koşullarını karşılamıyor. Daha güçlü bir şifre deneyin."
        );
      }
      throw error;
    }
    return { ok: true };
  }
);

exports.requestEmailVerificationCode = onCall(
  { secrets: ["EMAIL_OTP_HMAC_SECRET"] },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");

    const authUser = await admin.auth().getUser(uid);
    const email = normalizedEmail(authUser.email);
    if (!email) {
      throw new HttpsError("failed-precondition", "Hesapta doğrulanacak e-posta yok.");
    }

    const db = admin.firestore();
    const draftRef = db.collection("registration_drafts").doc(uid);
    const verificationRef = db.collection("email_verifications").doc(uid);
    const initialDraftDoc = await draftRef.get();
    const initialDraft = initialDraftDoc.exists ? initialDraftDoc.data() || {} : {};
    if (!initialDraftDoc.exists ||
        initialDraft.termsAccepted !== true ||
        cleanText(initialDraft.authProvider, 30) !== "email" ||
        normalizedEmail(initialDraft.email) !== email) {
      throw new HttpsError(
        "failed-precondition",
        "E-posta kayıt taslağı bulunamadı."
      );
    }
    if (hasTrustedFederatedEmail(authUser) || authUser.emailVerified === true) {
      await Promise.all([
        draftRef.set({
          emailVerified: true,
          emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }),
        verificationRef.set({
          email,
          verified: true,
          verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }),
      ]);
      return { ok: true, alreadyVerified: true };
    }

    if (!authProviderIds(authUser).has("password")) {
      throw new HttpsError(
        "permission-denied",
        "Bu hesap e-posta/şifre doğrulama akışını kullanamaz."
      );
    }

    const code = crypto.randomInt(0, 1000000).toString().padStart(6, "0");
    const codeHash = hashEmailOtp(uid, email, code);
    const mailRef = db.collection("mail").doc();
    const nowMs = Date.now();
    const now = admin.firestore.Timestamp.fromMillis(nowMs);
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      nowMs + EMAIL_VERIFICATION_TTL_MS
    );

    const result = await db.runTransaction(async (transaction) => {
      const [draftDoc, verificationDoc] = await Promise.all([
        transaction.get(draftRef),
        transaction.get(verificationRef),
      ]);
      const draft = draftDoc.exists ? draftDoc.data() || {} : {};
      if (!draftDoc.exists ||
          draft.termsAccepted !== true ||
          cleanText(draft.authProvider, 30) !== "email" ||
          normalizedEmail(draft.email) !== email) {
        throw new HttpsError(
          "failed-precondition",
          "E-posta kayıt taslağı bulunamadı."
        );
      }

      const previous = verificationDoc.exists ? verificationDoc.data() || {} : {};
      if (previous.verified === true && normalizedEmail(previous.email) === email) {
        transaction.set(draftRef, {
          emailVerified: true,
          emailVerifiedAt: previous.verifiedAt || now,
          updatedAt: now,
        }, { merge: true });
        return { sent: false, alreadyVerified: true, retryAfterSeconds: 0 };
      }

      const previousSentAt = timestampMillis(previous.lastSentAt);
      const retryAfterMs = EMAIL_VERIFICATION_RESEND_MS - (nowMs - previousSentAt);
      if (previousSentAt > 0 && retryAfterMs > 0) {
        return {
          sent: false,
          alreadyVerified: false,
          retryAfterSeconds: Math.ceil(retryAfterMs / 1000),
        };
      }

      let windowStartedAtMs = timestampMillis(previous.windowStartedAt);
      let sentCount = Number(previous.sentCount) || 0;
      if (!windowStartedAtMs || nowMs - windowStartedAtMs >= EMAIL_VERIFICATION_WINDOW_MS) {
        windowStartedAtMs = nowMs;
        sentCount = 0;
      }
      if (sentCount >= EMAIL_VERIFICATION_MAX_SENDS) {
        throw new HttpsError(
          "resource-exhausted",
          "Saatlik kod gönderme sınırına ulaştın. Lütfen daha sonra tekrar dene."
        );
      }

      transaction.set(verificationRef, {
        email,
        verified: false,
        codeHash,
        expiresAt,
        attempts: 0,
        lastSentAt: now,
        windowStartedAt: admin.firestore.Timestamp.fromMillis(windowStartedAtMs),
        sentCount: sentCount + 1,
        updatedAt: now,
      }, { merge: true });
      transaction.set(mailRef, {
        to: email,
        category: "email_verification",
        ownerUid: uid,
        expireAt: admin.firestore.Timestamp.fromMillis(
          nowMs + 24 * 60 * 60 * 1000
        ),
        message: {
          subject: "CineMatch e-posta doğrulama kodun",
          text: `CineMatch doğrulama kodun: ${code}. Kod 10 dakika geçerlidir.`,
          html: `
            <div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px;color:#1f2937">
              <h2 style="color:#2E7D32">CineMatch</h2>
              <p>E-posta adresini doğrulamak için aşağıdaki kodu uygulamaya gir:</p>
              <div style="font-size:34px;font-weight:700;letter-spacing:10px;padding:18px 0;color:#2E7D32">${code}</div>
              <p>Bu kod 10 dakika geçerlidir. Bu kaydı sen başlatmadıysan e-postayı yok sayabilirsin.</p>
            </div>
          `,
        },
        createdAt: now,
      });
      return { sent: true, alreadyVerified: false, retryAfterSeconds: 60 };
    });

    return { ok: true, ...result };
  }
);

exports.verifyEmailVerificationCode = onCall(
  { secrets: ["EMAIL_OTP_HMAC_SECRET"] },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");
    const code = cleanText(request.data && request.data.code, 6);
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "6 haneli doğrulama kodu gerekli.");
    }

    const authUser = await admin.auth().getUser(uid);
    const email = normalizedEmail(authUser.email);
    if (!email) {
      throw new HttpsError("failed-precondition", "Hesapta doğrulanacak e-posta yok.");
    }
    const submittedHash = hashEmailOtp(uid, email, code);
    const db = admin.firestore();
    const draftRef = db.collection("registration_drafts").doc(uid);
    const verificationRef = db.collection("email_verifications").doc(uid);
    const nowMs = Date.now();
    const now = admin.firestore.Timestamp.fromMillis(nowMs);

    const result = await db.runTransaction(async (transaction) => {
      const [draftDoc, verificationDoc] = await Promise.all([
        transaction.get(draftRef),
        transaction.get(verificationRef),
      ]);
      if (!draftDoc.exists || !verificationDoc.exists) {
        return { ok: false, reason: "not-started" };
      }
      const draft = draftDoc.data() || {};
      const verification = verificationDoc.data() || {};
      if (normalizedEmail(draft.email) !== email ||
          normalizedEmail(verification.email) !== email) {
        return { ok: false, reason: "email-mismatch" };
      }
      if (verification.verified === true) {
        transaction.set(draftRef, {
          emailVerified: true,
          emailVerifiedAt: verification.verifiedAt || now,
          updatedAt: now,
        }, { merge: true });
        return { ok: true, alreadyVerified: true };
      }

      const expiresAtMs = timestampMillis(verification.expiresAt);
      if (!expiresAtMs || expiresAtMs < nowMs) {
        return { ok: false, reason: "expired" };
      }
      const attempts = Math.max(0, Number(verification.attempts) || 0);
      if (attempts >= EMAIL_VERIFICATION_MAX_ATTEMPTS) {
        return { ok: false, reason: "locked" };
      }
      if (!safeHashEquals(cleanText(verification.codeHash, 64), submittedHash)) {
        const nextAttempts = attempts + 1;
        transaction.set(verificationRef, {
          attempts: nextAttempts,
          lastAttemptAt: now,
          updatedAt: now,
        }, { merge: true });
        return {
          ok: false,
          reason: nextAttempts >= EMAIL_VERIFICATION_MAX_ATTEMPTS
            ? "locked"
            : "invalid",
        };
      }

      transaction.set(verificationRef, {
        verified: true,
        verifiedAt: now,
        codeHash: admin.firestore.FieldValue.delete(),
        expiresAt: admin.firestore.FieldValue.delete(),
        attempts: admin.firestore.FieldValue.delete(),
        updatedAt: now,
      }, { merge: true });
      transaction.set(draftRef, {
        emailVerified: true,
        emailVerifiedAt: now,
        updatedAt: now,
      }, { merge: true });
      return { ok: true, alreadyVerified: false };
    });

    if (!result.ok) {
      if (result.reason === "expired") {
        throw new HttpsError("deadline-exceeded", "Kodun süresi dolmuş.");
      }
      if (result.reason === "locked") {
        throw new HttpsError(
          "resource-exhausted",
          "Çok fazla hatalı deneme yaptın. Yeni kod iste."
        );
      }
      if (result.reason === "invalid") {
        throw new HttpsError("invalid-argument", "Doğrulama kodu hatalı.");
      }
      throw new HttpsError(
        "failed-precondition",
        "Önce yeni bir doğrulama kodu istemelisin."
      );
    }

    await admin.auth().updateUser(uid, { emailVerified: true });
    return { ok: true, verified: true };
  }
);

const ACCOUNT_DELETION_OTP_TTL_MS = 10 * 60 * 1000;
const ACCOUNT_DELETION_AUTH_TTL_MS = 15 * 60 * 1000;
const ACCOUNT_DELETION_RECENT_AUTH_MS = 5 * 60 * 1000;
const ACCOUNT_DELETION_REASON_CODES = new Set([
  "privacy",
  "too_many_notifications",
  "not_useful",
  "technical_problems",
  "found_alternative",
  "taking_break",
  "other",
]);

function hashAccountDeletionOtp(uid, email, code) {
  return crypto
    .createHmac("sha256", emailOtpSecret())
    .update(`account-deletion:otp:${uid}:${email}:${code}`)
    .digest("hex");
}

function hashAccountDeletionAuthorization(uid, token) {
  return crypto
    .createHmac("sha256", emailOtpSecret())
    .update(`account-deletion:authorization:${uid}:${token}`)
    .digest("hex");
}

function assertRecentFederatedAuthentication(request, authUser) {
  const providers = authProviderIds(authUser);
  const federated = providers.has("google.com") || providers.has("apple.com");
  if (!federated) return;

  const authTimeSeconds = Number(request.auth && request.auth.token.auth_time);
  const authTimeMs = Number.isFinite(authTimeSeconds)
    ? authTimeSeconds * 1000
    : 0;
  if (!authTimeMs || Date.now() - authTimeMs > ACCOUNT_DELETION_RECENT_AUTH_MS) {
    throw new HttpsError(
      "unauthenticated",
      "Hesabı silmeden önce Google veya Apple hesabınla yeniden doğrulanmalısın."
    );
  }
}

function accountProviderTypes(authUser) {
  const providers = authProviderIds(authUser);
  const values = [];
  if (providers.has("google.com")) values.push("google");
  if (providers.has("apple.com")) values.push("apple");
  if (providers.has("password")) values.push("email");
  return values.length ? values : ["unknown"];
}

exports.requestAccountDeletionCode = onCall(
  { secrets: ["EMAIL_OTP_HMAC_SECRET"] },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");

    const authUser = await admin.auth().getUser(uid);
    const email = normalizedEmail(authUser.email);
    if (!email) {
      throw new HttpsError(
        "failed-precondition",
        "Hesabına bağlı bir e-posta adresi bulunamadı."
      );
    }
    assertRecentFederatedAuthentication(request, authUser);

    const db = admin.firestore();
    const verificationRef = db.collection("account_deletion_verifications").doc(uid);
    const mailRef = db.collection("mail").doc();
    const code = crypto.randomInt(0, 1000000).toString().padStart(6, "0");
    const codeHash = hashAccountDeletionOtp(uid, email, code);
    const nowMs = Date.now();
    const now = admin.firestore.Timestamp.fromMillis(nowMs);
    const expiresAt = admin.firestore.Timestamp.fromMillis(
      nowMs + ACCOUNT_DELETION_OTP_TTL_MS
    );

    const result = await db.runTransaction(async (transaction) => {
      const verificationDoc = await transaction.get(verificationRef);
      const previous = verificationDoc.exists ? verificationDoc.data() || {} : {};
      const previousSentAt = timestampMillis(previous.lastSentAt);
      const retryAfterMs = EMAIL_VERIFICATION_RESEND_MS - (nowMs - previousSentAt);
      if (previousSentAt > 0 && retryAfterMs > 0) {
        return {
          sent: false,
          retryAfterSeconds: Math.ceil(retryAfterMs / 1000),
        };
      }

      let windowStartedAtMs = timestampMillis(previous.windowStartedAt);
      let sentCount = Number(previous.sentCount) || 0;
      if (!windowStartedAtMs ||
          nowMs - windowStartedAtMs >= EMAIL_VERIFICATION_WINDOW_MS) {
        windowStartedAtMs = nowMs;
        sentCount = 0;
      }
      if (sentCount >= EMAIL_VERIFICATION_MAX_SENDS) {
        throw new HttpsError(
          "resource-exhausted",
          "Saatlik kod gönderme sınırına ulaştın. Lütfen daha sonra tekrar dene."
        );
      }

      transaction.set(verificationRef, {
        email,
        codeHash,
        expiresAt,
        attempts: 0,
        lastSentAt: now,
        windowStartedAt: admin.firestore.Timestamp.fromMillis(windowStartedAtMs),
        sentCount: sentCount + 1,
        sessionId: crypto.randomBytes(16).toString("hex"),
        providerTypes: accountProviderTypes(authUser),
        authorizedHash: admin.firestore.FieldValue.delete(),
        authorizedAt: admin.firestore.FieldValue.delete(),
        authorizedUntil: admin.firestore.FieldValue.delete(),
        processingStartedAt: admin.firestore.FieldValue.delete(),
        updatedAt: now,
      }, { merge: true });
      transaction.set(mailRef, {
        to: email,
        category: "account_deletion_verification",
        ownerUid: uid,
        expireAt: admin.firestore.Timestamp.fromMillis(
          nowMs + 24 * 60 * 60 * 1000
        ),
        message: {
          subject: "CineMatch hesap silme doğrulama kodun",
          text: `CineMatch hesap silme kodun: ${code}. Kod 10 dakika geçerlidir. Bu işlemi sen başlatmadıysan kodu kimseyle paylaşma.`,
          html: `
            <div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px;color:#1f2937">
              <h2 style="color:#c62828">CineMatch</h2>
              <p>Hesabını kalıcı olarak silme isteğini doğrulamak için aşağıdaki kodu uygulamaya gir:</p>
              <div style="font-size:34px;font-weight:700;letter-spacing:10px;padding:18px 0;color:#c62828">${code}</div>
              <p>Kod 10 dakika geçerlidir. Bu işlemi sen başlatmadıysan kodu kimseyle paylaşma; hesabın silinmeyecektir.</p>
            </div>
          `,
        },
        createdAt: now,
      });
      return { sent: true, retryAfterSeconds: 60 };
    });

    return {
      ok: true,
      email,
      providerTypes: accountProviderTypes(authUser),
      ...result,
    };
  }
);

exports.verifyAccountDeletionCode = onCall(
  { secrets: ["EMAIL_OTP_HMAC_SECRET"] },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");
    const code = cleanText(request.data && request.data.code, 6);
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "6 haneli doğrulama kodu gerekli.");
    }

    const authUser = await admin.auth().getUser(uid);
    const email = normalizedEmail(authUser.email);
    if (!email) {
      throw new HttpsError("failed-precondition", "Hesap e-postası bulunamadı.");
    }

    const db = admin.firestore();
    const verificationRef = db.collection("account_deletion_verifications").doc(uid);
    const submittedHash = hashAccountDeletionOtp(uid, email, code);
    const authorizationToken = crypto.randomBytes(32).toString("hex");
    const authorizationHash = hashAccountDeletionAuthorization(
      uid,
      authorizationToken
    );
    const nowMs = Date.now();
    const now = admin.firestore.Timestamp.fromMillis(nowMs);
    const result = await db.runTransaction(async (transaction) => {
      const verificationDoc = await transaction.get(verificationRef);
      if (!verificationDoc.exists) return { ok: false, reason: "not-started" };
      const verification = verificationDoc.data() || {};
      if (normalizedEmail(verification.email) !== email) {
        return { ok: false, reason: "email-mismatch" };
      }
      const expiresAtMs = timestampMillis(verification.expiresAt);
      if (!expiresAtMs || expiresAtMs < nowMs) {
        return { ok: false, reason: "expired" };
      }
      const attempts = Math.max(0, Number(verification.attempts) || 0);
      if (attempts >= EMAIL_VERIFICATION_MAX_ATTEMPTS) {
        return { ok: false, reason: "locked" };
      }
      if (!safeHashEquals(cleanText(verification.codeHash, 64), submittedHash)) {
        const nextAttempts = attempts + 1;
        transaction.set(verificationRef, {
          attempts: nextAttempts,
          lastAttemptAt: now,
          updatedAt: now,
        }, { merge: true });
        return {
          ok: false,
          reason: nextAttempts >= EMAIL_VERIFICATION_MAX_ATTEMPTS
            ? "locked"
            : "invalid",
        };
      }

      transaction.set(verificationRef, {
        authorizedHash: authorizationHash,
        authorizedAt: now,
        authorizedUntil: admin.firestore.Timestamp.fromMillis(
          nowMs + ACCOUNT_DELETION_AUTH_TTL_MS
        ),
        attempts: admin.firestore.FieldValue.delete(),
        processingStartedAt: admin.firestore.FieldValue.delete(),
        updatedAt: now,
      }, { merge: true });
      return { ok: true };
    });

    if (!result.ok) {
      if (result.reason === "expired") {
        throw new HttpsError("deadline-exceeded", "Kodun süresi dolmuş.");
      }
      if (result.reason === "locked") {
        throw new HttpsError(
          "resource-exhausted",
          "Çok fazla hatalı deneme yaptın. Yeni kod iste."
        );
      }
      if (result.reason === "invalid") {
        throw new HttpsError("invalid-argument", "Doğrulama kodu hatalı.");
      }
      throw new HttpsError(
        "failed-precondition",
        "Önce yeni bir hesap silme kodu istemelisin."
      );
    }
    return { ok: true, authorizationToken };
  }
);

async function deleteReferences(refs) {
  const unique = [...new Map(refs.map((ref) => [ref.path, ref])).values()];
  for (let index = 0; index < unique.length; index += 400) {
    const batch = admin.firestore().batch();
    unique.slice(index, index + 400).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
}

async function deleteQueryTrees(query) {
  const db = admin.firestore();
  while (true) {
    const snapshot = await query.limit(100).get();
    if (snapshot.empty) return;
    for (let index = 0; index < snapshot.docs.length; index += 10) {
      await Promise.all(
        snapshot.docs.slice(index, index + 10)
          .map((doc) => db.recursiveDelete(doc.ref))
      );
    }
  }
}

async function runChunked(items, chunkSize, action) {
  for (let index = 0; index < items.length; index += chunkSize) {
    await Promise.all(items.slice(index, index + chunkSize).map(action));
  }
}

// Collection-group indekslerine bağımlı olmadan eski ve yeni alt koleksiyon
// şemalarındaki kullanıcı izlerini temizler. listDocuments, ana belgesi olmayan
// fakat alt koleksiyonu bulunan Firestore yollarını da döndürür.
async function deleteNestedAccountData(uid) {
  const db = admin.firestore();
  const userRefs = await db.collection("users").listDocuments();
  await runChunked(userRefs, 10, async (userRef) => {
    await Promise.all([
      deleteQueryTrees(
        userRef.collection("notifications").where("actorId", "==", uid)
      ),
      deleteQueryTrees(
        userRef.collection("saved_lists").where("ownerId", "==", uid)
      ),
    ]);
  });

  const feedRefs = await db.collection("feeds").listDocuments();
  await runChunked(feedRefs, 10, (feedRef) =>
    deleteQueryTrees(
      feedRef.collection("user_feed").where("authorId", "==", uid)
    )
  );

  const weekRefs = await db.collection("weekly_leaderboard").listDocuments();
  await deleteReferences(
    weekRefs.map((weekRef) => weekRef.collection("scores").doc(uid))
  );

  const postRefs = await db.collection("posts").listDocuments();
  await runChunked(postRefs, 5, async (postRef) => {
    const likeRefs = [postRef.collection("likes").doc(uid)];
    const replies = await postRef.collection("replies").get();
    for (const reply of replies.docs) {
      if (cleanText(reply.data().authorId, 128) === uid) {
        await db.recursiveDelete(reply.ref);
        continue;
      }
      likeRefs.push(reply.ref.collection("likes").doc(uid));
      const subReplies = await reply.ref.collection("subReplies").get();
      for (const subReply of subReplies.docs) {
        if (cleanText(subReply.data().authorId, 128) === uid) {
          await db.recursiveDelete(subReply.ref);
        } else {
          likeRefs.push(subReply.ref.collection("likes").doc(uid));
        }
      }
    }
    await deleteReferences(likeRefs);
  });
}

async function cleanupAccountCrossLinks(uid) {
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const [followers, following, blocked, blockedBy] = await Promise.all([
    userRef.collection("followers").get(),
    userRef.collection("following").get(),
    userRef.collection("blocked").get(),
    userRef.collection("blockedBy").get(),
  ]);
  const refs = [];
  followers.docs.forEach((doc) => {
    refs.push(db.collection("users").doc(doc.id).collection("following").doc(uid));
  });
  following.docs.forEach((doc) => {
    refs.push(db.collection("users").doc(doc.id).collection("followers").doc(uid));
  });
  blocked.docs.forEach((doc) => {
    refs.push(db.collection("users").doc(doc.id).collection("blockedBy").doc(uid));
  });
  blockedBy.docs.forEach((doc) => {
    refs.push(db.collection("users").doc(doc.id).collection("blocked").doc(uid));
  });
  await deleteReferences(refs);
}

async function removeAccountFromClubs(uid) {
  const db = admin.firestore();
  const clubs = await db.collection("clubs").where("members", "array-contains", uid).get();
  for (const clubDoc of clubs.docs) {
    const data = clubDoc.data() || {};
    const members = (Array.isArray(data.members) ? data.members : [])
      .map(String).filter((memberUid) => memberUid && memberUid !== uid);
    const admins = (Array.isArray(data.admins) ? data.admins : [])
      .map(String).filter((adminUid) => adminUid && adminUid !== uid);
    const chatRef = db.collection("chats").doc(clubDoc.id);
    if (!members.length) {
      await Promise.all([
        db.recursiveDelete(clubDoc.ref),
        db.recursiveDelete(chatRef),
      ]);
      continue;
    }
    const currentOwner = cleanText(data.ownerId, 128);
    const nextOwner = currentOwner && currentOwner !== uid
      ? currentOwner
      : (admins[0] || members[0]);
    if (!admins.includes(nextOwner)) admins.push(nextOwner);
    await Promise.all([
      clubDoc.ref.update({
        ownerId: nextOwner,
        members,
        admins,
        pendingRequests: admin.firestore.FieldValue.arrayRemove(uid),
        memberCount: members.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }),
      chatRef.set({
        ownerId: nextOwner,
        participants: admin.firestore.FieldValue.arrayRemove(uid),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true }),
    ]);

    const [events, polls] = await Promise.all([
      clubDoc.ref.collection("events").get(),
      clubDoc.ref.collection("polls").get(),
    ]);
    const batch = db.batch();
    events.docs.forEach((doc) => batch.update(doc.ref, {
      participants: admin.firestore.FieldValue.arrayRemove(uid),
    }));
    polls.docs.forEach((doc) => batch.update(doc.ref, {
      [`voters.${uid}`]: admin.firestore.FieldValue.delete(),
    }));
    if (events.size || polls.size) await batch.commit();
  }
}

async function removeAccountFromChats(uid) {
  const db = admin.firestore();
  const chats = await db.collection("chats")
    .where("participants", "array-contains", uid).get();
  for (const chatDoc of chats.docs) {
    const data = chatDoc.data() || {};
    const participants = (Array.isArray(data.participants) ? data.participants : [])
      .map(String).filter((participantUid) => participantUid && participantUid !== uid);
    const updates = {
      participants,
      [`titles.${uid}`]: admin.firestore.FieldValue.delete(),
      [`photos.${uid}`]: admin.firestore.FieldValue.delete(),
      [`unreadCounts.${uid}`]: admin.firestore.FieldValue.delete(),
      [`hiddenFor.${uid}`]: admin.firestore.FieldValue.delete(),
      [`deliveredUpTo.${uid}`]: admin.firestore.FieldValue.delete(),
      [`typing.${uid}`]: admin.firestore.FieldValue.delete(),
      [`typingUpdatedAt.${uid}`]: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (data.lastMessageAuthorId === uid) {
      updates.lastMessage = "Silinen kullanıcıdan mesaj";
      updates.lastMessageAuthorId = admin.firestore.FieldValue.delete();
    }
    participants.forEach((participantUid) => {
      updates[`titles.${participantUid}`] = "Silinen kullanıcı";
      updates[`photos.${participantUid}`] = "";
    });
    await chatDoc.ref.update(updates);
    await deleteReferences([chatDoc.ref.collection("reads").doc(uid)]);
    await deleteQueryTrees(
      chatDoc.ref.collection("messages").where("authorId", "==", uid)
    );
    await deleteQueryTrees(
      chatDoc.ref.collection("messages").where("from", "==", uid)
    );
  }
}

async function deleteAccountStorage(uid) {
  const bucket = onboardingProfileBucket();
  const prefixes = [
    `profile_images/${uid}/`,
    `user_avatars/${uid}_`,
    `post_images/${uid}_`,
  ];
  for (const prefix of prefixes) {
    const [files] = await bucket.getFiles({ prefix });
    for (let index = 0; index < files.length; index += 20) {
      await Promise.all(files.slice(index, index + 20).map((file) =>
        file.delete({ ignoreNotFound: true })
      ));
    }
  }
}

async function deleteAccountFirestoreData(uid) {
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();
  const userData = userDoc.exists ? userDoc.data() || {} : {};

  await cleanupAccountCrossLinks(uid);
  await removeAccountFromChats(uid);
  await removeAccountFromClubs(uid);

  const treeQueries = [
    db.collection("posts").where("authorId", "==", uid),
    db.collection("custom_lists").where("ownerId", "==", uid),
    db.collection("userAddedFilms").where("authorId", "==", uid),
    db.collection("likes").where("uids", "array-contains", uid),
    db.collection("matches").where("uids", "array-contains", uid),
  ];
  for (const query of treeQueries) await deleteQueryTrees(query);
  await deleteNestedAccountData(uid);

  const plainQueries = [
    db.collection("profile_movie_events").where("userId", "==", uid),
    db.collection("likeLogs").where("from", "==", uid),
    db.collection("likeLogs").where("to", "==", uid),
    db.collection("reports").where("reporterId", "==", uid),
    db.collection("reports").where("by", "==", uid),
    db.collection("reports").where("reportedUserId", "==", uid),
    db.collection("reports").where("reportedId", "==", uid),
    db.collection("usernames").where("uid", "==", uid),
  ];
  for (const query of plainQueries) await deleteQueryTrees(query);

  const usernameKeys = new Set([
    cleanText(userData.username_lc, 80),
    cleanText(userData.displayName_lc, 80),
    cleanText(userData.username, 80).toLowerCase(),
    cleanText(userData.displayName, 80).toLowerCase(),
  ].filter(Boolean));
  await deleteReferences(
    [...usernameKeys].map((username) => db.collection("usernames").doc(username))
  );

  const directTrees = [
    userRef,
    db.collection("feeds").doc(uid),
    db.collection("userTasteProfiles").doc(uid),
    db.collection("registration_drafts").doc(uid),
    db.collection("email_verifications").doc(uid),
    db.collection("marketing_emails").doc(uid),
    db.collection("account_delete_requests").doc(uid),
  ];
  for (const ref of directTrees) await db.recursiveDelete(ref);
}

exports.completeAccountDeletion = onCall(
  {
    secrets: ["EMAIL_OTP_HMAC_SECRET"],
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");
    const token = cleanText(request.data && request.data.authorizationToken, 128);
    const reasonCode = cleanText(request.data && request.data.reasonCode, 40);
    const note = cleanText(request.data && request.data.note, 500);
    if (!/^[a-f0-9]{64}$/.test(token)) {
      throw new HttpsError("permission-denied", "Hesap silme yetkisi geçersiz.");
    }
    if (!ACCOUNT_DELETION_REASON_CODES.has(reasonCode)) {
      throw new HttpsError("invalid-argument", "Bir ayrılma nedeni seçmelisin.");
    }
    if (reasonCode === "other" && note.length < 3) {
      throw new HttpsError(
        "invalid-argument",
        "Diğer seçeneği için kısa bir açıklama yazmalısın."
      );
    }

    const db = admin.firestore();
    const authUser = await admin.auth().getUser(uid);
    const email = normalizedEmail(authUser.email);
    const verificationRef = db.collection("account_deletion_verifications").doc(uid);
    const suppliedHash = hashAccountDeletionAuthorization(uid, token);
    const nowMs = Date.now();
    const now = admin.firestore.Timestamp.fromMillis(nowMs);
    const claimed = await db.runTransaction(async (transaction) => {
      const verificationDoc = await transaction.get(verificationRef);
      if (!verificationDoc.exists) return null;
      const verification = verificationDoc.data() || {};
      const expectedHash = cleanText(verification.authorizedHash, 64);
      const authorizedUntilMs = timestampMillis(verification.authorizedUntil);
      const alreadyProcessing = timestampMillis(verification.processingStartedAt) > 0;
      if (normalizedEmail(verification.email) !== email ||
          !safeHashEquals(expectedHash, suppliedHash) ||
          (!alreadyProcessing && authorizedUntilMs < nowMs)) {
        return null;
      }
      transaction.set(verificationRef, {
        processingStartedAt: verification.processingStartedAt || now,
        updatedAt: now,
      }, { merge: true });
      return {
        sessionId: cleanText(verification.sessionId, 64),
        providerTypes: Array.isArray(verification.providerTypes)
          ? verification.providerTypes.map(String).slice(0, 4)
          : accountProviderTypes(authUser),
      };
    });
    if (!claimed || !/^[a-f0-9]{32}$/.test(claimed.sessionId)) {
      throw new HttpsError(
        "permission-denied",
        "Hesap silme doğrulamasının süresi dolmuş. Lütfen yeniden başlat."
      );
    }

    const feedbackRef = db.collection("account_deletion_feedback")
      .doc(claimed.sessionId);
    await feedbackRef.set({
      reasonCode,
      note: note || null,
      providerTypes: claimed.providerTypes,
      status: "processing",
      submittedAt: now,
    }, { merge: true });

    try {
      await deleteAccountFirestoreData(uid);
      await deleteAccountStorage(uid);
      await admin.auth().deleteUser(uid);
      await verificationRef.delete().catch(() => null);
      await feedbackRef.set({
        status: "completed",
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return { ok: true };
    } catch (error) {
      console.error("Hesap silme tamamlanamadı:", uid, error);
      await feedbackRef.set({
        status: "failed",
        failedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true }).catch(() => null);
      throw new HttpsError(
        "internal",
        "Hesap silme işlemi tamamlanamadı. Lütfen tekrar dene."
      );
    }
  }
);

// Kimlik doğrulama, tamamlanmış üyelik anlamına gelmez. Bu callable zorunlu
// onboarding alanlarını doğrular, kullanıcı adını transaction ile ayırır ve
// profili tek atomik işlemde active durumuna geçirir.
exports.completeOnboarding = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");

  const payload = request.data || {};
  const age = Number(payload.age);
  if (!Number.isInteger(age) || age < 13 || age > 120) {
    throw new HttpsError("invalid-argument", "Geçerli bir yaş girmeniz gerekiyor.");
  }

  const letterboxdUsername = cleanText(payload.letterboxdUsername, 40);
  if (letterboxdUsername && !/^[A-Za-z0-9_.-]{2,40}$/.test(letterboxdUsername)) {
    throw new HttpsError("invalid-argument", "Letterboxd kullanıcı adı geçersiz.");
  }

  const favGenres = Array.isArray(payload.favGenres)
    ? [...new Set(payload.favGenres.map((item) => cleanText(item, 60)).filter(Boolean))]
      .slice(0, 60)
    : [];
  const favDirectors = normalizeOnboardingPeople(payload.favDirectors);
  const favActors = normalizeOnboardingPeople(payload.favActors);
  if (!favDirectors.length || !favActors.length) {
    throw new HttpsError(
      "invalid-argument",
      "En az bir favori yönetmen ve bir favori oyuncu seçmeniz gerekiyor."
    );
  }

  const favoriteMovieKey = validCatalogKey(payload.favoriteMovieKey);
  if (!favoriteMovieKey) {
    throw new HttpsError(
      "invalid-argument",
      "En az bir geçerli favori film seçmeniz gerekiyor."
    );
  }
  const profilePhoto = await validateOnboardingProfilePhoto(
    uid,
    payload.profilePhotoPath,
    payload.photoURL
  );
  const authUser = await admin.auth().getUser(uid);
  const verifiedAuthEmail = normalizedEmail(authUser.email);
  if (!verifiedAuthEmail) {
    throw new HttpsError(
      "failed-precondition",
      "Doğrulanmış bir e-posta adresi olmadan kayıt tamamlanamaz."
    );
  }
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const draftRef = db.collection("registration_drafts").doc(uid);
  const catalogRef = db.collection("catalog_films").doc(favoriteMovieKey);
  const verificationRef = db.collection("email_verifications").doc(uid);
  const watchedHistoryRef = userRef.collection("watched").doc("history");
  const diaryWatchedAt = admin.firestore.Timestamp.now();
  const diaryEventId = crypto
    .createHash("sha1")
    .update(`${uid}|onboarding|${favoriteMovieKey}`)
    .digest("hex");
  const diaryRef = userRef.collection("diary").doc(diaryEventId);

  await db.runTransaction(async (transaction) => {
    const [userDoc, draftDoc, catalogDoc, verificationDoc] = await Promise.all([
      transaction.get(userRef),
      transaction.get(draftRef),
      transaction.get(catalogRef),
      transaction.get(verificationRef),
    ]);
    const existing = userDoc.exists ? userDoc.data() || {} : {};
    const draft = draftDoc.exists ? draftDoc.data() || {} : {};
    const catalogMovie = catalogDoc.exists ? catalogDoc.data() || {} : {};
    const verification = verificationDoc.exists ? verificationDoc.data() || {} : {};

    if (existing.registrationStatus === "active" &&
        existing.onboardingCompleted === true) {
      if (draftDoc.exists) transaction.delete(draftRef);
      if (verificationDoc.exists) transaction.delete(verificationRef);
      return;
    }

    const verifiedByOtp = verification.verified === true &&
      normalizedEmail(verification.email) === verifiedAuthEmail;
    if (!hasTrustedFederatedEmail(authUser) &&
        authUser.emailVerified !== true &&
        !verifiedByOtp) {
      throw new HttpsError(
        "failed-precondition",
        "Onboarding'den önce e-posta adresini doğrulaman gerekiyor."
      );
    }

    const favoriteTmdbId = positiveInteger(catalogMovie.tmdbId);
    const favoriteTitle = cleanText(catalogMovie.title, 180);
    if (!catalogDoc.exists || !favoriteTmdbId || !favoriteTitle) {
      throw new HttpsError(
        "failed-precondition",
        "Seçilen film güvenli katalogda doğrulanamadı."
      );
    }
    const favoritePosterPath = validPosterPath(catalogMovie.posterPath) ||
      posterPathFromTmdbUrl(catalogMovie.posterUrl);
    const favoritePosterUrl = tmdbPosterUrl(favoritePosterPath);
    const favoriteReleaseYear = positiveInteger(catalogMovie.year);
    const favoriteLite = {
      key: favoriteMovieKey,
      title: favoriteTitle,
      tmdbId: favoriteTmdbId,
      posterUrl: favoritePosterUrl,
      source: "manual",
    };
    const diaryEntry = {
      id: diaryEventId,
      movieKey: favoriteMovieKey,
      tmdbId: favoriteTmdbId,
      title: favoriteTitle,
      posterUrl: favoritePosterUrl,
      ...(favoriteReleaseYear ? { releaseYear: favoriteReleaseYear } : {}),
      watchedAt: diaryWatchedAt,
      source: "onboarding",
    };

    const base = draftDoc.exists ? draft : existing;
    const displayName = cleanText(base.displayName, 20);
    const displayNameLc = displayName.toLowerCase();
    if (base.termsAccepted !== true ||
        !/^[A-Za-z0-9._-]{3,20}$/.test(displayName)) {
      throw new HttpsError(
        "failed-precondition",
        "Kullanıcı adı ve sözleşme onayı tamamlanmamış."
      );
    }

    const duplicateQuery = db
      .collection("users")
      .where("displayName_lc", "==", displayNameLc)
      .limit(2);
    const duplicateDocs = await transaction.get(duplicateQuery);
    if (duplicateDocs.docs.some((doc) => doc.id !== uid)) {
      throw new HttpsError("already-exists", "Bu kullanıcı adı artık kullanımda.");
    }

    const usernameRef = db.collection("usernames").doc(displayNameLc);
    const usernameDoc = await transaction.get(usernameRef);
    if (usernameDoc.exists && usernameDoc.data().uid !== uid) {
      throw new HttpsError("already-exists", "Bu kullanıcı adı artık kullanımda.");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const email = verifiedAuthEmail;
    const marketingConsent = base.marketingConsent === true;
    const authProvider = cleanText(base.authProvider, 30) || "unknown";

    transaction.set(usernameRef, { uid, updatedAt: now });
    transaction.set(userRef, {
      displayName,
      displayName_lc: displayNameLc,
      username: displayName,
      username_lc: displayNameLc,
      email,
      photoURL: profilePhoto.photoURL,
      photoUrl: admin.firestore.FieldValue.delete(),
      photoStoragePath: profilePhoto.profilePhotoPath,
      termsAccepted: true,
      marketingConsent,
      termsAcceptedAt: base.termsAcceptedAt || now,
      authProvider,
      age,
      favGenres,
      favDirectors,
      favActors,
      favoritesKeys: admin.firestore.FieldValue.arrayUnion(favoriteMovieKey),
      favorites: admin.firestore.FieldValue.arrayUnion(favoriteLite),
      watchedKeys: admin.firestore.FieldValue.arrayUnion(favoriteMovieKey),
      recentWatchedIds: admin.firestore.FieldValue.arrayUnion(favoriteMovieKey),
      recentDiaryEntries: [diaryEntry],
      diaryUpdatedAt: now,
      filmSources: { [favoriteMovieKey]: "manual" },
      letterboxdUsername,
      letterboxdUsername_lc: letterboxdUsername.toLowerCase(),
      registrationStatus: "active",
      onboardingCompleted: true,
      onboardingCompletedAt: now,
      registrationVersion: 3,
      createdAt: existing.createdAt || base.createdAt || now,
      updatedAt: now,
    }, { merge: true });

    transaction.set(watchedHistoryRef, {
      ids: { [favoriteMovieKey]: true },
      recentIds: admin.firestore.FieldValue.arrayUnion(favoriteMovieKey),
      updatedAt: now,
    }, { merge: true });

    transaction.set(diaryRef, {
      ...diaryEntry,
      recordedAt: now,
    });

    const marketingRef = db.collection("marketing_emails").doc(uid);
    if (marketingConsent && email) {
      transaction.set(marketingRef, {
        email,
        displayName,
        consentedAt: base.termsAcceptedAt || now,
        source: `${authProvider}_register`,
      }, { merge: true });
    } else {
      transaction.delete(marketingRef);
    }
    if (draftDoc.exists) transaction.delete(draftRef);
    if (verificationDoc.exists) transaction.delete(verificationRef);
  });

  try {
    await admin.auth().updateUser(uid, { photoURL: profilePhoto.photoURL });
  } catch (error) {
    console.error("Firebase Auth profil fotoğrafı güncellenemedi:", uid, error.message);
  }

  return { ok: true, registrationStatus: "active" };
});

exports.cancelRegistration = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");

  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const draftRef = db.collection("registration_drafts").doc(uid);
  const verificationRef = db.collection("email_verifications").doc(uid);
  await db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    const userData = userDoc.exists ? userDoc.data() || {} : {};
    if (userData.registrationStatus === "active" &&
        userData.onboardingCompleted === true) {
      throw new HttpsError(
        "failed-precondition",
        "Tamamlanmış hesap bu akıştan silinemez."
      );
    }
    transaction.delete(draftRef);
    transaction.delete(verificationRef);
    if (userDoc.exists) transaction.delete(userRef);
    transaction.delete(db.collection("userTasteProfiles").doc(uid));
    transaction.delete(db.collection("marketing_emails").doc(uid));
  });

  try {
    await onboardingProfileBucket().file(onboardingProfilePhotoPath(uid)).delete();
  } catch (error) {
    if (Number(error.code) !== 404) {
      console.error("Onboarding profil fotoğrafı silinemedi:", uid, error.message);
    }
  }

  try {
    await admin.auth().deleteUser(uid);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
  }
  return { ok: true };
});

// Trigger Email uzantısı teslimatı bitirdiğinde doğrulama kodunu içeren kuyruk
// belgesini kaldırır. Böylece düz metin kod mail koleksiyonunda tutulmaz.
exports.cleanupEmailVerificationMail = functions.firestore
  .document("mail/{mailId}")
  .onUpdate(async (change) => {
    const data = change.after.data() || {};
    const deliveryState = cleanText(data.delivery && data.delivery.state, 30);
    if (!["email_verification", "account_deletion_verification", "password_reset"]
      .includes(data.category) ||
        !["SUCCESS", "ERROR"].includes(deliveryState)) {
      return null;
    }
    await change.after.ref.delete();
    return null;
  });

async function assertNewsEditor(uid) {
  if (!uid) throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
  if (NEWS_ADMIN_UIDS.has(uid)) return true;

  const db = admin.firestore();
  const editorDoc = await db.collection("news_editors").doc(uid).get();
  if (editorDoc.exists && editorDoc.data().active !== false) return true;

  const userDoc = await db.collection("users").doc(uid).get();
  const role = userDoc.exists ? userDoc.data().role : null;
  if (["admin", "editor", "newsEditor"].includes(role)) return true;

  throw new HttpsError("permission-denied", "Bu panel için yetkiniz yok.");
}

async function assertTriviaEditor(uid) {
  if (!uid) throw new HttpsError("unauthenticated", "Giris yapmaniz gerekiyor.");
  if (NEWS_ADMIN_UIDS.has(uid)) return true;

  const db = admin.firestore();
  const editorDoc = await db.collection("trivia_editors").doc(uid).get();
  if (editorDoc.exists && editorDoc.data().active !== false) return true;

  const userDoc = await db.collection("users").doc(uid).get();
  const role = userDoc.exists ? userDoc.data().role : null;
  if (["admin", "editor", "triviaEditor", "newsEditor"].includes(role)) return true;

  throw new HttpsError("permission-denied", "Bu panel icin yetkiniz yok.");
}

async function assertBotAdmin(uid) {
  if (!uid) throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
  if (NEWS_ADMIN_UIDS.has(uid)) return true;

  const db = admin.firestore();
  const editorDoc = await db.collection("bot_editors").doc(uid).get();
  if (editorDoc.exists && editorDoc.data().active !== false) return true;

  const userDoc = await db.collection("users").doc(uid).get();
  const role = userDoc.exists ? userDoc.data().role : null;
  if (["admin", "botAdmin"].includes(role)) return true;

  throw new HttpsError("permission-denied", "Bu panel için yetkiniz yok.");
}

async function assertBlogEditor(uid, authToken = {}) {
  if (!uid) throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");

  const db = admin.firestore();
  const [editorDoc, userDoc] = await Promise.all([
    db.collection("blog_editors").doc(uid).get(),
    db.collection("users").doc(uid).get(),
  ]);
  const editor = editorDoc.exists ? editorDoc.data() || {} : {};
  const user = userDoc.exists ? userDoc.data() || {} : {};
  const role = cleanText(user.role, 40);
  const isManager = NEWS_ADMIN_UIDS.has(uid) ||
    role === "admin" || (editor.canManageAll === true && editor.active !== false);
  const isEditor = isManager ||
    (editorDoc.exists && editor.active !== false) ||
    (!editorDoc.exists && ["blogger", "blogEditor"].includes(role));

  if (!isEditor) {
    throw new HttpsError("permission-denied", "Bu hesap blogger olarak yetkilendirilmemiş.");
  }

  const tokenName = cleanText(authToken.name, 100);
  const tokenEmail = cleanText(authToken.email, 180);
  const username = cleanText(user.username || user.handle, 80).replace(/^@/, "");
  const displayName = cleanText(
    user.displayName || user.name || tokenName || username || tokenEmail.split("@")[0],
    100
  ) || "CineMatch Blogger";
  const photoUrl = cleanHttpsUrl(
    user.photoURL || user.photoUrl || user.profileImageUrl || authToken.picture,
    1400
  );

  return {
    canManageAll: isManager,
    profile: { uid, displayName, username, photoUrl },
  };
}

function cleanHttpsUrl(value, maxLength = 1400) {
  const candidate = cleanText(value, maxLength);
  if (!candidate) return "";
  try {
    const parsed = new URL(candidate);
    return parsed.protocol === "https:" ? parsed.toString() : "";
  } catch (error) {
    return "";
  }
}

function sanitizeBlogContent(value) {
  const source = typeof value === "string" ? value.slice(0, 180000) : "";
  return sanitizeHtml(source, {
    allowedTags: [
      "p", "br", "h2", "h3", "strong", "b", "em", "i", "u", "s",
      "blockquote", "ul", "ol", "li", "a", "figure", "img", "figcaption", "hr",
    ],
    allowedAttributes: {
      a: ["href", "target", "rel"],
      img: ["src", "alt", "data-storage-path"],
    },
    allowedSchemes: ["https"],
    allowedSchemesByTag: { img: ["https"], a: ["https", "http"] },
    allowProtocolRelative: false,
    transformTags: {
      a: (tagName, attribs) => ({
        tagName,
        attribs: {
          href: cleanHttpsUrl(attribs.href, 1400),
          target: "_blank",
          rel: "noopener noreferrer nofollow",
        },
      }),
    },
    exclusiveFilter: (frame) => {
      if (frame.tag !== "img") return false;
      const src = cleanHttpsUrl(frame.attribs.src, 1800);
      return !src || ![
        "firebasestorage.googleapis.com",
        "storage.googleapis.com",
      ].includes(new URL(src).hostname);
    },
  }).trim();
}

function normalizeBlogMovies(value) {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  return value.reduce((movies, raw) => {
    if (movies.length >= 10 || !raw || typeof raw !== "object") return movies;
    const tmdbId = Number(raw.tmdbId || raw.id);
    if (!Number.isInteger(tmdbId) || tmdbId <= 0 || seen.has(tmdbId)) return movies;
    seen.add(tmdbId);
    movies.push({
      tmdbId,
      title: cleanText(raw.title, 180) || `TMDB ${tmdbId}`,
      originalTitle: cleanText(raw.originalTitle, 180),
      year: Number.isInteger(Number(raw.year)) ? Number(raw.year) : null,
      posterPath: /^\/[A-Za-z0-9._/-]+$/.test(String(raw.posterPath || ""))
        ? String(raw.posterPath)
        : "",
      posterUrl: cleanHttpsUrl(raw.posterUrl, 1400),
    });
    return movies;
  }, []);
}

function normalizeBlogImages(value, postId) {
  if (!Array.isArray(value)) return [];
  return value.reduce((images, raw) => {
    if (images.length >= 30 || !raw || typeof raw !== "object") return images;
    const url = cleanHttpsUrl(raw.url, 1800);
    const path = cleanText(raw.path, 600);
    if (!url || !/^blog_images\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+\/[A-Za-z0-9_.-]+$/.test(path)) {
      return images;
    }
    if (path.split("/")[2] !== postId) return images;
    images.push({ url, path, alt: cleanText(raw.alt, 180) });
    return images;
  }, []);
}

function normalizeTriviaQuestion(data) {
  const question = cleanText(data.question, 500);
  if (!question) throw new HttpsError("invalid-argument", "Soru metni gerekli.");

  const options = Array.isArray(data.options)
    ? data.options.map((item) => cleanText(item, 180)).filter(Boolean).slice(0, 4)
    : [];
  if (options.length !== 4) {
    throw new HttpsError("invalid-argument", "Tam 4 sik gerekli.");
  }

  const correctIndex = Number(data.correctIndex);
  if (!Number.isInteger(correctIndex) || correctIndex < 0 || correctIndex > 3) {
    throw new HttpsError("invalid-argument", "Dogru sik 0-3 arasinda olmali.");
  }

  const weekId = cleanText(data.weekId, 16);
  if (!/^\d{4}_W\d{1,2}$/.test(weekId)) {
    throw new HttpsError("invalid-argument", "Hafta ID formati gecersiz. Ornek: 2026_W27");
  }

  const difficulty = ["kolay", "orta", "zor"].includes(data.difficulty)
    ? data.difficulty
    : "orta";

  return {
    question,
    options,
    correctIndex,
    weekId,
    difficulty,
    imageUrl: cleanText(data.imageUrl, 1200) || null,
    explanation: cleanText(data.explanation, 800),
    isActive: data.isActive !== false,
  };
}

async function countTriviaQuestionsForWeek(db, weekId, excludeId) {
  const snap = await db
    .collection("trivia_questions")
    .where("weekId", "==", weekId)
    .get();
  return snap.docs.filter((doc) => doc.id !== excludeId).length;
}

exports.isNewsAdmin = onCall(async (request) => {
  await assertNewsEditor(request.auth && request.auth.uid);
  return { ok: true };
});

exports.isTriviaAdmin = onCall(async (request) => {
  await assertTriviaEditor(request.auth && request.auth.uid);
  return { ok: true };
});

exports.isBotAdmin = onCall(async (request) => {
  await assertBotAdmin(request.auth && request.auth.uid);
  return { ok: true };
});

exports.isBlogEditor = onCall(async (request) => {
  const access = await assertBlogEditor(
    request.auth && request.auth.uid,
    request.auth && request.auth.token
  );
  return { ok: true, ...access };
});

// Kullanıcıların profil kataloglarına eklediği filmleri zaman damgalı olaylara
// dönüştürür. Watchlist bilinçli olarak kapsam dışıdır; henüz izlenmemiş filmdir.
// Bu tetikleyici sayesinde haftalık rapor bütün users dokümanlarını taramaz.
exports.trackProfileMovieCatalogAdditions = functions.firestore
  .document("users/{uid}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const beforeDiaryMs = before.diaryUpdatedAt &&
      typeof before.diaryUpdatedAt.toMillis === "function"
      ? before.diaryUpdatedAt.toMillis()
      : 0;
    const afterDiaryMs = after.diaryUpdatedAt &&
      typeof after.diaryUpdatedAt.toMillis === "function"
      ? after.diaryUpdatedAt.toMillis()
      : 0;
    // Yeni istemci aynı batch içinde asıl Diary belgesini yazıyor. Bu durumda
    // ikinci bir profile_movie_events kopyası üretmek gereksiz yazma olur.
    if (afterDiaryMs && afterDiaryMs !== beforeDiaryMs) return null;
    const fields = {
      watchedKeys: "watched",
    };
    const writes = [];
    Object.entries(fields).forEach(([field, catalogType]) => {
      const previous = new Set(
        (Array.isArray(before[field]) ? before[field] : [])
          .map((value) => String(value).trim())
          .filter(Boolean)
      );
      const current = (Array.isArray(after[field]) ? after[field] : [])
        .map((value) => String(value).trim())
        .filter(Boolean);
      current.forEach((movieKey) => {
        if (previous.has(movieKey)) return;
        const fingerprint = crypto
          .createHash("sha1")
          .update(`${context.eventId}|${field}|${movieKey}`)
          .digest("hex");
        const ref = admin.firestore()
          .collection("profile_movie_events")
          .doc(fingerprint);
        writes.push(ref.set({
          userId: context.params.uid,
          movieKey,
          tmdbId: Number(movieKey) || null,
          catalogType,
          addedAt: admin.firestore.FieldValue.serverTimestamp(),
          sourceEventId: context.eventId,
        }));
      });
    });
    await Promise.all(writes);
    return null;
  });

// Admin tarafından elle üretilen haftalık Instagram raporu. Haftalar pazartesi
// 00:00 (Europe/Istanbul) başlangıçlıdır. İstemci yalnızca hazır veriyi çizer;
// sıralama ve yetki kontrolü güvenilir sunucu tarafında yapılır.
exports.generateWeeklySocialReport = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertNewsEditor(uid);

  const rawEnd = request.data && request.data.weekEnd;
  const end = rawEnd ? new Date(rawEnd) : new Date();
  if (Number.isNaN(end.getTime())) {
    throw new HttpsError("invalid-argument", "Hafta tarihi geçersiz.");
  }

  // JS Date UTC çalışır. İstanbul pazartesi başlangıcını UTC'ye çeviriyoruz.
  const istanbulNow = new Date(end.getTime() + (3 * 60 * 60 * 1000));
  const day = istanbulNow.getUTCDay() || 7;
  istanbulNow.setUTCDate(istanbulNow.getUTCDate() - day + 1);
  istanbulNow.setUTCHours(0, 0, 0, 0);
  const start = new Date(istanbulNow.getTime() - (3 * 60 * 60 * 1000));
  const finish = new Date(start.getTime() + (7 * 24 * 60 * 60 * 1000));

  const db = admin.firestore();
  const startTimestamp = admin.firestore.Timestamp.fromDate(start);
  const finishTimestamp = admin.firestore.Timestamp.fromDate(finish);
  const [legacyAdditions, diaryAdditions] = await Promise.all([
    db.collection("profile_movie_events")
      .where("addedAt", ">=", startTimestamp)
      .where("addedAt", "<", finishTimestamp)
      .get(),
    db.collectionGroup("diary")
      .where("recordedAt", ">=", startTimestamp)
      .where("recordedAt", "<", finishTimestamp)
      .get(),
  ]);

  // Yalnızca gerçekten izlenen filmleri say. Uygulama aynı filmi hem katalog
  // anahtarı hem TMDB anahtarıyla watchedKeys'e ekleyebildiği için önce merkezi
  // katalog üzerinden tek bir kimliğe indirgeriz. Aynı kullanıcı/film çifti
  // haftada yalnızca bir kez sayılır.
  const legacyItems = legacyAdditions.docs
    .map((doc) => doc.data() || {})
    .filter((item) => item.catalogType === "watched");
  const diaryItems = diaryAdditions.docs.map((doc) => ({
    ...(doc.data() || {}),
    userId: doc.ref.parent.parent && doc.ref.parent.parent.id,
    catalogType: "watched",
  }));
  const catalogCache = new Map();
  async function resolveCatalog(rawKey, rawTmdbId) {
    const key = String(rawKey || "").trim();
    const embeddedTmdb = /^tmdb:(\d+)$/.exec(key);
    const numericTmdb = Number(rawTmdbId) ||
      (embeddedTmdb ? Number(embeddedTmdb[1]) : Number(key)) || null;
    const cacheKey = `${key}|${numericTmdb || ""}`;
    if (catalogCache.has(cacheKey)) return catalogCache.get(cacheKey);

    const pending = (async () => {
      let catalogDoc = key
        ? await db.collection("catalog_films").doc(key).get()
        : null;
      if ((!catalogDoc || !catalogDoc.exists) && numericTmdb) {
        const snap = await db.collection("catalog_films")
          .where("tmdbId", "==", numericTmdb).limit(1).get();
        catalogDoc = snap.empty ? null : snap.docs[0];
      }
      const data = catalogDoc && catalogDoc.exists
        ? catalogDoc.data() || {}
        : {};
      const tmdbId = Number(data.tmdbId) || numericTmdb;
      return {
        id: tmdbId
          ? `tmdb:${tmdbId}`
          : (catalogDoc && catalogDoc.exists ? catalogDoc.id : key),
        tmdbId: tmdbId || null,
        title: cleanText(data.title, 140) || key,
        year: Number(data.year) || null,
        posterUrl: cleanText(data.posterUrl, 1200),
      };
    })();
    // Aynı legacy film eşzamanlı işlendiğinde katalog sorgusunu da paylaş.
    catalogCache.set(cacheKey, pending);
    return pending;
  }

  const resolvedLegacyItems = await Promise.all(legacyItems.map(async (item) => ({
    userId: String(item.userId || ""),
    movie: await resolveCatalog(item.movieKey, item.tmdbId),
  })));
  // Yeni Diary olayları ekran için gerekli film özetini zaten taşıyor. Haftalık
  // raporda bunları tekrar catalog_films üzerinden okumak gereksizdir.
  const resolvedDiaryItems = diaryItems.map((item) => {
    const tmdbId = positiveInteger(item.tmdbId);
    const movieKey = cleanText(item.movieKey, 300);
    return {
      userId: String(item.userId || ""),
      movie: {
        id: tmdbId ? `tmdb:${tmdbId}` : movieKey,
        tmdbId: tmdbId || null,
        title: cleanText(item.title, 140) || movieKey,
        year: positiveInteger(item.releaseYear),
        posterUrl: cleanText(item.posterUrl, 1200),
      },
    };
  });
  const resolvedItems = [...resolvedLegacyItems, ...resolvedDiaryItems];
  const counts = new Map();
  resolvedItems.forEach(({ userId, movie }) => {
    if (!movie.id) return;
    const current = counts.get(movie.id) || {
      ...movie,
      viewers: new Set(),
    };
    current.viewers.add(userId || `anonymous:${current.viewers.size}`);
    counts.set(movie.id, current);
  });

  const movies = [...counts.values()]
    .map(({ viewers, ...movie }) => ({ ...movie, additions: viewers.size }))
    .sort((a, b) => b.additions - a.additions || a.title.localeCompare(b.title, "tr"))
    .slice(0, 10);

  const weekId = start.toISOString().slice(0, 10);
  const payload = {
    weekId,
    startAt: admin.firestore.Timestamp.fromDate(start),
    endAt: admin.firestore.Timestamp.fromDate(finish),
    totalAdditions: movies.reduce((sum, movie) => sum + movie.additions, 0),
    movies,
    generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    generatedBy: uid,
  };
  await db.collection("weekly_social_reports").doc(weekId).set(payload, { merge: true });

  return {
    ok: true,
    weekId,
    startAt: start.toISOString(),
    endAt: finish.toISOString(),
    totalAdditions: movies.reduce((sum, movie) => sum + movie.additions, 0),
    movies,
  };
});

// Mobil uygulamadaki Feed popüler filmler widget'ı için güvenli özet döndürür.
// Ham profile_movie_events ve diary kayıtları istemciye açılmaz.
exports.getWeeklyPopularMovies = onCall(async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Giriş yapmanız gerekiyor.");
  }

  const resultLimit = Math.min(
    10,
    Math.max(1, Number(request.data && request.data.resultLimit) || 10)
  );
  const maxWeeks = Math.min(
    3,
    Math.max(1, Number(request.data && request.data.maxWeeks) || 3)
  );
  const end = new Date();
  const istanbulNow = new Date(end.getTime() + (3 * 60 * 60 * 1000));
  const day = istanbulNow.getUTCDay() || 7;
  istanbulNow.setUTCDate(istanbulNow.getUTCDate() - day + 1);
  istanbulNow.setUTCHours(0, 0, 0, 0);
  const currentWeekStart = new Date(
    istanbulNow.getTime() - (3 * 60 * 60 * 1000)
  );
  const finish = new Date(
    currentWeekStart.getTime() + (7 * 24 * 60 * 60 * 1000)
  );
  const db = admin.firestore();

  async function loadRange(start) {
    const startTimestamp = admin.firestore.Timestamp.fromDate(start);
    const finishTimestamp = admin.firestore.Timestamp.fromDate(finish);
    const [legacyAdditions, diaryAdditions] = await Promise.all([
      db.collection("profile_movie_events")
        .where("addedAt", ">=", startTimestamp)
        .where("addedAt", "<", finishTimestamp)
        .get(),
      db.collectionGroup("diary")
        .where("recordedAt", ">=", startTimestamp)
        .where("recordedAt", "<", finishTimestamp)
        .get(),
    ]);

    const legacyItems = legacyAdditions.docs
      .map((doc) => doc.data() || {})
      .filter((item) => item.catalogType === "watched");
    const diaryItems = diaryAdditions.docs.map((doc) => ({
      ...(doc.data() || {}),
      userId: doc.ref.parent.parent && doc.ref.parent.parent.id,
      catalogType: "watched",
    }));

    const catalogCache = new Map();
    async function resolveCatalog(rawKey, rawTmdbId) {
      const key = String(rawKey || "").trim();
      const embeddedTmdb = /^tmdb:(\d+)$/.exec(key);
      const numericTmdb = Number(rawTmdbId) ||
        (embeddedTmdb ? Number(embeddedTmdb[1]) : Number(key)) || null;
      const cacheKey = `${key}|${numericTmdb || ""}`;
      if (catalogCache.has(cacheKey)) return catalogCache.get(cacheKey);

      const pending = (async () => {
        let catalogDoc = key
          ? await db.collection("catalog_films").doc(key).get()
          : null;
        if ((!catalogDoc || !catalogDoc.exists) && numericTmdb) {
          const snap = await db.collection("catalog_films")
            .where("tmdbId", "==", numericTmdb)
            .limit(1)
            .get();
          catalogDoc = snap.empty ? null : snap.docs[0];
        }
        const data = catalogDoc && catalogDoc.exists
          ? catalogDoc.data() || {}
          : {};
        const tmdbId = Number(data.tmdbId) || numericTmdb;
        return {
          id: tmdbId
            ? `tmdb:${tmdbId}`
            : (catalogDoc && catalogDoc.exists ? catalogDoc.id : key),
          tmdbId: tmdbId || null,
          title: cleanText(data.title, 140) || key,
          year: Number(data.year) || null,
          posterUrl: cleanText(data.posterUrl, 1200),
        };
      })();
      catalogCache.set(cacheKey, pending);
      return pending;
    }

    const resolvedLegacyItems = await Promise.all(
      legacyItems.map(async (item) => ({
        userId: String(item.userId || ""),
        movie: await resolveCatalog(item.movieKey, item.tmdbId),
      }))
    );
    const resolvedDiaryItems = diaryItems.map((item) => {
      const tmdbId = positiveInteger(item.tmdbId);
      const movieKey = cleanText(item.movieKey, 300);
      return {
        userId: String(item.userId || ""),
        movie: {
          id: tmdbId ? `tmdb:${tmdbId}` : movieKey,
          tmdbId: tmdbId || null,
          title: cleanText(item.title, 140) || movieKey,
          year: positiveInteger(item.releaseYear),
          posterUrl: cleanText(item.posterUrl, 1200),
        },
      };
    });

    const counts = new Map();
    [...resolvedLegacyItems, ...resolvedDiaryItems].forEach(({ userId, movie }) => {
      if (!movie.id) return;
      const current = counts.get(movie.id) || {
        ...movie,
        viewers: new Set(),
      };
      current.viewers.add(userId || `anonymous:${current.viewers.size}`);
      counts.set(movie.id, current);
    });

    return [...counts.values()]
      .map(({ viewers, ...movie }) => ({ ...movie, additions: viewers.size }))
      .sort(
        (a, b) =>
          b.additions - a.additions || a.title.localeCompare(b.title, "tr")
      );
  }

  let movies = [];
  let usedWeeks = 1;
  for (let weekSpan = 1; weekSpan <= maxWeeks; weekSpan += 1) {
    const start = new Date(
      currentWeekStart.getTime() -
        ((weekSpan - 1) * 7 * 24 * 60 * 60 * 1000)
    );
    movies = await loadRange(start);
    usedWeeks = weekSpan;
    if (movies.length >= resultLimit || weekSpan === maxWeeks) break;
  }

  return {
    ok: true,
    usedWeeks,
    movies: movies.slice(0, resultLimit),
  };
});

// Admin sosyal medya stüdyosundaki film ızgarası ve puan sıralaması için TMDB
// detaylarını tek istekte hazırlar. İstemci ayrı ayrı TMDB çağrısı yapmaz.
exports.getSocialGridMovies = onCall(
  { secrets: ["TMDB_ACCESS_TOKEN"] },
  async (request) => {
    await assertNewsEditor(request.auth && request.auth.uid);
    const rawIds = Array.isArray(request.data && request.data.ids)
      ? request.data.ids
      : [];
    const ids = [...new Set(
      rawIds
        .map((value) => Number(value))
        .filter((value) => Number.isInteger(value) && value > 0)
    )];
    if (!ids.length) {
      throw new HttpsError("invalid-argument", "En az bir geçerli TMDB film linki gerekli.");
    }
    if (ids.length > 36) {
      throw new HttpsError("invalid-argument", "Tek görselde en fazla 36 film kullanılabilir.");
    }

    const token = process.env.TMDB_ACCESS_TOKEN;
    const results = await Promise.all(ids.map(async (id) => {
      try {
        const response = await axios.get(`https://api.themoviedb.org/3/movie/${id}`, {
          params: { language: "en-US" },
          headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
        });
        const movie = response.data || {};
        const displayTitle = movie.original_language === "tr"
          ? movie.original_title
          : movie.title;
        return {
          id,
          title: cleanText(displayTitle || movie.original_title, 160) || `TMDB ${id}`,
          year: /^\d{4}/.test(String(movie.release_date || ""))
            ? Number(String(movie.release_date).slice(0, 4))
            : null,
          posterUrl: movie.poster_path
            ? `https://image.tmdb.org/t/p/w500${movie.poster_path}`
            : "",
          heroPosterUrl: movie.poster_path
            ? `https://image.tmdb.org/t/p/w780${movie.poster_path}`
            : "",
          voteAverage: Number.isFinite(Number(movie.vote_average))
            ? Number(Number(movie.vote_average).toFixed(1))
            : 0,
        };
      } catch (error) {
        console.error("Sosyal grid TMDB hatası:", id, error.message);
        return null;
      }
    }));

    return {
      movies: results.filter(Boolean),
      missingIds: ids.filter((id, index) => !results[index]),
    };
  }
);

// ==================================================================
// BOT ADMIN PANELİ ERİŞİMİ
// CineBot AI (cinematchbotai) backend'i Firebase dışında (Render'da
// SQLite ile) çalıştığı için oradaki veriye Firestore üzerinden değil,
// doğrudan REST üzerinden erişilir. Panel, bu backend'in admin uçlarını
// (/api/admin/...) çağırmak için gereken base URL + gizli anahtarı
// SADECE yetkili admin kullanıcılara, giriş yaptıktan sonra bu callable
// üzerinden verir -- anahtar hiçbir zaman istemci kaynak koduna gömülmez.
// Gerekli secret'lar: BOTAI_API_BASE, BOTAI_ADMIN_KEY
// (firebase functions:secrets:set BOTAI_API_BASE / BOTAI_ADMIN_KEY)
// ==================================================================
exports.getBotAdminAccess = onCall(
  { secrets: ["BOTAI_API_BASE", "BOTAI_ADMIN_KEY"] },
  async (request) => {
    await assertBotAdmin(request.auth && request.auth.uid);

    const baseUrl = process.env.BOTAI_API_BASE;
    const key = process.env.BOTAI_ADMIN_KEY;
    if (!baseUrl || !key) {
      throw new HttpsError(
        "failed-precondition",
        "Bot admin paneli için sunucu tarafında BOTAI_API_BASE / BOTAI_ADMIN_KEY tanımlı değil."
      );
    }

    return { baseUrl, key };
  }
);

function blogTimestampMillis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : null;
}

function serializeBlogPost(id, data, includeContent = false) {
  const serialized = {
    id,
    title: cleanText(data.title, 180),
    slug: cleanText(data.slug, 120),
    excerpt: cleanText(data.excerpt, 360),
    category: cleanText(data.category, 40),
    tags: Array.isArray(data.tags) ? data.tags : [],
    movies: Array.isArray(data.movies) ? data.movies : [],
    coverImageUrl: cleanHttpsUrl(data.coverImageUrl, 1800),
    status: ["draft", "published", "archived"].includes(data.status)
      ? data.status
      : "draft",
    authorId: cleanText(data.authorId, 128),
    authorName: cleanText(data.authorName, 100),
    authorUsername: cleanText(data.authorUsername, 80),
    authorPhotoUrl: cleanHttpsUrl(data.authorPhotoUrl, 1400),
    readingMinutes: Number(data.readingMinutes) || 0,
    revision: Number(data.revision) || 0,
    createdAtMs: blogTimestampMillis(data.createdAt),
    updatedAtMs: blogTimestampMillis(data.updatedAt),
    publishedAtMs: blogTimestampMillis(data.publishedAt),
  };
  if (includeContent) {
    serialized.contentHtml = typeof data.contentHtml === "string" ? data.contentHtml : "";
    serialized.images = Array.isArray(data.images) ? data.images : [];
  }
  return serialized;
}

exports.listBlogPosts = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  const access = await assertBlogEditor(uid, request.auth && request.auth.token);
  const requestedLimit = Number(request.data && request.data.limit);
  const limit = Number.isInteger(requestedLimit)
    ? Math.min(100, Math.max(10, requestedLimit))
    : 30;
  const db = admin.firestore();
  let docs;
  let hasMore;
  if (access.canManageAll) {
    const snapshot = await db.collection("blog_posts")
      .orderBy("updatedAt", "desc")
      .limit(limit + 1)
      .get();
    hasMore = snapshot.docs.length > limit;
    docs = snapshot.docs.slice(0, limit);
  } else {
    const snapshot = await db.collection("blog_posts")
      .where("authorId", "==", uid)
      .get();
    const sortedDocs = snapshot.docs
      .sort((left, right) => {
        const leftMs = blogTimestampMillis(left.data().updatedAt) || 0;
        const rightMs = blogTimestampMillis(right.data().updatedAt) || 0;
        return rightMs - leftMs;
      });
    hasMore = sortedDocs.length > limit;
    docs = sortedDocs.slice(0, limit);
  }
  return {
    posts: docs.map((doc) => serializeBlogPost(doc.id, doc.data() || {})),
    hasMore,
  };
});

exports.getBlogPost = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  const access = await assertBlogEditor(uid, request.auth && request.auth.token);
  const id = cleanText(request.data && request.data.id, 120);
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(id)) {
    throw new HttpsError("invalid-argument", "Blog yazısı kimliği geçersiz.");
  }
  const snap = await admin.firestore().collection("blog_posts").doc(id).get();
  if (!snap.exists) throw new HttpsError("not-found", "Blog yazısı bulunamadı.");
  const post = snap.data() || {};
  if (post.authorId !== uid && !access.canManageAll) {
    throw new HttpsError("permission-denied", "Bu blog yazısını görüntüleyemezsiniz.");
  }
  return { post: serializeBlogPost(snap.id, post, true) };
});

async function assertBlogManager(request) {
  const access = await assertBlogEditor(
    request.auth && request.auth.uid,
    request.auth && request.auth.token
  );
  if (!access.canManageAll) {
    throw new HttpsError("permission-denied", "Blogger yetkilerini yalnızca yöneticiler değiştirebilir.");
  }
  return access;
}

function serializeBloggerCandidate(doc, activeEditorIds = new Set(), blockedEditorIds = new Set()) {
  const data = doc.data() || {};
  const username = cleanText(data.username || data.handle, 80).replace(/^@/, "");
  return {
    uid: doc.id,
    displayName: cleanText(data.displayName || data.name || username, 100) || "CineMatch Kullanıcısı",
    username,
    photoUrl: cleanHttpsUrl(data.photoURL || data.photoUrl || data.profileImageUrl, 1400),
    isBlogEditor: activeEditorIds.has(doc.id) ||
      (!blockedEditorIds.has(doc.id) && ["admin", "blogger", "blogEditor"].includes(data.role)),
  };
}

exports.searchBlogUsers = onCall(async (request) => {
  await assertBlogManager(request);
  const rawQuery = cleanText(request.data && request.data.query, 100).replace(/^@/, "");
  const query = rawQuery.toLocaleLowerCase("tr-TR");
  if (query.length < 2) {
    throw new HttpsError("invalid-argument", "Kullanıcı araması en az 2 karakter olmalı.");
  }

  const db = admin.firestore();
  const lookups = ["username_lc", "displayName_lc"].map((field) =>
    db.collection("users")
      .orderBy(field)
      .startAt(query)
      .endAt(`${query}\uf8ff`)
      .limit(8)
      .get()
  );
  if (/^[A-Za-z0-9_-]{20,128}$/.test(rawQuery)) {
    lookups.push(db.collection("users").where(admin.firestore.FieldPath.documentId(), "==", rawQuery).get());
  }
  const snapshots = await Promise.all(lookups);
  const usersById = new Map();
  snapshots.forEach((snapshot) => snapshot.docs.forEach((doc) => usersById.set(doc.id, doc)));
  const userDocs = [...usersById.values()].slice(0, 12);
  const editorDocs = await Promise.all(
    userDocs.map((doc) => db.collection("blog_editors").doc(doc.id).get())
  );
  const activeIds = new Set(
    editorDocs.filter((doc) => doc.exists && doc.data().active !== false).map((doc) => doc.id)
  );
  const blockedIds = new Set(
    editorDocs.filter((doc) => doc.exists && doc.data().active === false).map((doc) => doc.id)
  );
  return {
    users: userDocs.map((doc) => serializeBloggerCandidate(doc, activeIds, blockedIds)),
  };
});

exports.listBlogEditors = onCall(async (request) => {
  await assertBlogManager(request);
  const db = admin.firestore();
  const [editorSnapshot, roleSnapshot] = await Promise.all([
    db.collection("blog_editors").limit(100).get(),
    db.collection("users").where("role", "in", ["blogger", "blogEditor"]).limit(100).get(),
  ]);
  const activeDocs = editorSnapshot.docs.filter((doc) => doc.data().active !== false);
  const blockedIds = new Set(
    editorSnapshot.docs.filter((doc) => doc.data().active === false).map((doc) => doc.id)
  );
  const userIds = new Set(activeDocs.map((doc) => doc.id));
  roleSnapshot.docs.forEach((doc) => {
    if (!blockedIds.has(doc.id)) userIds.add(doc.id);
  });
  const userDocs = await Promise.all(
    [...userIds].map((uid) => db.collection("users").doc(uid).get())
  );
  const users = userDocs
    .filter((doc) => doc.exists)
    .map((doc) => serializeBloggerCandidate(doc, userIds))
    .sort((left, right) => left.displayName.localeCompare(right.displayName, "tr"));
  return { users };
});

exports.setBlogEditor = onCall(async (request) => {
  await assertBlogManager(request);
  const uid = cleanText(request.data && request.data.uid, 128);
  const active = request.data && request.data.active === true;
  if (!/^[A-Za-z0-9_-]{20,128}$/.test(uid)) {
    throw new HttpsError("invalid-argument", "Kullanıcı kimliği geçersiz.");
  }
  const db = admin.firestore();
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) throw new HttpsError("not-found", "CineMatch kullanıcısı bulunamadı.");
  await db.collection("blog_editors").doc(uid).set({
    active,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: request.auth.uid,
  }, { merge: true });
  return { ok: true, uid, active };
});

exports.searchBlogMovies = onCall(
  { secrets: ["TMDB_ACCESS_TOKEN"] },
  async (request) => {
    await assertBlogEditor(
      request.auth && request.auth.uid,
      request.auth && request.auth.token
    );
    const query = cleanText(request.data && request.data.query, 120);
    if (query.length < 2) {
      throw new HttpsError("invalid-argument", "Film araması en az 2 karakter olmalı.");
    }

    try {
      const response = await axios.get("https://api.themoviedb.org/3/search/movie", {
        params: {
          query,
          language: "tr-TR",
          page: "1",
          include_adult: "false",
        },
        headers: {
          Authorization: `Bearer ${process.env.TMDB_ACCESS_TOKEN}`,
          Accept: "application/json",
        },
      });
      const results = Array.isArray(response.data && response.data.results)
        ? response.data.results
        : [];
      return {
        movies: results.slice(0, 12).map((movie) => ({
          tmdbId: Number(movie.id),
          title: cleanText(movie.title || movie.original_title, 180),
          originalTitle: cleanText(movie.original_title, 180),
          year: /^\d{4}/.test(String(movie.release_date || ""))
            ? Number(String(movie.release_date).slice(0, 4))
            : null,
          posterPath: /^\/[A-Za-z0-9._/-]+$/.test(String(movie.poster_path || ""))
            ? String(movie.poster_path)
            : "",
          posterUrl: movie.poster_path
            ? `https://image.tmdb.org/t/p/w342${movie.poster_path}`
            : "",
        })).filter((movie) => Number.isInteger(movie.tmdbId) && movie.tmdbId > 0),
      };
    } catch (error) {
      console.error("Blog TMDB arama hatası:", error.message);
      throw new HttpsError("internal", "TMDB film araması şu anda tamamlanamadı.");
    }
  }
);

exports.saveBlogPost = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  const access = await assertBlogEditor(uid, request.auth && request.auth.token);
  const data = request.data || {};
  const title = cleanText(data.title, 180);
  const status = ["draft", "published", "archived"].includes(data.status)
    ? data.status
    : "draft";
  const postId = cleanText(data.id, 120);
  if (!title) throw new HttpsError("invalid-argument", "Yazı başlığı gerekli.");
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(postId)) {
    throw new HttpsError("invalid-argument", "Blog yazısı kimliği geçersiz.");
  }

  const contentHtml = sanitizeBlogContent(data.contentHtml);
  const contentText = sanitizeHtml(contentHtml, {
    allowedTags: [],
    allowedAttributes: {},
  }).replace(/\s+/g, " ").trim().slice(0, 120000);
  if (status === "published" && contentText.length < 20) {
    throw new HttpsError(
      "invalid-argument",
      "Yayınlamak için en az 20 karakterlik bir yazı içeriği gerekli."
    );
  }

  const db = admin.firestore();
  const ref = db.collection("blog_posts").doc(postId);
  const existingSnap = await ref.get();
  const existing = existingSnap.exists ? existingSnap.data() || {} : {};
  if (existingSnap.exists && existing.authorId !== uid && !access.canManageAll) {
    throw new HttpsError("permission-denied", "Yalnızca kendi blog yazılarınızı düzenleyebilirsiniz.");
  }

  const editingAnotherAuthor = existingSnap.exists && existing.authorId !== uid;
  const author = editingAnotherAuthor
    ? {
        uid: existing.authorId,
        displayName: cleanText(existing.authorName, 100) || "CineMatch Blogger",
        username: cleanText(existing.authorUsername, 80),
        photoUrl: cleanHttpsUrl(existing.authorPhotoUrl, 1400),
      }
    : access.profile;
  const now = admin.firestore.FieldValue.serverTimestamp();
  const slug = makeSlug(data.slug || title) || postId;
  const tags = Array.isArray(data.tags)
    ? [...new Set(data.tags.map((tag) => cleanText(tag, 40)).filter(Boolean))].slice(0, 12)
    : [];
  const movies = normalizeBlogMovies(data.movies);
  const images = normalizeBlogImages(data.images, postId);
  const activeImagePaths = new Set(images.map((image) => image.path));
  const removedImagePaths = Array.isArray(existing.images)
    ? existing.images
      .map((image) => cleanText(image && image.path, 600))
      .filter((path) => (
        /^blog_images\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+\/[A-Za-z0-9_.-]+$/.test(path) &&
        path.split("/")[2] === postId &&
        !activeImagePaths.has(path)
      ))
    : [];
  const excerpt = cleanText(data.excerpt, 360) || contentText.slice(0, 220);
  const coverImageUrl = cleanHttpsUrl(data.coverImageUrl, 1800) ||
    (images[0] ? images[0].url : "");
  const category = cleanText(data.category, 40) || "İnceleme";
  const readingMinutes = contentText
    ? Math.max(1, Math.ceil(contentText.split(/\s+/).length / 220))
    : 0;

  const payload = {
    schemaVersion: 1,
    title,
    slug,
    excerpt,
    contentHtml,
    contentText,
    category,
    tags,
    movies,
    tmdbIds: movies.map((movie) => movie.tmdbId),
    images,
    coverImageUrl,
    status,
    readingMinutes,
    authorId: author.uid,
    authorName: author.displayName,
    authorUsername: author.username,
    authorPhotoUrl: author.photoUrl,
    updatedAt: now,
    updatedBy: uid,
    updatedByName: access.profile.displayName,
    revision: admin.firestore.FieldValue.increment(1),
  };
  if (!existingSnap.exists) payload.createdAt = now;
  if (status === "published" && !existing.publishedAt) payload.publishedAt = now;

  const publicPayload = {
    schemaVersion: 1,
    title,
    slug,
    excerpt,
    contentHtml,
    contentText,
    category,
    tags,
    movies,
    tmdbIds: payload.tmdbIds,
    images,
    coverImageUrl,
    readingMinutes,
    authorId: author.uid,
    authorName: author.displayName,
    authorUsername: author.username,
    authorPhotoUrl: author.photoUrl,
    publishedAt: existing.publishedAt || now,
    updatedAt: now,
  };

  const batch = db.batch();
  batch.set(ref, payload, { merge: true });
  const publicRef = db.collection("public_blog_posts").doc(postId);
  if (status === "published") {
    batch.set(publicRef, publicPayload, { merge: true });
  } else {
    batch.delete(publicRef);
  }
  await batch.commit();
  if (removedImagePaths.length) {
    const bucket = admin.storage().bucket();
    const cleanupResults = await Promise.allSettled(
      removedImagePaths.map((path) => bucket.file(path).delete({ ignoreNotFound: true }))
    );
    cleanupResults.forEach((result, index) => {
      if (result.status === "rejected") {
        console.error("Kullanılmayan blog görseli silinemedi:", removedImagePaths[index], result.reason);
      }
    });
  }
  return { ok: true, id: postId, slug, status };
});

exports.deleteBlogPost = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  const access = await assertBlogEditor(uid, request.auth && request.auth.token);
  const id = cleanText(request.data && request.data.id, 120);
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(id)) {
    throw new HttpsError("invalid-argument", "Blog yazısı kimliği geçersiz.");
  }

  const db = admin.firestore();
  const ref = db.collection("blog_posts").doc(id);
  const snap = await ref.get();
  if (!snap.exists) return { ok: true };
  const post = snap.data() || {};
  if (post.authorId !== uid && !access.canManageAll) {
    throw new HttpsError("permission-denied", "Yalnızca kendi blog yazılarınızı silebilirsiniz.");
  }

  const batch = db.batch();
  batch.delete(ref);
  batch.delete(db.collection("public_blog_posts").doc(id));
  await batch.commit();

  const bucket = admin.storage().bucket();
  const storedPaths = Array.isArray(post.images)
    ? post.images.map((image) => cleanText(image && image.path, 600))
      .filter((path) => path.startsWith("blog_images/") && path.split("/").includes(id))
    : [];
  await Promise.allSettled([
    bucket.deleteFiles({ prefix: `blog_images/${post.authorId}/${id}/` }),
    ...storedPaths.map((path) => bucket.file(path).delete({ ignoreNotFound: true })),
  ]);
  return { ok: true };
});

exports.saveNewsArticle = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertNewsEditor(uid);

  const data = request.data || {};
  const title = cleanText(data.title, 180);
  const body = cleanText(data.body, 50000);
  const status = ["draft", "published", "archived"].includes(data.status)
    ? data.status
    : "draft";

  if (!title) throw new HttpsError("invalid-argument", "Başlık gerekli.");
  if (status === "published" && !body) {
    throw new HttpsError("invalid-argument", "Yayınlamak için haber metni gerekli.");
  }

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const articleId = cleanText(data.id, 120) || db.collection("news_articles").doc().id;
  const slug = makeSlug(data.slug || title) || articleId;
  const tags = Array.isArray(data.tags)
    ? data.tags.map((tag) => cleanText(tag, 40)).filter(Boolean).slice(0, 12)
    : [];

  const payload = {
    title,
    slug,
    summary: cleanText(data.summary, 320),
    body,
    category: cleanText(data.category, 40) || "Haber",
    movieTitle: cleanText(data.movieTitle, 120),
    imageUrl: cleanText(data.imageUrl, 1200),
    sourceUrl: cleanText(data.sourceUrl, 1200),
    tags,
    status,
    updatedAt: now,
    updatedBy: uid,
  };

  const ref = db.collection("news_articles").doc(articleId);
  const snap = await ref.get();
  if (!snap.exists) {
    payload.createdAt = now;
    payload.authorId = uid;
    payload.authorName = cleanText(data.authorName, 80) || "CineMatch Editör";
  }
  if (status === "published" && !snap.data()?.publishedAt) {
    payload.publishedAt = now;
  }

  await ref.set(payload, { merge: true });
  if (status === "published") {
    const publicPayload = {
      title: payload.title,
      slug: payload.slug,
      summary: payload.summary,
      body: payload.body,
      category: payload.category,
      movieTitle: payload.movieTitle,
      imageUrl: payload.imageUrl,
      sourceUrl: payload.sourceUrl,
      tags: payload.tags,
      authorName: payload.authorName || snap.data()?.authorName || "CineMatch Editör",
      publishedAt: payload.publishedAt || snap.data()?.publishedAt || now,
      updatedAt: now,
    };
    await db.collection("public_news").doc(articleId).set(publicPayload, { merge: true });
  } else {
    await db.collection("public_news").doc(articleId).delete().catch(() => null);
  }
  return { ok: true, id: articleId, slug };
});

exports.deleteNewsArticle = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertNewsEditor(uid);

  const id = cleanText(request.data && request.data.id, 120);
  if (!id) throw new HttpsError("invalid-argument", "Haber ID gerekli.");

  await admin.firestore().collection("news_articles").doc(id).delete();
  await admin.firestore().collection("public_news").doc(id).delete().catch(() => null);
  return { ok: true };
});

exports.getAnnouncement = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertNewsEditor(uid);

  const doc = await admin.firestore().collection("system").doc("announcement").get();
  return { announcement: doc.exists ? doc.data() : null };
});

exports.saveAnnouncement = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertNewsEditor(uid);

  const data = request.data || {};
  const title = cleanText(data.title, 160);
  const message = cleanText(data.message, 3000);
  const imageUrl = cleanText(data.imageUrl, 1200);
  const isActive = data.isActive === true;

  if (isActive && (!title || !message)) {
    throw new HttpsError("invalid-argument", "Aktif duyuru icin baslik ve mesaj gerekli.");
  }

  const db = admin.firestore();
  const ref = db.collection("system").doc("announcement");
  const snap = await ref.get();
  const previous = snap.exists ? snap.data() : {};
  const previousItems = Array.isArray(previous.items) ? previous.items : [];
  const id = cleanText(data.id, 120) || `announcement_${Date.now()}`;
  const now = admin.firestore.FieldValue.serverTimestamp();

  let items = previousItems;
  if (title || message) {
    const item = {
      id,
      title,
      message,
      imageUrl,
      date: admin.firestore.Timestamp.now(),
      updatedBy: uid,
    };

    items = [
      item,
      ...previousItems.filter((entry) => entry && entry.id !== id),
    ].slice(0, 30);
  }

  await ref.set({
    id,
    title,
    message,
    imageUrl,
    isActive,
    items,
    updatedAt: now,
    updatedBy: uid,
  }, { merge: true });

  return { ok: true, id };
});

exports.saveTriviaQuestion = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertTriviaEditor(uid);

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const data = normalizeTriviaQuestion(request.data || {});
  const questionId = cleanText(request.data && request.data.id, 120) ||
    db.collection("trivia_questions").doc().id;

  const count = await countTriviaQuestionsForWeek(db, data.weekId, questionId);
  if (count >= 10) {
    throw new HttpsError("failed-precondition", `${data.weekId} haftasi icin 10 soru siniri dolu.`);
  }

  const ref = db.collection("trivia_questions").doc(questionId);
  const snap = await ref.get();
  const payload = {
    ...data,
    updatedAt: now,
    updatedBy: uid,
  };
  if (!snap.exists) {
    payload.createdAt = now;
    payload.createdBy = uid;
  }

  await ref.set(payload, { merge: true });
  return { ok: true, id: questionId };
});

exports.deleteTriviaQuestion = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertTriviaEditor(uid);

  const id = cleanText(request.data && request.data.id, 120);
  if (!id) throw new HttpsError("invalid-argument", "Soru ID gerekli.");

  await admin.firestore().collection("trivia_questions").doc(id).delete();
  return { ok: true };
});

exports.bulkSaveTriviaQuestions = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  await assertTriviaEditor(uid);

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const items = Array.isArray(request.data && request.data.questions)
    ? request.data.questions
    : [];
  if (!items.length) {
    throw new HttpsError("invalid-argument", "Yuklenecek soru bulunamadi.");
  }
  if (items.length > 10) {
    throw new HttpsError("invalid-argument", "Tek seferde en fazla 10 soru yuklenebilir.");
  }

  const normalized = items.map((item) => normalizeTriviaQuestion(item));
  const weekIds = [...new Set(normalized.map((item) => item.weekId))];
  if (weekIds.length !== 1) {
    throw new HttpsError("invalid-argument", "Toplu yuklemede tum sorular ayni weekId icin olmali.");
  }

  const weekId = weekIds[0];
  const count = await countTriviaQuestionsForWeek(db, weekId);
  if (count + normalized.length > 10) {
    throw new HttpsError("failed-precondition", `${weekId} haftasi 10 soru sinirini asiyor.`);
  }

  const batch = db.batch();
  const ids = [];
  normalized.forEach((item) => {
    const ref = db.collection("trivia_questions").doc();
    ids.push(ref.id);
    batch.set(ref, {
      ...item,
      createdAt: now,
      updatedAt: now,
      createdBy: uid,
      updatedBy: uid,
    });
  });

  await batch.commit();
  return { ok: true, ids };
});

// ==================================================================
// 1. GENEL TMDB PROXY (V2)
// ==================================================================
const TMDB_POSTER_BASE_URL = "https://image.tmdb.org/t/p";
const TMDB_LOGIN_POSTER_SIZE = "w342";

function positiveInteger(value) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function validPosterPath(value) {
  const path = cleanText(value, 500);
  return /^\/[A-Za-z0-9._-]+$/.test(path) ? path : "";
}

function posterPathFromTmdbUrl(value) {
  const candidate = cleanHttpsUrl(value, 1400);
  if (!candidate) return "";
  try {
    const parsed = new URL(candidate);
    if (parsed.hostname !== "image.tmdb.org") return "";
    const match = parsed.pathname.match(
      /^\/t\/p\/(?:w\d+|original)(\/[A-Za-z0-9._-]+)$/
    );
    return match ? match[1] : "";
  } catch (error) {
    return "";
  }
}

function tmdbPosterUrl(path, size = TMDB_LOGIN_POSTER_SIZE) {
  const safePath = validPosterPath(path);
  if (!safePath || !/^w\d+$/.test(size)) return "";
  return `${TMDB_POSTER_BASE_URL}/${size}${safePath}`;
}

function validCatalogKey(value) {
  const key = cleanText(value, 180).toLowerCase();
  if (/^film:[a-z0-9][a-z0-9-]{0,159}$/.test(key)) return key;
  if (/^tmdb:\d{1,12}$/.test(key)) return key;
  return "";
}

function validDocumentId(value) {
  const id = cleanText(value, 1500);
  return id && id !== "." && id !== ".." && !id.includes("/") ? id : "";
}

function catalogTitleKey(value) {
  return cleanText(value, 180)
    .normalize("NFKD")
    .toLocaleLowerCase("tr-TR")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/ı/g, "i")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

function movieYear(movie) {
  const releaseDate = cleanText(movie && movie.release_date, 20);
  return /^\d{4}/.test(releaseDate) ? Number(releaseDate.slice(0, 4)) : null;
}

function catalogDataMatchesMovie(existing, movie) {
  const tmdbId = positiveInteger(movie && movie.id);
  const existingTmdbId = positiveInteger(existing && existing.tmdbId);
  if (existingTmdbId && existingTmdbId !== tmdbId) return false;
  const existingTitle = catalogTitleKey(existing && existing.title);
  if (!existingTitle) return true;
  const trustedTitles = new Set([
    catalogTitleKey(movie && movie.title),
    catalogTitleKey(movie && movie.original_title),
  ].filter(Boolean));
  return trustedTitles.has(existingTitle);
}

function catalogKeyMatchesMovie(key, movie, requestedTitle) {
  const safeKey = validCatalogKey(key);
  const tmdbId = positiveInteger(movie && movie.id);
  if (!safeKey || !tmdbId) return false;
  if (safeKey === `tmdb:${tmdbId}`) return true;
  const year = movieYear(movie);
  const slugs = new Set([
    makeSlug(requestedTitle),
    makeSlug(movie && movie.title),
    makeSlug(movie && movie.original_title),
  ].filter(Boolean));
  for (const slug of slugs) {
    if (safeKey === `film:${slug}` ||
        safeKey === `film:${slug}-${tmdbId}` ||
        (year && safeKey === `film:${slug}-${year}`)) {
      return true;
    }
  }
  return false;
}

async function tmdbRequest(endpoint, params = {}) {
  const response = await axios.get(`https://api.themoviedb.org${endpoint}`, {
    params,
    headers: {
      Authorization: `Bearer ${process.env.TMDB_ACCESS_TOKEN}`,
      Accept: "application/json",
    },
  });
  return response.data || {};
}

async function resolveTmdbMovie({ tmdbId, imdbId, title, year }) {
  const id = positiveInteger(tmdbId);
  if (id) {
    try {
      return await tmdbRequest(`/3/movie/${id}`, { language: "tr-TR" });
    } catch (error) {
      console.error("TMDB film detayı alınamadı:", id, error.message);
      return null;
    }
  }

  const safeImdbId = cleanText(imdbId, 30);
  if (/^tt\d+$/.test(safeImdbId)) {
    try {
      const data = await tmdbRequest(`/3/find/${safeImdbId}`, {
        external_source: "imdb_id",
        language: "en-US",
      });
      const results = Array.isArray(data.movie_results) ? data.movie_results : [];
      if (results.length) return results[0];
    } catch (error) {
      console.error("TMDB IMDb araması başarısız:", safeImdbId, error.message);
    }
  }

  const query = cleanText(title, 180);
  if (!query) return null;
  try {
    const data = await tmdbRequest("/3/search/movie", {
      query,
      language: "en-US",
      include_adult: "false",
      page: "1",
      ...(positiveInteger(year) ? { primary_release_year: String(year) } : {}),
    });
    const results = Array.isArray(data.results) ? data.results : [];
    return results.find((movie) => positiveInteger(movie.id)) || null;
  } catch (error) {
    console.error("TMDB film araması başarısız:", query, error.message);
    return null;
  }
}

async function catalogRefForMovie(db, movie, requestedKey, requestedTitle) {
  const tmdbId = positiveInteger(movie.id);
  if (!tmdbId) return null;

  const byTmdb = await db.collection("catalog_films")
    .where("tmdbId", "==", tmdbId).limit(1).get();
  if (!byTmdb.empty) return byTmdb.docs[0].ref;

  const safeRequestedKey = validCatalogKey(requestedKey);
  if (safeRequestedKey) {
    const requestedRef = db.collection("catalog_films").doc(safeRequestedKey);
    const requestedDoc = await requestedRef.get();
    if (!requestedDoc.exists &&
        catalogKeyMatchesMovie(safeRequestedKey, movie, requestedTitle)) {
      return requestedRef;
    }
    if (requestedDoc.exists) {
      const existing = requestedDoc.data() || {};
      if (catalogDataMatchesMovie(existing, movie)) {
        return requestedRef;
      }
    }
  }

  const title = cleanText(movie.original_title || movie.title, 180);
  const slug = makeSlug(title) || `tmdb-${tmdbId}`;
  const year = movieYear(movie);
  const candidates = [
    `film:${slug}`,
    year ? `film:${slug}-${year}` : "",
    `film:${slug}-${tmdbId}`,
    `tmdb:${tmdbId}`,
  ].filter(Boolean);

  for (const key of candidates) {
    const ref = db.collection("catalog_films").doc(key);
    const doc = await ref.get();
    if (!doc.exists || positiveInteger(doc.data().tmdbId) === tmdbId) return ref;
  }
  return db.collection("catalog_films").doc(`tmdb:${tmdbId}`);
}

async function upsertResolvedTmdbMovie({
  db,
  movie,
  catalogKey,
  requestedTitle,
  source = "tmdb",
}) {
  const tmdbId = positiveInteger(movie && movie.id);
  if (!tmdbId) return null;
  const ref = await catalogRefForMovie(db, movie, catalogKey, requestedTitle);
  if (!ref) return null;

  const posterPath = validPosterPath(movie.poster_path);
  const title = cleanText(movie.title || requestedTitle || movie.original_title, 180);
  const originalTitle = cleanText(movie.original_title, 180);
  const year = movieYear(movie);
  const imdbId = /^tt\d+$/.test(cleanText(movie.imdb_id, 30))
    ? cleanText(movie.imdb_id, 30)
    : "";
  const posterUrl = tmdbPosterUrl(posterPath);
  const popularity = Number(movie.popularity);
  const voteAverage = Number(movie.vote_average);

  const payload = {
    tmdbId,
    title: title || `TMDB ${tmdbId}`,
    titleLc: catalogTitleKey(title || originalTitle),
    canonicalKey: ref.id,
    source: "tmdb",
    importSource: source,
    aliases: admin.firestore.FieldValue.arrayUnion(
      `tmdb:${tmdbId}`,
      ...(imdbId ? [`imdb:${imdbId}`] : []),
    ),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(originalTitle ? { originalTitle } : {}),
    ...(year ? { year } : {}),
    ...(imdbId ? { imdbId } : {}),
    ...(Number.isFinite(popularity) ? { popularity } : {}),
    ...(Number.isFinite(voteAverage) ? { voteAverage } : {}),
    ...(posterPath ? {
      posterPath,
      posterUrl,
      posterSource: "tmdb",
    } : {
      posterPath: admin.firestore.FieldValue.delete(),
      posterUrl: admin.firestore.FieldValue.delete(),
      posterSource: "missing",
    }),
  };

  await ref.set(payload, { merge: true });

  // Kullanıcı rafları eski Letterboxd anahtarını tutuyor olabilir. Aynı filme
  // ait olduğu doğrulanırsa o belgeyi de güvenilir TMDB verisiyle zenginleştir;
  // böylece anahtar göçü beklemeden eski profiller çalışmaya devam eder.
  const legacyKey = validCatalogKey(catalogKey);
  if (legacyKey && legacyKey !== ref.id) {
    const legacyRef = db.collection("catalog_films").doc(legacyKey);
    const legacyDoc = await legacyRef.get();
    const requestedTitleKey = catalogTitleKey(requestedTitle);
    const trustedMovieTitles = new Set([
      catalogTitleKey(movie.title),
      catalogTitleKey(movie.original_title),
    ].filter(Boolean));
    const canCreateLetterboxdAlias = source === "letterboxd" &&
      requestedTitleKey.length > 0 &&
      trustedMovieTitles.has(requestedTitleKey) &&
      catalogKeyMatchesMovie(legacyKey, movie, requestedTitle);
    const canUpdateExistingAlias = legacyDoc.exists &&
      catalogDataMatchesMovie(legacyDoc.data() || {}, movie);
    if (canCreateLetterboxdAlias || canUpdateExistingAlias) {
      await legacyRef.set({
        ...payload,
        canonicalKey: ref.id,
        duplicateOf: ref.id,
      }, { merge: true });
    }
  }

  return {
    docId: ref.id,
    tmdbId,
    title: payload.title,
    originalTitle,
    year,
    posterPath,
    posterUrl,
  };
}

async function resolveAndUpsertCatalogMovie({
  db,
  tmdbId,
  imdbId,
  title,
  year,
  catalogKey,
  source,
}) {
  const movie = await resolveTmdbMovie({ tmdbId, imdbId, title, year });
  if (!movie) return null;
  return upsertResolvedTmdbMovie({
    db,
    movie,
    catalogKey,
    requestedTitle: title,
    source,
  });
}

async function removeUntrustedCatalogPoster(db, catalogKey, title, year) {
  const safeKey = validCatalogKey(catalogKey);
  if (!safeKey) return;
  const ref = db.collection("catalog_films").doc(safeKey);
  const doc = await ref.get();
  const existing = doc.exists ? doc.data() || {} : {};
  if (posterPathFromTmdbUrl(existing.posterUrl)) return;
  await ref.set({
    ...(cleanText(title, 180) ? { title: cleanText(title, 180) } : {}),
    ...(positiveInteger(year) ? { year: positiveInteger(year) } : {}),
    canonicalKey: safeKey,
    source: cleanText(existing.source, 30) || "letterboxd",
    posterUrl: admin.firestore.FieldValue.delete(),
    posterPath: admin.firestore.FieldValue.delete(),
    posterSource: "missing",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

exports.resolveCatalogMovie = onCall(
  {
    secrets: ["TMDB_ACCESS_TOKEN"],
    timeoutSeconds: 120,
    // App Store'daki mevcut iOS sürümü App Attest tokenı üretemediğinde
    // onboarding tamamen kilitlenmemeli. Kimlik doğrulaması aşağıda zorunlu;
    // App Check yeni iOS sürümü yaygınlaştıktan sonra yeniden enforce edilebilir.
    enforceAppCheck: false,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");
    }
    const data = request.data || {};
    const tmdbId = positiveInteger(data.tmdbId);
    const imdbId = /^tt\d+$/.test(cleanText(data.imdbId, 30))
      ? cleanText(data.imdbId, 30)
      : "";
    const title = cleanText(data.title, 180);
    const year = positiveInteger(data.year);
    const catalogKey = validCatalogKey(data.catalogKey);
    if (!tmdbId && !imdbId && !title) {
      throw new HttpsError("invalid-argument", "TMDB kimliği veya film adı gerekli.");
    }

    const result = await resolveAndUpsertCatalogMovie({
      db: admin.firestore(),
      tmdbId,
      imdbId,
      title,
      year,
      catalogKey,
      source: "client",
    });
    return result ? { ok: true, ...result } : { ok: false };
  }
);

exports.importLetterboxdCatalog = onCall(
  { secrets: ["TMDB_ACCESS_TOKEN"], timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");
    }
    const rawFilms = Array.isArray(request.data && request.data.films)
      ? request.data.films.slice(0, 50)
      : [];
    const films = rawFilms.map((film) => ({
      catalogKey: validCatalogKey(film && film.key),
      title: cleanText(film && film.title, 180),
      year: positiveInteger(film && film.year),
      preferExisting: film && film.preferExisting === true,
    })).filter((film) => film.catalogKey && film.title);
    if (!films.length) {
      return { ok: true, resolved: 0, missing: 0, films: [] };
    }

    const db = admin.firestore();
    let cursor = 0;
    let resolved = 0;
    let missing = 0;
    const resolvedFilms = new Array(films.length);
    const existingByKey = new Map();
    const reusableFilms = films.filter((film) => film.preferExisting);
    if (reusableFilms.length) {
      const existingDocs = await db.getAll(...reusableFilms.map((film) =>
        db.collection("catalog_films").doc(film.catalogKey)
      ));
      existingDocs.forEach((doc) => existingByKey.set(doc.id, doc));
    }
    async function worker() {
      while (cursor < films.length) {
        const index = cursor++;
        const film = films[index];
        const existingDoc = existingByKey.get(film.catalogKey);
        const existing = existingDoc && existingDoc.exists
          ? existingDoc.data() || {}
          : {};
        const existingTmdbId = positiveInteger(existing.tmdbId);
        const existingTitle = cleanText(existing.title, 180);
        const existingPosterPath = validPosterPath(existing.posterPath);
        const existingPosterUrl = existingPosterPath
          ? tmdbPosterUrl(existingPosterPath)
          : cleanText(existing.posterUrl, 1200);
        if (existingTmdbId && existingTitle && existingPosterUrl) {
          resolved++;
          resolvedFilms[index] = {
            catalogKey: film.catalogKey,
            docId: cleanText(existing.canonicalKey, 500) || existingDoc.id,
            tmdbId: existingTmdbId,
            title: existingTitle,
            originalTitle: cleanText(existing.originalTitle, 180),
            year: positiveInteger(existing.year),
            posterPath: existingPosterPath,
            posterUrl: existingPosterUrl,
          };
          continue;
        }
        const result = await resolveAndUpsertCatalogMovie({
          db,
          title: film.title,
          year: film.year,
          catalogKey: film.catalogKey,
          source: "letterboxd",
        });
        if (result) {
          resolved++;
          resolvedFilms[index] = {
            catalogKey: film.catalogKey,
            ...result,
          };
        } else {
          missing++;
          await removeUntrustedCatalogPoster(
            db,
            film.catalogKey,
            film.title,
            film.year
          );
        }
      }
    }
    await Promise.all(Array.from({ length: Math.min(5, films.length) }, worker));
    return {
      ok: true,
      resolved,
      missing,
      films: resolvedFilms.filter(Boolean),
    };
  }
);

exports.backfillCatalogPosters = onCall(
  { secrets: ["TMDB_ACCESS_TOKEN"], timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    await assertNewsEditor(request.auth && request.auth.uid);
    const data = request.data || {};
    const limit = Math.min(Math.max(positiveInteger(data.limit) || 40, 1), 100);
    const cursor = validDocumentId(data.cursor);
    const db = admin.firestore();
    let query = db.collection("catalog_films")
      .orderBy(admin.firestore.FieldPath.documentId()).limit(limit);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();

    let normalized = 0;
    let resolved = 0;
    let missing = 0;
    for (const doc of snapshot.docs) {
      const film = doc.data() || {};
      const trustedPath = validPosterPath(film.posterPath) ||
        posterPathFromTmdbUrl(film.posterUrl);
      if (trustedPath) {
        await doc.ref.set({
          posterPath: trustedPath,
          posterUrl: tmdbPosterUrl(trustedPath),
          posterSource: "tmdb",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        normalized++;
        continue;
      }

      const result = await resolveAndUpsertCatalogMovie({
        db,
        tmdbId: film.tmdbId,
        title: film.title,
        year: film.year,
        catalogKey: doc.id,
        source: "backfill",
      });
      if (result) {
        resolved++;
      } else {
        missing++;
        await removeUntrustedCatalogPoster(db, doc.id, film.title, film.year);
      }
    }

    return {
      ok: true,
      scanned: snapshot.size,
      normalized,
      resolved,
      missing,
      nextCursor: snapshot.empty ? null : snapshot.docs[snapshot.docs.length - 1].id,
      hasMore: snapshot.size === limit,
    };
  }
);

exports.refreshLoginPosters = onCall(async (request) => {
  await assertNewsEditor(request.auth && request.auth.uid);
  const requestedLimit = positiveInteger(request.data && request.data.limit) || 30;
  const limit = Math.min(Math.max(requestedLimit, 12), 40);
  const db = admin.firestore();
  const [posterSourceSnap, sourceSnap] = await Promise.all([
    db.collection("catalog_films").where("posterSource", "==", "tmdb").limit(250).get(),
    db.collection("catalog_films").where("source", "==", "tmdb").limit(250).get(),
  ]);
  const candidates = new Map();
  [...posterSourceSnap.docs, ...sourceSnap.docs].forEach((doc) => {
    const film = doc.data() || {};
    const posterPath = validPosterPath(film.posterPath) ||
      posterPathFromTmdbUrl(film.posterUrl);
    const tmdbId = positiveInteger(film.tmdbId);
    if (!posterPath || !tmdbId) return;
    candidates.set(tmdbId, {
      tmdbId,
      title: cleanText(film.title, 180),
      posterPath,
      posterUrl: tmdbPosterUrl(posterPath),
      popularity: Number.isFinite(Number(film.popularity))
        ? Number(film.popularity)
        : 0,
    });
  });
  const selected = [...candidates.values()]
    .sort((a, b) => b.popularity - a.popularity || a.tmdbId - b.tmdbId)
    .slice(0, limit);
  if (selected.length < 12) {
    throw new HttpsError(
      "failed-precondition",
      "Login arka planı için en az 12 doğrulanmış TMDB posteri gerekli."
    );
  }

  const existing = await db.collection("login_posters").get();
  const batch = db.batch();
  existing.docs.forEach((doc) => batch.delete(doc.ref));
  selected.forEach((poster, index) => {
    batch.set(db.collection("login_posters").doc(String(poster.tmdbId)), {
      ...poster,
      enabled: true,
      order: index,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth.uid,
    });
  });
  await batch.commit();
  return { ok: true, count: selected.length };
});

exports.callTMDB = onCall({ secrets: ["TMDB_ACCESS_TOKEN"] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Oturum açmanız gerekiyor.');
  const { endpoint, params } = request.data;
  const token = process.env.TMDB_ACCESS_TOKEN;
  if (!endpoint) throw new HttpsError('invalid-argument', 'Endpoint gerekli.');

  try {
    const response = await axios.get(`https://api.themoviedb.org${endpoint}`, {
      params: { ...params, language: params && params.language ? params.language : 'tr-TR' },
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' }
    });
    return response.data;
  } catch (error) {
    console.error("TMDB Proxy Hatası:", endpoint, error.message);
    throw new HttpsError('internal', 'TMDB isteği başarısız oldu.');
  }
});

// ==================================================================
// 2. SEARCH MOVIES (V2)
// ==================================================================
exports.searchMovies = onCall({ secrets: ["TMDB_ACCESS_TOKEN"] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Giriş yapmalısın.');
  const query = request.data.query;
  const page = request.data.page || 1;
  const token = process.env.TMDB_ACCESS_TOKEN;

  try {
    const response = await axios.get(`https://api.themoviedb.org/3/search/movie`, {
      params: { query: query, language: 'tr-TR', page: page.toString(), include_adult: 'false' },
      headers: { Authorization: `Bearer ${token}` }
    });
    return response.data;
  } catch (error) {
    console.error("Search hatası:", error);
    throw new HttpsError('internal', 'Arama hatası.');
  }
});

// ==================================================================
// 3. SOSYAL BİLDİRİMLER (V1 Trigger)
// ==================================================================
function pushString(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  return String(value).slice(0, 900);
}

function pushTime(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value._seconds) return value._seconds * 1000;
  return 0;
}

function isInvalidFcmToken(error) {
  const code = error && error.code;
  return [
    "messaging/invalid-registration-token",
    "messaging/registration-token-not-registered",
    "messaging/invalid-argument",
  ].includes(code);
}

async function sendPushToUser(uid, message) {
  if (!uid) return null;

  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();
  const userData = userDoc.data() || {};
  if (userData.notificationsEnabled === false) return null;

  const tokensSnap = await userRef.collection("fcmTokens").get();
  if (tokensSnap.empty) return null;

  const tokens = tokensSnap.docs.map((doc) => doc.id).filter(Boolean);
  if (!tokens.length) return null;

  const data = {};
  Object.entries(message.data || {}).forEach(([key, value]) => {
    data[key] = pushString(value);
  });

  const type = data.type || "social";
  const rawGroupTarget = type === "chat"
    ? (data.chatId || data.actorId || uid)
    : (["like", "comment"].includes(type)
      ? (data.postId || data.notificationId || uid)
      : (type === "follow" ? "follows" : (data.clubId || data.notificationId || uid)));
  const groupDigest = crypto
    .createHash("sha1")
    .update(`${type}:${rawGroupTarget}`)
    .digest("hex")
    .slice(0, 20);
  const groupKey = `cinematch_${type}_${groupDigest}`;
  data.groupKey = groupKey;
  const parsedCount = Number(data.unreadCount || data.count || 1);
  const notificationCount = Number.isInteger(parsedCount) && parsedCount > 0
    ? Math.min(parsedCount, 999)
    : 1;

  const result = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: message.notification,
    data,
    android: {
      priority: "high",
      collapseKey: type === "chat" ? "cinematch_chat" : "cinematch_social",
      notification: {
        channelId: type === "chat" ? "cinematch_chat" : "cinematch_social",
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
        icon: "ic_stat_cinematch",
        color: "#2E7D32",
        tag: groupKey,
        notificationCount,
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-collapse-id": groupKey,
      },
      payload: {
        aps: {
          sound: "default",
          badge: 1,
          threadId: groupKey,
        },
      },
    },
  });

  const cleanup = [];
  result.responses.forEach((response, index) => {
    if (!response.success && isInvalidFcmToken(response.error)) {
      cleanup.push(tokensSnap.docs[index].ref.delete().catch(() => null));
    }
  });
  await Promise.all(cleanup);
  return result;
}

function buildSocialPush(uid, notificationId, data) {
  const type = pushString(data.type, "social");
  const actorName = pushString(data.actorName, "Bir kullanici") || "Bir kullanici";
  const preview = pushString(data.preview);
  const count = Math.max(1, Number(data.count) || 1);
  let title = "CineMatch";
  let body = "Yeni bildirimin var.";

  if (type === "like") {
    title = "Yeni begeni";
    body = count > 1
      ? `${actorName} ve ${count - 1} kisi daha gonderini begendi`
      : `${actorName} gonderini begendi`;
  } else if (type === "comment") {
    title = "Yeni yorum";
    body = preview ? `${actorName}: ${preview}` : `${actorName} gonderine yorum yapti`;
  } else if (type === "comment_reply") {
    title = "Yorumunuz yanıtlandı";
    body = preview ? `${actorName}: ${preview}` : `${actorName} yorumunuzu yanıtladı`;
  } else if (type === "follow") {
    title = "Yeni takipci";
    body = `${actorName} seni takip etmeye basladi`;
  } else if (type === "club_request") {
    title = "Kulup istegi";
    body = `${actorName} kulubune katilmak istiyor`;
  }

  return {
    notification: { title, body },
    data: {
      type,
      route: type,
      notificationId,
      actorId: pushString(data.actorId),
      actorName,
      postId: pushString(data.postId),
      parentReplyId: pushString(data.parentReplyId),
      replyToReplyId: pushString(data.replyToReplyId),
      clubId: pushString(data.clubId),
      clubName: pushString(data.clubName),
      preview,
      count,
      recipientId: uid,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
  };
}

exports.sendPushOnUserNotification = functions.firestore
  .document("users/{uid}/notifications/{notificationId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;

    const uid = context.params.uid;
    const notificationId = context.params.notificationId;
    const before = change.before.exists ? (change.before.data() || {}) : {};
    const after = change.after.data() || {};

    if (after.actorId === uid) return null;
    if (after.read === true || after.isRead === true) return null;

    if (change.before.exists) {
      const beforeTime = pushTime(before.updatedAt || before.createdAt);
      const afterTime = pushTime(after.updatedAt || after.createdAt);
      if (beforeTime === afterTime) return null;
    }

    return sendPushToUser(uid, buildSocialPush(uid, notificationId, after));
  });

exports.createNotificationOnLike = functions.firestore
  .document("posts/{postId}/likes/{userId}")
  .onCreate(async (snapshot, context) => {
    const postId = context.params.postId;
    const actorId = context.params.userId;
    const postSnap = await admin.firestore().collection("posts").doc(postId).get();
    if (!postSnap.exists) return;
    const postData = postSnap.data();
    const authorId = postData.authorId;
    if (authorId === actorId) return;
    
    const actorSnap = await admin.firestore().collection("users").doc(actorId).get();
    const actorData = actorSnap.data() || {};
    const actorName = actorData.username || "Bir Kullanıcı";
    
    const querySnapshot = await admin.firestore()
      .collection("users").doc(authorId).collection("notifications")
      .where("type", "==", "like").where("postId", "==", postId).where("read", "==", false)
      .limit(1).get();

    if (!querySnapshot.empty) {
      const doc = querySnapshot.docs[0];
      await doc.ref.update({
        count: (doc.data().count || 1) + 1,
        actorName: actorName,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } else {
      await admin.firestore().collection("users").doc(authorId).collection("notifications").add({
        type: "like", actorId: actorId, actorName: actorName, postId: postId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(), read: false, count: 1,
        preview: `${actorName} gönderini beğendi.`
      });
    }
  });exports.removeNotificationOnUnlike = functions.firestore
  .document("posts/{postId}/likes/{userId}")
  .onDelete(async (snapshot, context) => {
    const postId = context.params.postId;
    
    // Post'un yazarını (authorId) bulmamız lazım
    const postSnap = await admin.firestore().collection("posts").doc(postId).get();
    if (!postSnap.exists) return;
    const authorId = postSnap.data().authorId;

    // Yazarın bildirimlerinde bu post için olan okunmamış beğeni bildirimini bul
    const querySnapshot = await admin.firestore()
      .collection("users").doc(authorId).collection("notifications")
      .where("type", "==", "like")
      .where("postId", "==", postId)
      .where("read", "==", false)
      .limit(1).get();

    if (!querySnapshot.empty) {
      const doc = querySnapshot.docs[0];
      const currentCount = doc.data().count || 1;
      
      if (currentCount > 1) {
        // Eğer bildirimde birden fazla kişinin beğenisi gruplanmışsa, sayacı 1 azalt
        await doc.ref.update({
          count: currentCount - 1
        });
      } else {
        // Eğer sadece 1 beğeni varsa ve o da geri alındıysa, bildirimi tamamen sil
        await doc.ref.delete();
      }
    }
  });

exports.createNotificationOnFollow = functions.firestore
  .document("users/{followerId}/following/{followedId}")
  .onCreate(async (snapshot, context) => {
    const followerId = context.params.followerId;
    const followedId = context.params.followedId;
    const followerSnap = await admin.firestore().collection("users").doc(followerId).get();
    const followerData = followerSnap.data() || {};
    await admin.firestore().collection("users").doc(followedId).collection("notifications")
      .doc(`${followerId}_follow`).set({
        type: "follow", actorId: followerId, actorName: followerData.username || "Bir Kullanıcı",
        createdAt: admin.firestore.FieldValue.serverTimestamp(), read: false,
      });
  });
// ==================================================================
// 4. SOHBET & MESAJ BİLDİRİMLERİ (Optimize Edilmiş V1)
// ==================================================================
exports.sendChatNotification = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snapshot, context) => {
    const messageData = snapshot.data() || {};
    const authorId = messageData.authorId;
    const chatId = context.params.chatId;
    const messageId = context.params.messageId;

    if (!authorId) return null;

    const chatDoc = await admin.firestore().collection("chats").doc(chatId).get();
    if (!chatDoc.exists) return null;

    const chatData = chatDoc.data() || {};
    const participants = Array.isArray(chatData.participants) ? chatData.participants : [];
    // Kendimiz hariç diğer katılımcıları bul
    const recipients = participants.filter((uid) => uid && uid !== authorId);
    if (!recipients.length) return null;

    const authorSnap = await admin.firestore().collection("users").doc(authorId).get();
    const authorData = authorSnap.data() || {};
    const actorName = authorData.displayName || authorData.username || authorData.name || "Bir kullanıcı";
    
    const preview = pushString(messageData.text, "Bir mesaj gönderdi.");
    const isGroup = chatData.isGroup === true;
    const groupName = pushString(chatData.name || chatData.groupName || "");
    const body = isGroup && groupName
      ? `${groupName}: ${preview}`
      : preview;

    await Promise.all(recipients.map(async (receiverId) => {
      const userDoc = await admin.firestore().collection("users").doc(receiverId).get();
      const userData = userDoc.data() || {};
      const mutedChats = Array.isArray(userData.mutedChats) ? userData.mutedChats : [];

      // KONTROL: Kullanıcı bu sohbeti sessize almış mı?
      if (mutedChats.includes(chatId)) return null;

      const unreadCounts = chatData.unreadCounts || {};
      const unreadCount = Math.max(1, Number(unreadCounts[receiverId]) || 1);

      return sendPushToUser(receiverId, {
        notification: {
          title: unreadCount > 1
            ? `${pushString(actorName, "Yeni mesaj")} (${unreadCount} yeni mesaj)`
            : pushString(actorName, "Yeni mesaj"),
          body,
        },
        data: {
          type: "chat",
          route: "chat",
          chatId,
          messageId,
          actorId: authorId,
          otherUid: authorId, // İstemci tarafında yönlendirme için
          actorName,
          preview,
          unreadCount,
          isGroup: isGroup ? "true" : "false",
          groupName,
          recipientId: receiverId,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
      });
    }));

    return null;
  });

exports.aggregateUnreadCounts = functions.firestore
  .document("chats/{chatId}")
  .onUpdate(async (change) => {
    const newData = change.after.data();
    const oldData = change.before.data();
    const newCounts = newData.unreadCounts || {};
    const oldCounts = oldData.unreadCounts || {};
    if (JSON.stringify(newCounts) === JSON.stringify(oldCounts)) return;
    
    for (const uid of (newData.participants || [])) {
      const diff = (newCounts[uid] || 0) - (oldCounts[uid] || 0);
      if (diff !== 0) {
        await admin.firestore().collection("users").doc(uid).set({
          totalUnreadCount: admin.firestore.FieldValue.increment(diff)
        }, { merge: true });
      }
    }
  });

exports.findMatchesCallable = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Giriş gerekli.');
  const db = admin.firestore();
  const meSnap = await db.collection('users').doc(context.auth.uid).get();
  if (!meSnap.exists) return { results: [] };
  const myData = meSnap.data();
  function listOf(field) {
    return Array.isArray(myData[field])
      ? myData[field].map((item) => String(item).trim()).filter(Boolean)
      : [];
  }

  function sampleKeys(values, max = 10) {
    const unique = [...new Set(values)].filter(Boolean);
    return unique.sort(() => Math.random() - 0.5).slice(0, max);
  }

  const candidates = new Map();
  async function runArrayQuery(field, keys) {
    const queryKeys = sampleKeys(keys, 10);
    if (!queryKeys.length) return;
    try {
      const snap = await db
        .collection('users')
        .where(field, 'array-contains-any', queryKeys)
        .limit(45)
        .get();
      snap.docs.forEach((doc) => {
        if (doc.id === context.auth.uid) return;
        const userData = doc.data() || {};
        if (!String(userData.username || '').trim()) return;
        candidates.set(doc.id, { uid: doc.id, ...userData });
      });
    } catch (e) {
      console.log('findMatchesCallable query skipped', field, e.message);
    }
  }

  const five = listOf('fiveStarKeys');
  const favs = listOf('favoritesKeys');
  const watch = listOf('watchlistKeys');
  const genres = listOf('favGenres').map((item) => item.toLowerCase());
  const directors = listOf('favDirectors').map((item) => item.toLowerCase());
  const actors = listOf('favActors').map((item) => item.toLowerCase());

  await Promise.all([
    runArrayQuery('fiveStarKeys', [...five, ...favs]),
    runArrayQuery('favoritesKeys', [...favs, ...five]),
    runArrayQuery('watchlistKeys', watch),
    runArrayQuery('favGenres', genres),
    runArrayQuery('favDirectors', directors),
    runArrayQuery('favActors', actors),
  ]);

  if (candidates.size < 8) {
    try {
      const discovery = await db
        .collection('users')
        .orderBy('totalMovies', 'desc')
        .limit(35)
        .get();
      discovery.docs.forEach((doc) => {
        if (doc.id === context.auth.uid) return;
        const userData = doc.data() || {};
        if (!String(userData.username || '').trim()) return;
        candidates.set(doc.id, { uid: doc.id, ...userData });
      });
    } catch (e) {
      console.log('findMatchesCallable discovery skipped', e.message);
    }
  }

  return { results: [...candidates.values()].slice(0, 120) };
}); 
// ==================================================================
// 7. FANOUT FEED (Takip Edilenler Akışı Optimizasyonu)
// ==================================================================
exports.fanoutPostToFollowers = functions.firestore
  .document("posts/{postId}")
  .onCreate(async (snapshot, context) => {
    const postData = snapshot.data();
    const authorId = postData.authorId;
    const postId = context.params.postId;

    const db = admin.firestore();
    
    // Yazarın takipçilerini bul (collectionGroup kullanarak)
    const followersSnap = await db.collectionGroup("following")
      .where("to", "==", authorId)
      .get();

    if (followersSnap.empty) return null;

    const batch = db.batch();
    
    // Post referansını her bir takipçinin özel feed kutusuna ekle
    followersSnap.forEach((doc) => {
      const followerId = doc.data().by;
      if (followerId) {
        const feedRef = db.collection("feeds").doc(followerId).collection("user_feed").doc(postId);
        batch.set(feedRef, {
          postId: postId,
          authorId: authorId,
          createdAt: postData.createdAt
        });
      }
    });

    return batch.commit();
  });
