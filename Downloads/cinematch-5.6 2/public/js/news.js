const firebaseConfig = {
  apiKey: "AIzaSyAsHFffuxGA1cYKbHBs8LE6QbJOi4pjwC4",
  authDomain: "movie-matching-8a836.firebaseapp.com",
  projectId: "movie-matching-8a836",
  storageBucket: "movie-matching-8a836.firebasestorage.app",
  messagingSenderId: "266660427246",
  appId: "1:266660427246:web:4dcb77ff5e91e47dc04aff",
};

firebase.initializeApp(firebaseConfig);
const db = firebase.firestore();

const pageType = document.body.dataset.newsPage;
let allArticles = [];

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function formatDate(timestamp) {
  const date = timestamp && timestamp.toDate
    ? timestamp.toDate()
    : timestamp instanceof Date
      ? timestamp
      : null;
  if (!date) return "";
  return date.toLocaleDateString("tr-TR", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

function setEditionDate() {
  const target = document.getElementById("newsEditionDate");
  if (!target) return;
  target.textContent = new Date().toLocaleDateString("tr-TR", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

function safeExternalUrl(value) {
  try {
    const url = new URL(String(value || ""));
    return ["http:", "https:"].includes(url.protocol) ? url.href : "";
  } catch (_) {
    return "";
  }
}

function activateImageFallbacks(root) {
  if (!root || typeof root.querySelectorAll !== "function") return;
  root.querySelectorAll("[data-news-image]").forEach((image) => {
    const showFallback = () => {
      image.hidden = true;
      const fallback = image.nextElementSibling;
      if (fallback && fallback.classList.contains("news-card-no-image")) {
        fallback.hidden = false;
      }
    };
    image.addEventListener("error", showFallback, { once: true });
    if (image.complete && image.naturalWidth === 0) showFallback();
  });
}

function articleLink(article) {
  return `/haber?id=${encodeURIComponent(article.id)}`;
}

function renderList() {
  const list = document.getElementById("newsList");
  const count = document.getElementById("newsCount");
  const searchInput = document.getElementById("newsSearch");
  const search = (searchInput.value || "").trim().toLocaleLowerCase("tr-TR");
  const visible = allArticles.filter((article) => {
    const haystack = [
      article.title,
      article.summary,
      article.category,
      article.movieTitle,
      Array.isArray(article.tags) ? article.tags.join(" ") : "",
    ]
      .join(" ")
      .toLocaleLowerCase("tr-TR");
    return !search || haystack.includes(search);
  });

  count.textContent = `${visible.length} haber · en yeniden eskiye`;

  if (!visible.length) {
    list.innerHTML = '<p class="state-text">Bu aramaya uygun bir haber bulunamadı.</p>';
    return;
  }

  list.innerHTML = visible
    .map((article, index) => {
      const positionClass = index === 0
        ? "news-card--lead"
        : index < 3
          ? "news-card--side"
          : "news-card--standard";
      const number = String(index + 1).padStart(2, "0");
      const imageUrl = safeExternalUrl(article.imageUrl);
      const image = imageUrl
        ? `<img data-news-image src="${escapeHtml(imageUrl)}" alt="${escapeHtml(article.title)}" ${index === 0 ? 'fetchpriority="high"' : 'loading="lazy"'} />
          <span class="news-card-no-image" aria-hidden="true" hidden>CM</span>`
        : '<span class="news-card-no-image" aria-hidden="true">CM</span>';
      return `
        <a class="news-card ${positionClass}" href="${articleLink(article)}">
          <div class="news-card-media">
            ${image}
            <span class="news-card-index">${number}</span>
          </div>
          <div class="news-card-body">
            <div class="news-meta">
              <strong>${escapeHtml(article.category || "Haber")}</strong>
              <span>${escapeHtml(formatDate(article.publishedAt))}</span>
            </div>
            <h2>${escapeHtml(article.title)}</h2>
            ${article.summary ? `<p class="news-card-summary">${escapeHtml(article.summary)}</p>` : ""}
            <span class="read-more">Haberi oku</span>
          </div>
        </a>
      `;
    })
    .join("");
  activateImageFallbacks(list);
}

async function loadList() {
  const list = document.getElementById("newsList");
  const searchInput = document.getElementById("newsSearch");

  try {
    const snapshot = await db
      .collection("public_news")
      .orderBy("publishedAt", "desc")
      .limit(80)
      .get();

    allArticles = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    searchInput.addEventListener("input", renderList);
    renderList();
  } catch (error) {
    list.innerHTML = `<p class="state-text">Haberler yüklenemedi: ${escapeHtml(error.message)}</p>`;
  }
}

function renderDetail(article) {
  const target = document.getElementById("articleDetail");
  const bodyText = String(article.body || "");
  const paragraphs = bodyText
    .split(/\n\s*\n/)
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => `<p>${escapeHtml(part)}</p>`)
    .join("");
  const coverUrl = safeExternalUrl(article.imageUrl);
  const cover = coverUrl
    ? `<figure class="article-cover">
        <div class="article-cover-media">
          <img data-news-image src="${escapeHtml(coverUrl)}" alt="${escapeHtml(article.title)}" />
          <span class="news-card-no-image" aria-hidden="true" hidden>CM</span>
        </div>
        ${article.movieTitle ? `<figcaption>${escapeHtml(article.movieTitle)}</figcaption>` : ""}
      </figure>`
    : "";
  const tags = Array.isArray(article.tags)
    ? article.tags.map((tag) => `<span class="tag">${escapeHtml(tag)}</span>`).join("")
    : "";
  const sourceUrl = safeExternalUrl(article.sourceUrl);
  const source = sourceUrl
    ? `<a class="source-link" href="${escapeHtml(sourceUrl)}" target="_blank" rel="noopener noreferrer">Haber kaynağını aç</a>`
    : "";
  const wordCount = bodyText.trim() ? bodyText.trim().split(/\s+/).length : 0;
  const readMinutes = Math.max(1, Math.ceil(wordCount / 190));

  document.title = `${article.title} - CineMatch`;
  const socialTitle = `${article.title} — CineMatch`;
  const socialDescription = String(article.summary || "CineMatch sinema gündemi haberi.").slice(0, 180);
  document.getElementById("newsOgTitle")?.setAttribute("content", socialTitle);
  document.getElementById("newsOgDescription")?.setAttribute("content", socialDescription);
  document.getElementById("newsTwitterTitle")?.setAttribute("content", socialTitle);
  document.getElementById("newsTwitterDescription")?.setAttribute("content", socialDescription);
  if (coverUrl) {
    document.getElementById("newsOgImage")?.setAttribute("content", coverUrl);
    document.getElementById("newsTwitterImage")?.setAttribute("content", coverUrl);
  }
  target.innerHTML = `
    <header class="article-header">
      <div class="news-meta">
        <strong>${escapeHtml(article.category || "Haber")}</strong>
        <span>${escapeHtml(formatDate(article.publishedAt))}</span>
        ${article.movieTitle ? `<span>${escapeHtml(article.movieTitle)}</span>` : ""}
      </div>
      <h1>${escapeHtml(article.title)}</h1>
      ${article.summary ? `<p class="article-summary">${escapeHtml(article.summary)}</p>` : ""}
      <div class="article-byline">
        <span>Yazan <strong>${escapeHtml(article.authorName || "CineMatch Editör")}</strong></span>
        <span>${readMinutes} dakikalık okuma</span>
      </div>
    </header>
    ${cover}
    <div class="article-paper${cover ? "" : " no-cover"}">
      <div class="article-body">${paragraphs}</div>
      ${(tags || source) ? `<footer class="article-extras">
        ${tags ? `<div class="tag-row">${tags}</div>` : ""}
        ${source}
      </footer>` : ""}
    </div>
  `;
  activateImageFallbacks(target);
}

async function loadDetail() {
  const target = document.getElementById("articleDetail");
  const params = new URLSearchParams(window.location.search);
  const id = params.get("id");

  if (!id) {
    target.innerHTML = '<p class="state-text">Haber bağlantısı eksik.</p>';
    return;
  }

  try {
    const doc = await db.collection("public_news").doc(id).get();
    if (!doc.exists) {
      target.innerHTML = '<p class="state-text">Haber bulunamadı.</p>';
      return;
    }
    renderDetail({ id: doc.id, ...doc.data() });
  } catch (error) {
    target.innerHTML = `<p class="state-text">Haber yüklenemedi: ${escapeHtml(error.message)}</p>`;
  }
}

setEditionDate();

if (pageType === "list") {
  loadList();
}

if (pageType === "detail") {
  loadDetail();
}
