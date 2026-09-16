(function () {
  "use strict";

  const firebaseConfig = {
    apiKey: "AIzaSyAsHFffuxGA1cYKbHBs8LE6QbJOi4pjwC4",
    authDomain: "movie-matching-8a836.firebaseapp.com",
    projectId: "movie-matching-8a836",
    storageBucket: "movie-matching-8a836.firebasestorage.app",
    messagingSenderId: "266660427246",
    appId: "1:266660427246:web:4dcb77ff5e91e47dc04aff",
  };

  const app = firebase.apps.length ? firebase.app() : firebase.initializeApp(firebaseConfig);
  const db = firebase.firestore(app);
  const pageType = document.body.dataset.blogPage || "";
  let allPosts = [];

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function safeHttpsUrl(value) {
    try {
      const parsed = new URL(String(value || ""));
      return parsed.protocol === "https:" ? parsed.toString() : "";
    } catch (error) {
      return "";
    }
  }

  function formatDate(timestamp) {
    const date = timestamp && typeof timestamp.toDate === "function"
      ? timestamp.toDate()
      : null;
    if (!date) return "";
    return date.toLocaleDateString("tr-TR", {
      day: "numeric",
      month: "long",
      year: "numeric",
    });
  }

  function postLink(post) {
    return `/blog/yazi?id=${encodeURIComponent(post.id)}`;
  }

  function authorVisual(post, className = "") {
    const photoUrl = safeHttpsUrl(post.authorPhotoUrl);
    const name = String(post.authorName || post.authorUsername || "CineMatch Blogger");
    if (photoUrl) {
      return `<img class="${escapeHtml(className)}" src="${escapeHtml(photoUrl)}" alt="" loading="lazy" referrerpolicy="no-referrer" />`;
    }
    return `<span class="author-fallback ${escapeHtml(className)}" aria-hidden="true">${escapeHtml(name.slice(0, 1).toLocaleUpperCase("tr-TR"))}</span>`;
  }

  function cardHtml(post, index, home = false) {
    const cover = safeHttpsUrl(post.coverImageUrl);
    const title = post.title || "Başlıksız Yazı";
    const authorName = post.authorName || post.authorUsername || "CineMatch Blogger";
    const className = home ? "home-blog-card" : "blog-card";
    const mediaClass = home ? "home-blog-card-media" : "blog-card-media";
    const bodyClass = home ? "home-blog-card-body" : "blog-card-body";
    const titleTag = home ? "h3" : "h2";
    const media = cover
      ? `<img src="${escapeHtml(cover)}" alt="${escapeHtml(title)}" loading="lazy" />`
      : `<span class="blog-card-no-cover" aria-hidden="true">CM</span>`;
    const movieNames = Array.isArray(post.movies)
      ? post.movies.slice(0, 2).map((movie) => movie.title).filter(Boolean).join(" · ")
      : "";

    return `
      <a class="${className}" href="${postLink(post)}">
        <div class="${mediaClass}">
          ${media}
          <span class="blog-card-index">${String(index + 1).padStart(2, "0")}</span>
        </div>
        <div class="${bodyClass}">
          <div class="blog-card-meta">
            <strong>${escapeHtml(post.category || "Blog")}</strong>
            <span>${escapeHtml(formatDate(post.publishedAt))}</span>
            ${movieNames ? `<span>${escapeHtml(movieNames)}</span>` : ""}
          </div>
          <${titleTag}>${escapeHtml(title)}</${titleTag}>
          <p class="blog-card-excerpt">${escapeHtml(post.excerpt || "")}</p>
          <div class="blog-card-footer">
            <span class="blog-card-author">
              ${authorVisual(post)}
              <span>${escapeHtml(authorName)}</span>
            </span>
            <span class="blog-card-arrow" aria-hidden="true">↗</span>
          </div>
        </div>
      </a>
    `;
  }

  async function fetchPublishedPosts(limit) {
    const snapshot = await db.collection("public_blog_posts")
      .orderBy("publishedAt", "desc")
      .limit(limit)
      .get();
    return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
  }

  function syncCategoryOptions() {
    const select = document.getElementById("blogCategory");
    if (!select) return;
    const selected = select.value;
    const categories = [...new Set(allPosts.map((post) => post.category).filter(Boolean))]
      .sort((left, right) => left.localeCompare(right, "tr"));
    select.innerHTML = '<option value="all">Tüm kategoriler</option>' + categories
      .map((category) => `<option value="${escapeHtml(category)}">${escapeHtml(category)}</option>`)
      .join("");
    select.value = categories.includes(selected) ? selected : "all";
  }

  function renderBlogList() {
    const list = document.getElementById("blogList");
    const count = document.getElementById("blogCount");
    const searchInput = document.getElementById("blogSearch");
    const categoryInput = document.getElementById("blogCategory");
    if (!list || !count || !searchInput || !categoryInput) return;

    const search = searchInput.value.trim().toLocaleLowerCase("tr-TR");
    const category = categoryInput.value;
    const posts = allPosts.filter((post) => {
      if (category !== "all" && post.category !== category) return false;
      const haystack = [
        post.title,
        post.excerpt,
        post.category,
        post.authorName,
        post.authorUsername,
        ...(Array.isArray(post.tags) ? post.tags : []),
        ...(Array.isArray(post.movies) ? post.movies.map((movie) => movie.title) : []),
      ].join(" ").toLocaleLowerCase("tr-TR");
      return !search || haystack.includes(search);
    });

    count.textContent = `${posts.length} yazı`;
    if (!posts.length) {
      list.innerHTML = '<p class="blog-state">Bu filtreye uygun bir yazı bulunamadı.</p>';
      return;
    }
    list.innerHTML = posts.map((post, index) => cardHtml(post, index)).join("");
  }

  async function loadBlogList() {
    const list = document.getElementById("blogList");
    try {
      allPosts = await fetchPublishedPosts(80);
      syncCategoryOptions();
      document.getElementById("blogSearch").addEventListener("input", renderBlogList);
      document.getElementById("blogCategory").addEventListener("change", renderBlogList);
      renderBlogList();
    } catch (error) {
      list.innerHTML = `<p class="blog-state">Yazılar şu anda yüklenemedi: ${escapeHtml(error.message)}</p>`;
    }
  }

  async function loadHomePreview() {
    const list = document.getElementById("homeBlogList");
    const state = document.getElementById("homeBlogState");
    if (!list) return;
    try {
      const posts = await fetchPublishedPosts(3);
      if (!posts.length) {
        if (state) state.textContent = "İlk yazılar hazırlanıyor.";
        return;
      }
      list.innerHTML = posts.map((post, index) => cardHtml(post, index, true)).join("");
      if (state) state.remove();
    } catch (error) {
      if (state) state.textContent = "Blog yazıları şu anda yüklenemedi.";
    }
  }

  function safeContentHtml(value) {
    const allowedTags = new Set([
      "P", "BR", "H2", "H3", "STRONG", "B", "EM", "I", "U", "S",
      "BLOCKQUOTE", "UL", "OL", "LI", "A", "FIGURE", "IMG", "FIGCAPTION", "HR",
    ]);
    const documentValue = new DOMParser().parseFromString(String(value || ""), "text/html");
    [...documentValue.body.querySelectorAll("*")].forEach((node) => {
      if (!allowedTags.has(node.tagName)) {
        node.replaceWith(...node.childNodes);
        return;
      }
      const originalHref = node.getAttribute("href");
      const originalSrc = node.getAttribute("src");
      const originalAlt = node.getAttribute("alt");
      [...node.attributes].forEach((attribute) => node.removeAttribute(attribute.name));
      if (node.tagName === "A") {
        const href = safeHttpsUrl(originalHref);
        if (href) {
          node.setAttribute("href", href);
          node.setAttribute("target", "_blank");
          node.setAttribute("rel", "noopener noreferrer nofollow");
        }
      }
      if (node.tagName === "IMG") {
        const src = safeHttpsUrl(originalSrc);
        if (!src || !["firebasestorage.googleapis.com", "storage.googleapis.com"].includes(new URL(src).hostname)) {
          node.remove();
          return;
        }
        node.setAttribute("src", src);
        node.setAttribute("alt", String(originalAlt || "Blog görseli").slice(0, 180));
        node.setAttribute("loading", "lazy");
      }
    });
    return documentValue.body.innerHTML;
  }

  function movieCards(movies) {
    if (!Array.isArray(movies) || !movies.length) return "";
    return `
      <section class="article-related">
        <h2>Yazıda geçen filmler</h2>
        <div class="movie-tags">
          ${movies.map((movie) => {
            const tmdbId = Number(movie.tmdbId);
            if (!Number.isInteger(tmdbId) || tmdbId <= 0) return "";
            const poster = safeHttpsUrl(movie.posterUrl);
            return `
              <a class="movie-tag" href="https://www.themoviedb.org/movie/${tmdbId}" target="_blank" rel="noopener noreferrer">
                ${poster
                  ? `<img src="${escapeHtml(poster)}" alt="" loading="lazy" />`
                  : '<span class="movie-tag-poster">?</span>'}
                <span><strong>${escapeHtml(movie.title || `TMDB ${tmdbId}`)}</strong><span>${escapeHtml(movie.year || "")}</span></span>
                <b aria-hidden="true">↗</b>
              </a>
            `;
          }).join("")}
        </div>
      </section>
    `;
  }

  function updateArticleMeta(post) {
    const title = `${post.title || "CineMatch Blog"} — CineMatch`;
    const description = String(post.excerpt || post.contentText || "CineMatch film yazısı.").slice(0, 160);
    document.title = title;
    document.getElementById("metaDescription")?.setAttribute("content", description);
    document.getElementById("ogTitle")?.setAttribute("content", title);
    document.getElementById("ogDescription")?.setAttribute("content", description);
    document.getElementById("twitterTitle")?.setAttribute("content", title);
    document.getElementById("twitterDescription")?.setAttribute("content", description);
    const cover = safeHttpsUrl(post.coverImageUrl);
    if (cover) {
      document.getElementById("ogImage")?.setAttribute("content", cover);
      document.getElementById("twitterImage")?.setAttribute("content", cover);
    }

    const schema = document.createElement("script");
    schema.type = "application/ld+json";
    schema.textContent = JSON.stringify({
      "@context": "https://schema.org",
      "@type": "BlogPosting",
      headline: post.title || "CineMatch Blog",
      description,
      image: cover || undefined,
      author: { "@type": "Person", name: post.authorName || post.authorUsername || "CineMatch Blogger" },
      datePublished: post.publishedAt?.toDate?.().toISOString(),
      dateModified: post.updatedAt?.toDate?.().toISOString(),
      mainEntityOfPage: window.location.href,
    });
    document.head.appendChild(schema);
  }

  function renderDetail(post) {
    const target = document.getElementById("blogDetail");
    const cover = safeHttpsUrl(post.coverImageUrl);
    const authorName = post.authorName || post.authorUsername || "CineMatch Blogger";
    const tags = Array.isArray(post.tags) && post.tags.length
      ? `<div class="article-tags">${post.tags.map((tag) => `<span>${escapeHtml(tag)}</span>`).join("")}</div>`
      : "";
    updateArticleMeta(post);
    target.innerHTML = `
      <header class="article-head">
        <div class="article-head-inner">
          <p class="article-kicker">${escapeHtml(post.category || "CineMatch Blog")}</p>
          <h1>${escapeHtml(post.title || "Başlıksız Yazı")}</h1>
          ${post.excerpt ? `<p class="article-excerpt">${escapeHtml(post.excerpt)}</p>` : ""}
          <div class="article-byline">
            <span class="article-author">${authorVisual(post, "author-photo")}<span>${escapeHtml(authorName)}${post.authorUsername ? ` · @${escapeHtml(post.authorUsername)}` : ""}</span></span>
            <span>${escapeHtml(formatDate(post.publishedAt))}</span>
            <span>${Number(post.readingMinutes) || 1} dk okuma</span>
          </div>
        </div>
        ${cover ? `<figure class="article-cover"><img src="${escapeHtml(cover)}" alt="${escapeHtml(post.title || "")}" /></figure>` : ""}
      </header>
      <section class="article-paper">
        <div class="article-body">${safeContentHtml(post.contentHtml)}</div>
      </section>
      ${tags}
      ${movieCards(post.movies)}
      <a class="article-end-link" href="/blog"><span>Tüm CineMatch yazılarına dön</span><span>→</span></a>
    `;
  }

  async function loadDetail() {
    const target = document.getElementById("blogDetail");
    const id = new URLSearchParams(window.location.search).get("id");
    if (!id || !/^[A-Za-z0-9_-]{1,120}$/.test(id)) {
      target.innerHTML = '<p class="blog-state page-frame">Blog yazısı bağlantısı geçersiz.</p>';
      return;
    }
    try {
      const snapshot = await db.collection("public_blog_posts").doc(id).get();
      if (!snapshot.exists) {
        target.innerHTML = '<p class="blog-state page-frame">Bu yazı bulunamadı veya artık yayında değil.</p>';
        return;
      }
      renderDetail({ id: snapshot.id, ...snapshot.data() });
    } catch (error) {
      target.innerHTML = `<p class="blog-state page-frame">Yazı yüklenemedi: ${escapeHtml(error.message)}</p>`;
    }
  }

  if (pageType === "list") loadBlogList();
  if (pageType === "detail") loadDetail();
  if (pageType === "home" || document.getElementById("homeBlogList")) loadHomePreview();
})();
