// admin-shared.js
// Tüm admin panelleri (haber, soru yarışması, duyuru, bot) tarafından ortak
// kullanılan Firebase başlatma, oturum kalıcılığı ve yetki-önbellek katmanı.
//
// ÇÖZÜLEN SORUNLAR
// 1) "Sayfalar arasında geçişte tekrar giriş isteme" bug'ı:
//    Her panel kendi Cloud Function'ı ile (isNewsAdmin / isTriviaAdmin / ...)
//    yetki kontrolü yapıyordu. Bu çağrı soğuk başlangıç (cold start) ya da
//    geçici ağ hatası yüzünden ara sıra "unauthenticated/permission-denied"
//    dönebiliyor ve kod bunu gerçek yetki hatası sanıp kullanıcıyı
//    auth.signOut() ile sistemden atıyordu. Burada:
//      - Yetki sonucu sessionStorage'da (sekme bazlı) kısa süreliğine
//        önbelleğe alınıyor, aynı yetkiyi paylaşan sayfalar arası geçişte
//        (örn. Haber <-> Duyuru, ikisi de isNewsAdmin kullanır) tekrar ağ
//        isteği yapılmıyor.
//      - Kontrolden önce ID token tazeleniyor (getIdToken(true)) ki sayfa
//        yeni açıldığında token henüz hazır değilken yanlış "yetkisiz"
//        sonucu alınmasın.
//      - Gerçek permission-denied/unauthenticated DIŞINDA bir hata gelirse
//        (örn. Function soğuk başlangıcı) kullanıcı hemen atılmıyor, kısa
//        bir bekleme sonrası bir kez daha deneniyor.
// 2) Firestore okuma optimizasyonu:
//    - IndexedDB tabanlı yerel önbellek (enablePersistence) açılıyor, böylece
//      art arda sayfa geçişlerinde/yeniden yüklemelerde ilk veriler
//      önbellekten anında gösterilir, sunucudan sadece farklar okunur.

(function (global) {
  if (global.CineAdmin) return; // birden fazla kez yüklenirse tekrar kurma

  const firebaseConfig = {
    apiKey: "AIzaSyAsHFffuxGA1cYKbHBs8LE6QbJOi4pjwC4",
    authDomain: "movie-matching-8a836.firebaseapp.com",
    projectId: "movie-matching-8a836",
    storageBucket: "movie-matching-8a836.firebasestorage.app",
    messagingSenderId: "266660427246",
    appId: "1:266660427246:web:4dcb77ff5e91e47dc04aff",
  };

  const app = firebase.apps.length ? firebase.app() : firebase.initializeApp(firebaseConfig);
  const auth = firebase.auth(app);
  const functions = firebase.functions(app);
  const db = firebase.firestore ? firebase.firestore(app) : null;

  if (db) {
    db.enablePersistence({ synchronizeTabs: true }).catch((err) => {
      // failed-precondition: aynı anda birden çok sekme açık
      // unimplemented: tarayıcı IndexedDB'yi desteklemiyor (gizli sekme vb.)
      console.warn("Firestore yerel önbellek etkinleştirilemedi:", err.code);
    });
  }

  // Kalıcılık, herhangi bir onAuthStateChanged dinleyicisi kurulmadan önce
  // ayarlanıp beklenmeli; aksi halde ilk auth durumu yanlış modda
  // değerlendirilip sayfa geçişlerinde oturum kaybolmuş gibi görünebiliyordu.
  const persistenceReady = auth
    .setPersistence(firebase.auth.Auth.Persistence.LOCAL)
    .catch((err) => console.warn("Firebase persistence ayarlanamadı:", err.code));

  const ROLE_CACHE_PREFIX = "cineadmin_role_";
  const ROLE_CACHE_TTL_MS = 15 * 60 * 1000; // 15 dakika

  function roleCacheKey(uid, roleKey) {
    return `${ROLE_CACHE_PREFIX}${roleKey}_${uid}`;
  }

  function readRoleCache(uid, roleKey) {
    try {
      const raw = sessionStorage.getItem(roleCacheKey(uid, roleKey));
      if (!raw) return null;
      const entry = JSON.parse(raw);
      if (!entry || entry.uid !== uid) return null;
      if (Date.now() - entry.savedAt > ROLE_CACHE_TTL_MS) return null;
      return entry.payload;
    } catch (err) {
      return null;
    }
  }

  function writeRoleCache(uid, roleKey, payload) {
    try {
      sessionStorage.setItem(
        roleCacheKey(uid, roleKey),
        JSON.stringify({ uid, savedAt: Date.now(), payload: payload === undefined ? true : payload })
      );
    } catch (err) {
      /* sessionStorage dolu/erişilemez olabilir, kritik değil */
    }
  }

  function clearRoleCache() {
    try {
      Object.keys(sessionStorage)
        .filter((key) => key.startsWith(ROLE_CACHE_PREFIX))
        .forEach((key) => sessionStorage.removeItem(key));
    } catch (err) {
      /* yoksay */
    }
  }

  function isPermissionError(error) {
    const code = error && error.code ? String(error.code) : "";
    return code.includes("permission-denied") || code.includes("unauthenticated");
  }

  function delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  // roleKey: önbellek anahtarı (örn. "newsAdmin", "triviaAdmin", "botAdmin")
  // fetcher: () => Promise<payload>  (yetki kontrolünü yapan callable çağrısı)
  async function requireRole(user, roleKey, fetcher) {
    const cached = readRoleCache(user.uid, roleKey);
    if (cached) return cached;

    // Sayfa yeni açıldığında ID token henüz tazelenmemiş olabiliyor; bu da
    // gerçekte yetkili bir kullanıcının "unauthenticated" hatası almasına
    // yol açabiliyordu. Kontrolden önce token'ı zorla tazeliyoruz.
    await user.getIdToken(true).catch(() => {});

    try {
      const payload = await fetcher();
      writeRoleCache(user.uid, roleKey, payload);
      return payload;
    } catch (error) {
      if (isPermissionError(error)) throw error;
      // Gerçek bir yetki reddi değilse (soğuk başlangıç/ağ hatası vb.)
      // kullanıcıyı hemen atmadan bir kez daha deniyoruz.
      await delay(700);
      const payload = await fetcher();
      writeRoleCache(user.uid, roleKey, payload);
      return payload;
    }
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function setMessage(target, text, type = "") {
    if (!target) return;
    target.textContent = text || "";
    target.className = `message ${type}`.trim();
  }

  async function logout() {
    clearRoleCache();
    await auth.signOut();
  }

  global.CineAdmin = {
    app,
    auth,
    db,
    functions,
    persistenceReady,
    requireRole,
    isPermissionError,
    clearRoleCache,
    escapeHtml,
    setMessage,
    logout,
  };
})(window);
