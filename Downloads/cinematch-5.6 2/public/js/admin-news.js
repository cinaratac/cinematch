// Firebase başlatma, oturum kalıcılığı ve yetki önbelleği admin-shared.js
// içinde ortaklaştırıldı (bkz. js/admin-shared.js). Bu sayede paneller arası
// geçişte gereksiz Cloud Function çağrısı yapılmıyor ve geçici hatalar
// yüzünden kullanıcı sistemden atılmıyor.
const { auth, db, functions } = CineAdmin;
const authPersistenceReady = CineAdmin.persistenceReady;

const ARTICLE_PAGE_SIZE = 30;
let articlePageSize = ARTICLE_PAGE_SIZE;

const els = {
  authLoadingPanel: document.getElementById("authLoadingPanel"),
  loginPanel: document.getElementById("loginPanel"),
  adminPanel: document.getElementById("adminPanel"),
  loginForm: document.getElementById("loginForm"),
  loginEmail: document.getElementById("loginEmail"),
  loginPassword: document.getElementById("loginPassword"),
  loginButton: document.getElementById("loginButton"),
  loginMessage: document.getElementById("loginMessage"),
  logoutButton: document.getElementById("logoutButton"),
  currentUserLabel: document.getElementById("currentUserLabel"),
  articleList: document.getElementById("articleList"),
  articleCount: document.getElementById("articleCount"),
  articleSearch: document.getElementById("articleSearch"),
  articleStatusFilter: document.getElementById("articleStatusFilter"),
  newArticleButton: document.getElementById("newArticleButton"),
  articleForm: document.getElementById("articleForm"),
  articleId: document.getElementById("articleId"),
  status: document.getElementById("status"),
  category: document.getElementById("category"),
  title: document.getElementById("title"),
  slug: document.getElementById("slug"),
  summary: document.getElementById("summary"),
  movieTitle: document.getElementById("movieTitle"),
  tags: document.getElementById("tags"),
  imageUrl: document.getElementById("imageUrl"),
  sourceUrl: document.getElementById("sourceUrl"),
  body: document.getElementById("body"),
  deleteButton: document.getElementById("deleteButton"),
  saveButton: document.getElementById("saveButton"),
  saveMessage: document.getElementById("saveMessage"),
  loadMoreArticlesButton: document.getElementById("loadMoreArticlesButton"),
};

let unsubscribeArticles = null;
let articles = [];

const { setMessage, escapeHtml, isPermissionError } = CineAdmin;

function slugify(value) {
  return (value || "")
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

function parseTags(value) {
  return (value || "")
    .split(",")
    .map((tag) => tag.trim())
    .filter(Boolean)
    .slice(0, 12);
}

function showLogin() {
  els.authLoadingPanel.classList.add("hidden");
  els.loginPanel.classList.remove("hidden");
  els.adminPanel.classList.add("hidden");
}

function showAdmin(user) {
  els.authLoadingPanel.classList.add("hidden");
  els.loginPanel.classList.add("hidden");
  els.adminPanel.classList.remove("hidden");
  els.currentUserLabel.textContent = user.email || user.uid;
}

function resetForm() {
  els.articleForm.reset();
  els.articleId.value = "";
  els.status.value = "draft";
  els.category.value = "Haber";
  els.deleteButton.disabled = true;
  setMessage(els.saveMessage, "");
  markActiveArticle("");
}

function fillForm(article) {
  els.articleId.value = article.id;
  els.status.value = article.status || "draft";
  els.category.value = article.category || "Haber";
  els.title.value = article.title || "";
  els.slug.value = article.slug || "";
  els.summary.value = article.summary || "";
  els.movieTitle.value = article.movieTitle || "";
  els.tags.value = Array.isArray(article.tags) ? article.tags.join(", ") : "";
  els.imageUrl.value = article.imageUrl || "";
  els.sourceUrl.value = article.sourceUrl || "";
  els.body.value = article.body || "";
  els.deleteButton.disabled = false;
  setMessage(els.saveMessage, "");
  markActiveArticle(article.id);
}

function collectForm() {
  const title = els.title.value.trim();
  return {
    id: els.articleId.value.trim(),
    status: els.status.value,
    category: els.category.value,
    title,
    slug: els.slug.value.trim() || slugify(title),
    summary: els.summary.value.trim(),
    movieTitle: els.movieTitle.value.trim(),
    tags: parseTags(els.tags.value),
    imageUrl: els.imageUrl.value.trim(),
    sourceUrl: els.sourceUrl.value.trim(),
    body: els.body.value.trim(),
    authorName: "CineMatch Editör",
  };
}

function markActiveArticle(id) {
  document.querySelectorAll(".article-item").forEach((button) => {
    button.classList.toggle("active", button.dataset.id === id);
  });
}

function renderArticles() {
  const search = (els.articleSearch.value || "")
    .trim()
    .toLocaleLowerCase("tr-TR");
  const statusFilter = els.articleStatusFilter.value;
  const visibleArticles = articles.filter((article) => {
    const statusMatches =
      statusFilter === "all" || (article.status || "draft") === statusFilter;
    const haystack = [
      article.title,
      article.summary,
      article.category,
      article.movieTitle,
      Array.isArray(article.tags) ? article.tags.join(" ") : "",
    ]
      .join(" ")
      .toLocaleLowerCase("tr-TR");
    return statusMatches && (!search || haystack.includes(search));
  });

  els.articleCount.textContent = `${visibleArticles.length} / ${articles.length} haber`;

  if (!articles.length) {
    els.articleList.innerHTML = '<p class="message">Henuz haber yok.</p>';
    return;
  }

  if (!visibleArticles.length) {
    els.articleList.innerHTML =
      '<p class="message">Filtreye uygun haber yok.</p>';
    return;
  }

  els.articleList.innerHTML = "";
  visibleArticles.forEach((article) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "article-item";
    button.dataset.id = article.id;
    button.innerHTML = `
      <strong>${escapeHtml(article.title || "Başlıksız")}</strong>
      <span>${escapeHtml(article.status || "draft")} · ${escapeHtml(article.category || "Haber")}</span>
    `;
    button.addEventListener("click", () => fillForm(article));
    els.articleList.appendChild(button);
  });
  markActiveArticle(els.articleId.value);
}

function subscribeArticles() {
  if (unsubscribeArticles) unsubscribeArticles();
  unsubscribeArticles = db
    .collection("news_articles")
    .orderBy("updatedAt", "desc")
    .limit(articlePageSize)
    .onSnapshot(
      (snapshot) => {
        articles = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
        renderArticles();
        // Getirilen kayıt sayısı, istenen sayfa boyutuna eşit veya fazlaysa
        // muhtemelen daha fazla kayıt vardır; "Daha Fazla Yükle" butonunu göster.
        if (els.loadMoreArticlesButton) {
          els.loadMoreArticlesButton.classList.toggle(
            "hidden",
            snapshot.docs.length < articlePageSize
          );
        }
      },
      (error) => {
        els.articleList.innerHTML = `<p class="message error">${escapeHtml(error.message)}</p>`;
      }
    );
}

els.loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  els.loginButton.disabled = true;
  setMessage(els.loginMessage, "Giriş yapılıyor...");

  try {
    await authPersistenceReady;
    await auth.signInWithEmailAndPassword(
      els.loginEmail.value.trim(),
      els.loginPassword.value
    );
    setMessage(els.loginMessage, "");
  } catch (error) {
    setMessage(els.loginMessage, error.message, "error");
  } finally {
    els.loginButton.disabled = false;
  }
});

els.logoutButton.addEventListener("click", () => CineAdmin.logout());
els.newArticleButton.addEventListener("click", resetForm);
els.articleSearch.addEventListener("input", renderArticles);
els.articleStatusFilter.addEventListener("change", renderArticles);

if (els.loadMoreArticlesButton) {
  els.loadMoreArticlesButton.addEventListener("click", () => {
    articlePageSize += ARTICLE_PAGE_SIZE;
    subscribeArticles();
  });
}

els.title.addEventListener("blur", () => {
  if (!els.slug.value.trim()) els.slug.value = slugify(els.title.value);
});

els.articleForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  els.saveButton.disabled = true;
  setMessage(els.saveMessage, "Kaydediliyor...");

  try {
    const saveNewsArticle = functions.httpsCallable("saveNewsArticle");
    const result = await saveNewsArticle(collectForm());
    if (result.data && result.data.id) els.articleId.value = result.data.id;
    setMessage(els.saveMessage, "Kaydedildi.", "success");
  } catch (error) {
    setMessage(els.saveMessage, error.message, "error");
  } finally {
    els.saveButton.disabled = false;
  }
});

els.deleteButton.addEventListener("click", async () => {
  const id = els.articleId.value.trim();
  if (!id) return;
  if (!window.confirm("Bu haberi kalıcı olarak silmek istiyor musunuz?")) return;

  els.deleteButton.disabled = true;
  setMessage(els.saveMessage, "Siliniyor...");

  try {
    const deleteNewsArticle = functions.httpsCallable("deleteNewsArticle");
    await deleteNewsArticle({ id });
    resetForm();
    setMessage(els.saveMessage, "Silindi.", "success");
  } catch (error) {
    els.deleteButton.disabled = false;
    setMessage(els.saveMessage, error.message, "error");
  }
});

auth.onAuthStateChanged(async (user) => {
  if (unsubscribeArticles) {
    unsubscribeArticles();
    unsubscribeArticles = null;
  }

  if (!user) {
    showLogin();
    return;
  }

  try {
    await authPersistenceReady;
    // "newsAdmin" yetkisi Duyuru paneli ile ortak önbelleklenir; bu sayede
    // Haber <-> Duyuru arası geçişte tekrar Cloud Function çağrısı yapılmaz
    // ve geçici hatalar yüzünden oturum kapatılıp tekrar giriş istenmez.
    await CineAdmin.requireRole(user, "newsAdmin", () =>
      functions.httpsCallable("isNewsAdmin")()
    );
    showAdmin(user);
    articlePageSize = ARTICLE_PAGE_SIZE;
    resetForm();
    subscribeArticles();
  } catch (error) {
    if (isPermissionError(error)) {
      await CineAdmin.logout();
      showLogin();
      setMessage(els.loginMessage, "Bu panel için yetkiniz yok.", "error");
      return;
    }

    showAdmin(user);
    setMessage(
      els.saveMessage,
      "Yetki kontrolu gecici olarak tamamlanamadi. Sayfayi yenileyebilirsiniz.",
      "error"
    );
  }
});
