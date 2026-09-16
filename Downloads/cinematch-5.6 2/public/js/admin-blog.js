const { auth, db, functions } = CineAdmin;
const storage = firebase.storage(CineAdmin.app);
const POST_PAGE_SIZE = 30;

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
  authorAvatar: document.getElementById("authorAvatar"),
  editorHeading: document.getElementById("editorHeading"),
  dirtyLabel: document.getElementById("dirtyLabel"),
  newPostButton: document.getElementById("newPostButton"),
  postList: document.getElementById("postList"),
  postCount: document.getElementById("postCount"),
  postSearch: document.getElementById("postSearch"),
  postStatusFilter: document.getElementById("postStatusFilter"),
  loadMorePostsButton: document.getElementById("loadMorePostsButton"),
  bloggerManager: document.getElementById("bloggerManager"),
  bloggerSearch: document.getElementById("bloggerSearch"),
  bloggerSearchButton: document.getElementById("bloggerSearchButton"),
  bloggerMessage: document.getElementById("bloggerMessage"),
  bloggerResults: document.getElementById("bloggerResults"),
  activeBloggers: document.getElementById("activeBloggers"),
  postForm: document.getElementById("postForm"),
  postId: document.getElementById("postId"),
  status: document.getElementById("status"),
  category: document.getElementById("category"),
  title: document.getElementById("title"),
  excerpt: document.getElementById("excerpt"),
  excerptCount: document.getElementById("excerptCount"),
  movieSearch: document.getElementById("movieSearch"),
  movieSearchButton: document.getElementById("movieSearchButton"),
  movieMessage: document.getElementById("movieMessage"),
  movieSearchResults: document.getElementById("movieSearchResults"),
  selectedMovies: document.getElementById("selectedMovies"),
  movieCount: document.getElementById("movieCount"),
  editorToolbar: document.getElementById("editorToolbar"),
  contentEditor: document.getElementById("contentEditor"),
  uploadImageButton: document.getElementById("uploadImageButton"),
  imageInput: document.getElementById("imageInput"),
  uploadProgress: document.getElementById("uploadProgress"),
  contentStats: document.getElementById("contentStats"),
  coverImageUrl: document.getElementById("coverImageUrl"),
  useFirstImageButton: document.getElementById("useFirstImageButton"),
  tags: document.getElementById("tags"),
  slug: document.getElementById("slug"),
  deleteButton: document.getElementById("deleteButton"),
  saveButton: document.getElementById("saveButton"),
  saveMessage: document.getElementById("saveMessage"),
};

const { setMessage, escapeHtml, isPermissionError } = CineAdmin;
let currentUser = null;
let currentAccess = null;
let posts = [];
let selectedMovies = [];
let postPageSize = POST_PAGE_SIZE;
let savedEditorRange = null;
let isDirty = false;
let isHydrating = false;
const pendingImages = new Map();
let draggedFigure = null;
let dropMarker = null;

function slugify(value) {
  return String(value || "")
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
  return [...new Set(
    String(value || "")
      .split(",")
      .map((tag) => tag.trim())
      .filter(Boolean)
  )].slice(0, 12);
}

function timestampMillis(value) {
  if (typeof value === "number") return value;
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value && typeof value.seconds === "number") return value.seconds * 1000;
  return 0;
}

function formatUpdatedAt(value) {
  const millis = timestampMillis(value);
  if (!millis) return "Henüz kaydedilmedi";
  return new Date(millis).toLocaleDateString("tr-TR", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function setDirty(value = true) {
  if (isHydrating) return;
  isDirty = value;
  els.dirtyLabel.classList.toggle("hidden", !value);
}

function showLogin() {
  els.authLoadingPanel.classList.add("hidden");
  els.adminPanel.classList.add("hidden");
  els.loginPanel.classList.remove("hidden");
}

function showAdmin(access) {
  const profile = access.profile || {};
  const authorName = profile.displayName || profile.username || currentUser.email || "Blogger";
  els.authLoadingPanel.classList.add("hidden");
  els.loginPanel.classList.add("hidden");
  els.adminPanel.classList.remove("hidden");
  els.currentUserLabel.textContent = profile.username
    ? `${authorName} · @${profile.username}`
    : authorName;
  els.authorAvatar.textContent = authorName.slice(0, 1).toLocaleUpperCase("tr-TR");
  if (profile.photoUrl) {
    els.authorAvatar.style.backgroundImage = `url("${String(profile.photoUrl).replace(/["\\]/g, "")}")`;
    els.authorAvatar.textContent = "";
  } else {
    els.authorAvatar.style.backgroundImage = "";
  }
}

function ensurePostId() {
  if (!els.postId.value) {
    els.postId.value = db.collection("blog_posts").doc().id;
  }
  return els.postId.value;
}

function cleanEditorHtml() {
  const clone = els.contentEditor.cloneNode(true);
  clone.querySelectorAll(".image-controls, .image-drop-marker").forEach((node) => node.remove());
  clone.querySelectorAll("[contenteditable]").forEach((node) => node.removeAttribute("contenteditable"));
  clone.querySelectorAll("[draggable]").forEach((node) => node.removeAttribute("draggable"));
  clone.querySelectorAll("[data-temp-image-id]").forEach((node) => node.removeAttribute("data-temp-image-id"));
  clone.querySelectorAll("[class]").forEach((node) => node.removeAttribute("class"));
  return clone.innerHTML.trim();
}

function editorImages() {
  return [...els.contentEditor.querySelectorAll("img")]
    .map((image) => ({
      url: String(image.getAttribute("src") || "").trim(),
      path: String(image.dataset.storagePath || "").trim(),
      alt: String(image.getAttribute("alt") || "").trim().slice(0, 180),
    }))
    .filter((image) => image.url)
    .slice(0, 30);
}

function collectForm() {
  const title = els.title.value.trim();
  return {
    id: ensurePostId(),
    status: els.status.value,
    category: els.category.value,
    title,
    slug: els.slug.value.trim() || slugify(title),
    excerpt: els.excerpt.value.trim(),
    contentHtml: cleanEditorHtml(),
    coverImageUrl: els.coverImageUrl.value.trim(),
    tags: parseTags(els.tags.value),
    movies: selectedMovies,
    images: editorImages(),
  };
}

function addImageControls(figure) {
  if (figure.querySelector(".image-controls")) return;
  const controls = document.createElement("span");
  controls.className = "image-controls";
  controls.contentEditable = "false";
  controls.innerHTML = `
    <span class="image-drag-hint" title="Görseli paragraf aralığına sürükle">⠿ Sürükle</span>
    <button type="button" data-image-action="up" title="Görseli yukarı taşı">↑</button>
    <button type="button" data-image-action="down" title="Görseli aşağı taşı">↓</button>
    <button type="button" data-image-action="remove" title="Görseli yazıdan çıkar">×</button>
  `;
  figure.appendChild(controls);
}

function decorateFigures() {
  els.contentEditor.querySelectorAll("figure").forEach((figure) => {
    figure.draggable = true;
    const image = figure.querySelector("img");
    if (image) {
      image.contentEditable = "false";
      figure.classList.toggle("pending-image", Boolean(image.dataset.tempImageId));
    }
    let caption = figure.querySelector("figcaption");
    if (!caption) {
      caption = document.createElement("figcaption");
      figure.appendChild(caption);
    }
    caption.contentEditable = "true";
    addImageControls(figure);
  });
}

function discardPendingImage(tempId) {
  const pending = pendingImages.get(tempId);
  if (!pending) return;
  URL.revokeObjectURL(pending.objectUrl);
  pendingImages.delete(tempId);
}

function cleanupPendingImages() {
  pendingImages.forEach((pending) => URL.revokeObjectURL(pending.objectUrl));
  pendingImages.clear();
  removeDropMarker();
}

function pruneDetachedPendingImages() {
  const activeIds = new Set(
    [...els.contentEditor.querySelectorAll("img[data-temp-image-id]")]
      .map((image) => image.dataset.tempImageId)
  );
  [...pendingImages.keys()].forEach((tempId) => {
    if (activeIds.has(tempId)) return;
    const pending = pendingImages.get(tempId);
    if (pending && els.coverImageUrl.value === pending.objectUrl) els.coverImageUrl.value = "";
    discardPendingImage(tempId);
  });
}

function resetForm() {
  cleanupPendingImages();
  isHydrating = true;
  els.postForm.reset();
  els.postId.value = "";
  els.status.value = "draft";
  els.category.value = "İnceleme";
  els.contentEditor.innerHTML = "";
  els.editorHeading.textContent = "Yeni Blog Yazısı";
  els.deleteButton.disabled = true;
  selectedMovies = [];
  renderSelectedMovies();
  els.movieSearchResults.classList.add("hidden");
  els.movieSearchResults.innerHTML = "";
  setMessage(els.movieMessage, "");
  setMessage(els.saveMessage, "");
  setMessage(els.uploadProgress, "");
  savedEditorRange = null;
  markActivePost("");
  updateWritingStats();
  els.excerptCount.textContent = "0";
  isHydrating = false;
  setDirty(false);
  els.title.focus();
}

function fillForm(post, skipDirtyCheck = false) {
  if (!skipDirtyCheck && isDirty && !window.confirm("Kaydedilmemiş değişikliklerden çıkmak istiyor musunuz?")) return;
  cleanupPendingImages();
  isHydrating = true;
  els.postId.value = post.id;
  els.status.value = post.status || "draft";
  els.category.value = post.category || "İnceleme";
  els.title.value = post.title || "";
  els.excerpt.value = post.excerpt || "";
  els.slug.value = post.slug || "";
  els.coverImageUrl.value = post.coverImageUrl || "";
  els.tags.value = Array.isArray(post.tags) ? post.tags.join(", ") : "";
  els.contentEditor.innerHTML = post.contentHtml || "";
  selectedMovies = Array.isArray(post.movies) ? post.movies.slice(0, 10) : [];
  decorateFigures();
  renderSelectedMovies();
  els.editorHeading.textContent = post.title || "Başlıksız Yazı";
  els.deleteButton.disabled = false;
  els.excerptCount.textContent = String(els.excerpt.value.length);
  setMessage(els.saveMessage, "");
  setMessage(els.uploadProgress, "");
  markActivePost(post.id);
  updateWritingStats();
  isHydrating = false;
  setDirty(false);
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function markActivePost(id) {
  document.querySelectorAll(".article-item").forEach((button) => {
    button.classList.toggle("active", button.dataset.id === id);
  });
}

function visiblePosts() {
  const search = els.postSearch.value.trim().toLocaleLowerCase("tr-TR");
  const status = els.postStatusFilter.value;
  return posts.filter((post) => {
    if (!currentAccess.canManageAll && post.authorId !== currentUser.uid) return false;
    if (status !== "all" && (post.status || "draft") !== status) return false;
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
}

function renderPosts() {
  const visible = visiblePosts();
  const accessibleCount = currentAccess.canManageAll
    ? posts.length
    : posts.filter((post) => post.authorId === currentUser.uid).length;
  els.postCount.textContent = `${visible.length} / ${accessibleCount} yazı`;

  if (!visible.length) {
    els.postList.innerHTML = '<p class="message">Gösterilecek blog yazısı yok.</p>';
    return;
  }

  els.postList.innerHTML = "";
  visible.forEach((post) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "article-item";
    button.dataset.id = post.id;
    button.innerHTML = `
      <strong>${escapeHtml(post.title || "Başlıksız")}</strong>
      <span class="post-list-meta">
        <span>${escapeHtml(post.status || "draft")} · ${escapeHtml(formatUpdatedAt(post.updatedAtMs))}</span>
        <span class="post-author">${escapeHtml(post.authorName || "Blogger")}</span>
      </span>
    `;
    button.addEventListener("click", () => openPost(post));
    els.postList.appendChild(button);
  });
  markActivePost(els.postId.value);
}

async function openPost(summary) {
  if (isDirty && !window.confirm("Kaydedilmemiş değişikliklerden çıkmak istiyor musunuz?")) return;
  setMessage(els.saveMessage, "Yazı yükleniyor…");
  try {
    const result = await functions.httpsCallable("getBlogPost")({ id: summary.id });
    fillForm(result.data.post, true);
  } catch (error) {
    setMessage(els.saveMessage, error.message, "error");
  }
}

async function loadPosts() {
  els.postList.innerHTML = '<p class="message">Yazılar yükleniyor…</p>';
  try {
    const result = await functions.httpsCallable("listBlogPosts")({ limit: postPageSize });
    posts = Array.isArray(result.data && result.data.posts) ? result.data.posts : [];
    renderPosts();
    els.loadMorePostsButton.classList.toggle("hidden", !(result.data && result.data.hasMore));
  } catch (error) {
    els.postList.innerHTML = `<p class="message error">${escapeHtml(error.message)}</p>`;
  }
}

function renderSelectedMovies() {
  els.movieCount.textContent = `${selectedMovies.length} / 10`;
  if (!selectedMovies.length) {
    els.selectedMovies.innerHTML = '<p class="empty-inline">Henüz film etiketlenmedi.</p>';
    return;
  }
  els.selectedMovies.innerHTML = selectedMovies.map((movie) => `
    <span class="selected-movie">
      ${escapeHtml(movie.title)}${movie.year ? ` (${escapeHtml(movie.year)})` : ""}
      <button type="button" data-remove-movie="${Number(movie.tmdbId)}" aria-label="${escapeHtml(movie.title)} etiketini kaldır">×</button>
    </span>
  `).join("");
}

function bloggerRows(users, emptyMessage) {
  if (!users.length) return `<p class="empty-inline">${escapeHtml(emptyMessage)}</p>`;
  return users.map((user) => `
    <div class="blogger-row">
      <span>
        <strong>${escapeHtml(user.displayName || user.username || "CineMatch Kullanıcısı")}</strong>
        <span>${user.username ? `@${escapeHtml(user.username)}` : escapeHtml(user.uid)}</span>
      </span>
      <button type="button" class="${user.isBlogEditor ? "revoke" : ""}" data-blogger-uid="${escapeHtml(user.uid)}" data-blogger-active="${user.isBlogEditor ? "false" : "true"}">
        ${user.isBlogEditor ? "Yetkiyi Kaldır" : "Blogger Yap"}
      </button>
    </div>
  `).join("");
}

async function loadBlogEditors() {
  if (!currentAccess || !currentAccess.canManageAll) return;
  els.activeBloggers.innerHTML = '<p class="empty-inline">Yükleniyor…</p>';
  try {
    const result = await functions.httpsCallable("listBlogEditors")();
    const users = Array.isArray(result.data && result.data.users) ? result.data.users : [];
    els.activeBloggers.innerHTML = bloggerRows(users, "Henüz ayrıca yetkilendirilmiş blogger yok.");
  } catch (error) {
    els.activeBloggers.innerHTML = `<p class="message error">${escapeHtml(error.message)}</p>`;
  }
}

async function searchBloggers() {
  const query = els.bloggerSearch.value.trim();
  if (query.length < 2) {
    setMessage(els.bloggerMessage, "En az 2 karakter yazın.", "error");
    return;
  }
  els.bloggerSearchButton.disabled = true;
  setMessage(els.bloggerMessage, "Kullanıcı aranıyor…");
  try {
    const result = await functions.httpsCallable("searchBlogUsers")({ query });
    const users = Array.isArray(result.data && result.data.users) ? result.data.users : [];
    els.bloggerResults.innerHTML = bloggerRows(users, "Kullanıcı bulunamadı.");
    setMessage(els.bloggerMessage, users.length ? `${users.length} kullanıcı bulundu.` : "");
  } catch (error) {
    setMessage(els.bloggerMessage, error.message, "error");
  } finally {
    els.bloggerSearchButton.disabled = false;
  }
}

async function changeBloggerAccess(button) {
  const uid = button.dataset.bloggerUid;
  const active = button.dataset.bloggerActive === "true";
  button.disabled = true;
  setMessage(els.bloggerMessage, active ? "Blogger yetkisi veriliyor…" : "Yetki kaldırılıyor…");
  try {
    await functions.httpsCallable("setBlogEditor")({ uid, active });
    setMessage(els.bloggerMessage, active ? "Blogger yetkisi verildi." : "Blogger yetkisi kaldırıldı.", "success");
    const refreshes = [loadBlogEditors()];
    if (els.bloggerSearch.value.trim().length >= 2) refreshes.push(searchBloggers());
    await Promise.all(refreshes);
  } catch (error) {
    button.disabled = false;
    setMessage(els.bloggerMessage, error.message, "error");
  }
}

function addMovie(movie) {
  if (selectedMovies.some((item) => Number(item.tmdbId) === Number(movie.tmdbId))) {
    setMessage(els.movieMessage, "Bu film zaten etiketli.", "error");
    return;
  }
  if (selectedMovies.length >= 10) {
    setMessage(els.movieMessage, "Bir yazıya en fazla 10 film etiketlenebilir.", "error");
    return;
  }
  selectedMovies.push({
    tmdbId: Number(movie.tmdbId),
    title: String(movie.title || ""),
    originalTitle: String(movie.originalTitle || ""),
    year: Number(movie.year) || null,
    posterPath: String(movie.posterPath || ""),
    posterUrl: String(movie.posterUrl || ""),
  });
  renderSelectedMovies();
  setMessage(els.movieMessage, "Film etiketlendi.", "success");
  setDirty();
}

async function searchMovies() {
  const query = els.movieSearch.value.trim();
  if (query.length < 2) {
    setMessage(els.movieMessage, "Aramak için en az 2 karakter yazın.", "error");
    return;
  }
  els.movieSearchButton.disabled = true;
  setMessage(els.movieMessage, "TMDB’de aranıyor…");
  try {
    const result = await functions.httpsCallable("searchBlogMovies")({ query });
    const movies = Array.isArray(result.data && result.data.movies) ? result.data.movies : [];
    if (!movies.length) {
      els.movieSearchResults.classList.add("hidden");
      setMessage(els.movieMessage, "Film bulunamadı.");
      return;
    }
    els.movieSearchResults.innerHTML = "";
    movies.forEach((movie) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "movie-result";
      const poster = movie.posterUrl
        ? `<img src="${escapeHtml(movie.posterUrl)}" alt="" loading="lazy" />`
        : '<span class="movie-poster-placeholder">?</span>';
      button.innerHTML = `
        ${poster}
        <span><strong>${escapeHtml(movie.title)}</strong><span>${escapeHtml(movie.year || "Yıl yok")}</span></span>
        <b aria-hidden="true">＋</b>
      `;
      button.addEventListener("click", () => addMovie(movie));
      els.movieSearchResults.appendChild(button);
    });
    els.movieSearchResults.classList.remove("hidden");
    setMessage(els.movieMessage, `${movies.length} sonuç bulundu.`);
  } catch (error) {
    setMessage(els.movieMessage, error.message, "error");
  } finally {
    els.movieSearchButton.disabled = false;
  }
}

function saveSelection() {
  const selection = window.getSelection();
  if (!selection || !selection.rangeCount) return;
  const range = selection.getRangeAt(0);
  if (els.contentEditor.contains(range.commonAncestorContainer)) {
    savedEditorRange = range.cloneRange();
  }
}

function placeCaretAfter(node) {
  const selection = window.getSelection();
  const range = document.createRange();
  range.setStartAfter(node);
  range.collapse(true);
  selection.removeAllRanges();
  selection.addRange(range);
  savedEditorRange = range.cloneRange();
}

function topLevelEditorChild(node) {
  let current = node && node.nodeType === Node.ELEMENT_NODE ? node : node && node.parentElement;
  while (current && current.parentElement !== els.contentEditor) current = current.parentElement;
  return current && current.parentElement === els.contentEditor ? current : null;
}

function savedInsertionReference() {
  if (!savedEditorRange || !els.contentEditor.contains(savedEditorRange.commonAncestorContainer)) return null;
  const block = topLevelEditorChild(savedEditorRange.startContainer);
  return block ? block.nextSibling : null;
}

function insertFigure(url, path, alt, options = {}) {
  const figure = document.createElement("figure");
  const image = document.createElement("img");
  const caption = document.createElement("figcaption");
  image.src = url;
  image.alt = alt || "Blog görseli";
  if (path) image.dataset.storagePath = path;
  if (options.tempId) {
    image.dataset.tempImageId = options.tempId;
    figure.classList.add("pending-image");
  }
  image.contentEditable = "false";
  caption.contentEditable = "true";
  figure.draggable = true;
  figure.append(image, caption);
  addImageControls(figure);

  const beforeNode = options.beforeNode && options.beforeNode.parentNode === els.contentEditor
    ? options.beforeNode
    : savedInsertionReference();
  if (beforeNode) {
    els.contentEditor.insertBefore(figure, beforeNode);
  } else {
    els.contentEditor.appendChild(figure);
  }

  if (!figure.nextElementSibling || figure.nextElementSibling.tagName === "FIGURE") {
    const paragraph = document.createElement("p");
    paragraph.appendChild(document.createElement("br"));
    figure.after(paragraph);
  }
  placeCaretAfter(figure);
  updateWritingStats();
  setDirty();
  return figure;
}

function safeFileName(name) {
  const extension = String(name || "image.jpg").split(".").pop().toLowerCase();
  const safeExtension = ["jpg", "jpeg", "png", "webp", "gif"].includes(extension) ? extension : "jpg";
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${safeExtension}`;
}

function validImageFiles(files) {
  const availableSlots = Math.max(0, 30 - els.contentEditor.querySelectorAll("figure img").length);
  return [...files].filter((file) => {
    if (!file.type.startsWith("image/")) return false;
    if (file.size > 8 * 1024 * 1024) {
      setMessage(els.uploadProgress, `${file.name} 8 MB sınırını aşıyor.`, "error");
      return false;
    }
    return true;
  }).slice(0, availableSlots);
}

function queueImages(files, beforeNode = null) {
  const validFiles = validImageFiles(files);
  if (!validFiles.length) return;
  const ownsAnchor = !beforeNode || beforeNode.parentNode !== els.contentEditor;
  const insertionAnchor = ownsAnchor ? document.createComment("image-insertion-point") : beforeNode;
  if (ownsAnchor) {
    els.contentEditor.insertBefore(insertionAnchor, savedInsertionReference());
  }

  validFiles.forEach((file) => {
    const tempId = window.crypto && typeof window.crypto.randomUUID === "function"
      ? window.crypto.randomUUID()
      : `temp-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
    const objectUrl = URL.createObjectURL(file);
    pendingImages.set(tempId, { file, objectUrl });
    insertFigure(
      objectUrl,
      "",
      file.name.replace(/\.[^.]+$/, ""),
      { tempId, beforeNode: insertionAnchor }
    );
  });
  if (ownsAnchor) insertionAnchor.remove();
  els.imageInput.value = "";
  setMessage(
    els.uploadProgress,
    `${validFiles.length} görsel hazır. Yalnızca yazıyı kaydettiğinde Storage’a yüklenecek.`,
    "success"
  );
}

function removeDropMarker() {
  if (dropMarker) dropMarker.remove();
  dropMarker = null;
  if (els.contentEditor.lastElementChild?.tagName === "FIGURE") {
    const paragraph = document.createElement("p");
    paragraph.appendChild(document.createElement("br"));
    els.contentEditor.appendChild(paragraph);
  }
}

function showDropMarker(clientY) {
  if (!dropMarker) {
    dropMarker = document.createElement("div");
    dropMarker.className = "image-drop-marker";
    dropMarker.contentEditable = "false";
  }
  const blocks = [...els.contentEditor.children]
    .filter((node) => node !== dropMarker && node !== draggedFigure);
  const beforeNode = blocks.find((node) => {
    const rect = node.getBoundingClientRect();
    return clientY < rect.top + (rect.height / 2);
  });
  els.contentEditor.insertBefore(dropMarker, beforeNode || null);
  return dropMarker;
}

async function uploadPendingImages(postId, uploadedImages) {
  const images = [...els.contentEditor.querySelectorAll("img[data-temp-image-id]")];
  if (!images.length) return;

  els.uploadImageButton.disabled = true;
  for (let index = 0; index < images.length; index += 1) {
    const image = images[index];
    const tempId = image.dataset.tempImageId;
    const pending = pendingImages.get(tempId);
    if (!pending) throw new Error("Geçici görsel bulunamadı. Görseli kaldırıp yeniden ekleyin.");

    const path = `blog_images/${currentUser.uid}/${postId}/${safeFileName(pending.file.name)}`;
    const ref = storage.ref().child(path);
    const figure = image.closest("figure");
    figure?.classList.add("is-uploading");
    setMessage(els.uploadProgress, `${index + 1}/${images.length}: ${pending.file.name} kayda hazırlanıyor…`);

    const snapshot = await ref.put(pending.file, {
      contentType: pending.file.type,
      customMetadata: { postId, uploadedBy: currentUser.uid },
    });
    const url = await snapshot.ref.getDownloadURL();
    uploadedImages.push({ image, figure, pending, tempId, path, ref, url });
    if (els.coverImageUrl.value === pending.objectUrl) els.coverImageUrl.value = url;
    image.src = url;
    image.dataset.storagePath = path;
    delete image.dataset.tempImageId;
    figure?.classList.remove("pending-image", "is-uploading");
  }
}

function finalizeUploadedImages(uploadedImages) {
  uploadedImages.forEach(({ pending, tempId }) => {
    URL.revokeObjectURL(pending.objectUrl);
    pendingImages.delete(tempId);
  });
}

async function rollbackUploadedImages(uploadedImages) {
  if (!uploadedImages.length) return;
  await Promise.allSettled(uploadedImages.map(({ ref }) => ref.delete()));
  uploadedImages.forEach(({ image, figure, pending, tempId, url }) => {
    if (els.coverImageUrl.value === url) els.coverImageUrl.value = pending.objectUrl;
    if (!image.isConnected) return;
    image.src = pending.objectUrl;
    image.dataset.tempImageId = tempId;
    delete image.dataset.storagePath;
    figure?.classList.add("pending-image");
    figure?.classList.remove("is-uploading");
  });
}

function updateWritingStats() {
  const text = els.contentEditor.innerText.trim();
  const words = text ? text.split(/\s+/).filter(Boolean).length : 0;
  const minutes = words ? Math.max(1, Math.ceil(words / 220)) : 0;
  els.contentStats.textContent = `${words} kelime · yaklaşık ${minutes} dk okuma`;
}

function validatePostBeforeSave() {
  if (!els.title.value.trim()) throw new Error("Yazı başlığı gerekli.");
  const contentText = els.contentEditor.innerText.replace(/\s+/g, " ").trim();
  if (els.status.value === "published" && contentText.length < 20) {
    throw new Error("Yayınlamak için en az 20 karakterlik bir yazı içeriği gerekli.");
  }
}

els.loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  els.loginButton.disabled = true;
  setMessage(els.loginMessage, "Giriş yapılıyor…");
  try {
    await CineAdmin.persistenceReady;
    await auth.signInWithEmailAndPassword(els.loginEmail.value.trim(), els.loginPassword.value);
    setMessage(els.loginMessage, "");
  } catch (error) {
    setMessage(els.loginMessage, error.message, "error");
  } finally {
    els.loginButton.disabled = false;
  }
});

els.logoutButton.addEventListener("click", async () => {
  if (isDirty && !window.confirm("Kaydedilmemiş değişiklikler var. Yine de çıkmak istiyor musunuz?")) return;
  await CineAdmin.logout();
});
els.newPostButton.addEventListener("click", () => {
  if (isDirty && !window.confirm("Kaydedilmemiş değişikliklerden çıkmak istiyor musunuz?")) return;
  resetForm();
});
els.postSearch.addEventListener("input", renderPosts);
els.postStatusFilter.addEventListener("change", renderPosts);
els.loadMorePostsButton.addEventListener("click", () => {
  postPageSize += POST_PAGE_SIZE;
  loadPosts();
});
els.bloggerSearchButton.addEventListener("click", searchBloggers);
els.bloggerSearch.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    searchBloggers();
  }
});
els.bloggerManager.addEventListener("click", (event) => {
  const button = event.target.closest("[data-blogger-uid]");
  if (button) changeBloggerAccess(button);
});

els.movieSearchButton.addEventListener("click", searchMovies);
els.movieSearch.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    searchMovies();
  }
});
els.selectedMovies.addEventListener("click", (event) => {
  const button = event.target.closest("[data-remove-movie]");
  if (!button) return;
  const tmdbId = Number(button.dataset.removeMovie);
  selectedMovies = selectedMovies.filter((movie) => Number(movie.tmdbId) !== tmdbId);
  renderSelectedMovies();
  setDirty();
});

els.editorToolbar.addEventListener("mousedown", (event) => event.preventDefault());
els.editorToolbar.addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (!button) return;
  if (button === els.uploadImageButton) return;
  els.contentEditor.focus();
  if (button.dataset.command) {
    document.execCommand(button.dataset.command, false, null);
  } else if (button.dataset.block) {
    document.execCommand("formatBlock", false, `<${button.dataset.block}>`);
  } else if (button.dataset.action === "link") {
    const value = window.prompt("Bağlantı adresi (https://…)");
    if (value && /^https:\/\//i.test(value.trim())) {
      document.execCommand("createLink", false, value.trim());
    }
  }
  saveSelection();
  setDirty();
});

els.contentEditor.addEventListener("keyup", saveSelection);
els.contentEditor.addEventListener("mouseup", saveSelection);
els.contentEditor.addEventListener("focus", saveSelection);
els.contentEditor.addEventListener("input", () => {
  updateWritingStats();
  setDirty();
});
els.contentEditor.addEventListener("paste", (event) => {
  event.preventDefault();
  const text = event.clipboardData.getData("text/plain");
  document.execCommand("insertText", false, text);
});
els.contentEditor.addEventListener("dragstart", (event) => {
  const figure = event.target.closest("figure");
  if (!figure) return;
  draggedFigure = figure;
  figure.classList.add("is-dragging");
  event.dataTransfer.effectAllowed = "move";
  event.dataTransfer.setData("text/x-cinematch-blog-image", "move");
});
els.contentEditor.addEventListener("dragover", (event) => {
  const hasFiles = [...event.dataTransfer.types].includes("Files");
  if (!draggedFigure && !hasFiles) return;
  event.preventDefault();
  event.dataTransfer.dropEffect = draggedFigure ? "move" : "copy";
  showDropMarker(event.clientY);
});
els.contentEditor.addEventListener("drop", (event) => {
  const hasFiles = event.dataTransfer.files && event.dataTransfer.files.length;
  if (!draggedFigure && !hasFiles) return;
  event.preventDefault();
  const marker = dropMarker || showDropMarker(event.clientY);
  if (draggedFigure) {
    els.contentEditor.insertBefore(draggedFigure, marker);
    draggedFigure.classList.remove("is-dragging");
    draggedFigure = null;
    updateWritingStats();
    setDirty();
  } else {
    queueImages(event.dataTransfer.files, marker);
  }
  removeDropMarker();
});
els.contentEditor.addEventListener("dragleave", (event) => {
  if (!event.relatedTarget || !els.contentEditor.contains(event.relatedTarget)) removeDropMarker();
});
els.contentEditor.addEventListener("dragend", () => {
  draggedFigure?.classList.remove("is-dragging");
  draggedFigure = null;
  removeDropMarker();
});
els.contentEditor.addEventListener("click", (event) => {
  const button = event.target.closest("[data-image-action]");
  if (!button) return;
  const figure = button.closest("figure");
  if (!figure) return;
  const action = button.dataset.imageAction;
  if (action === "remove") {
    if (window.confirm("Bu görsel yazıdan çıkarılsın mı?")) {
      const image = figure.querySelector("img");
      if (image && els.coverImageUrl.value === image.src) els.coverImageUrl.value = "";
      if (image?.dataset.tempImageId) discardPendingImage(image.dataset.tempImageId);
      figure.remove();
    }
  } else if (action === "up" && figure.previousElementSibling) {
    figure.parentNode.insertBefore(figure, figure.previousElementSibling);
  } else if (action === "down" && figure.nextElementSibling) {
    figure.parentNode.insertBefore(figure.nextElementSibling, figure);
  }
  updateWritingStats();
  setDirty();
});

els.uploadImageButton.addEventListener("click", () => {
  saveSelection();
  els.imageInput.click();
});
els.imageInput.addEventListener("change", () => queueImages(els.imageInput.files));
els.useFirstImageButton.addEventListener("click", () => {
  const image = els.contentEditor.querySelector("img");
  if (!image) {
    setMessage(els.uploadProgress, "Önce yazıya bir görsel ekleyin.", "error");
    return;
  }
  els.coverImageUrl.value = image.src;
  setDirty();
});

els.excerpt.addEventListener("input", () => {
  els.excerptCount.textContent = String(els.excerpt.value.length);
});
els.title.addEventListener("blur", () => {
  if (!els.slug.value.trim()) els.slug.value = slugify(els.title.value);
});
els.postForm.addEventListener("input", () => setDirty());
els.postForm.addEventListener("change", () => setDirty());

els.postForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  pruneDetachedPendingImages();
  els.saveButton.disabled = true;
  els.contentEditor.classList.add("is-saving");
  const uploadedImages = [];
  setMessage(
    els.saveMessage,
    pendingImages.size ? "Görseller yükleniyor ve yazı kaydediliyor…" : "Kaydediliyor…"
  );
  try {
    validatePostBeforeSave();
    const postId = ensurePostId();
    await uploadPendingImages(postId, uploadedImages);
    const payload = collectForm();
    const result = await functions.httpsCallable("saveBlogPost")(payload);
    finalizeUploadedImages(uploadedImages);
    els.postId.value = result.data.id;
    els.slug.value = result.data.slug;
    els.deleteButton.disabled = false;
    els.editorHeading.textContent = payload.title;
    setDirty(false);
    setMessage(
      els.saveMessage,
      payload.status === "published"
        ? "Yazı yayınlandı."
        : payload.status === "archived" ? "Yazı arşivlendi." : "Taslak kaydedildi.",
      "success"
    );
    setMessage(
      els.uploadProgress,
      uploadedImages.length ? `${uploadedImages.length} görsel yazıyla birlikte kaydedildi.` : "",
      "success"
    );
    await loadPosts();
  } catch (error) {
    await rollbackUploadedImages(uploadedImages);
    setMessage(els.saveMessage, error.message, "error");
    if (uploadedImages.length) {
      setMessage(els.uploadProgress, "Kayıt tamamlanmadığı için yüklenen görseller Storage’dan geri alındı.", "error");
    }
  } finally {
    els.saveButton.disabled = false;
    els.uploadImageButton.disabled = false;
    els.contentEditor.classList.remove("is-saving");
    els.contentEditor.querySelectorAll("figure.is-uploading").forEach((figure) => figure.classList.remove("is-uploading"));
  }
});

els.deleteButton.addEventListener("click", async () => {
  const id = els.postId.value.trim();
  if (!id || !window.confirm("Bu blog yazısı ve yazıya yüklenen görseller kalıcı olarak silinsin mi?")) return;
  els.deleteButton.disabled = true;
  setMessage(els.saveMessage, "Siliniyor…");
  try {
    await functions.httpsCallable("deleteBlogPost")({ id });
    resetForm();
    setMessage(els.saveMessage, "Blog yazısı silindi.", "success");
    await loadPosts();
  } catch (error) {
    els.deleteButton.disabled = false;
    setMessage(els.saveMessage, error.message, "error");
  }
});

window.addEventListener("keydown", (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLocaleLowerCase("tr-TR") === "s") {
    event.preventDefault();
    els.postForm.requestSubmit();
  }
});
window.addEventListener("beforeunload", (event) => {
  if (!isDirty) return;
  event.preventDefault();
  event.returnValue = "";
});

auth.onAuthStateChanged(async (user) => {
  if (!user) {
    currentUser = null;
    currentAccess = null;
    showLogin();
    return;
  }

  currentUser = user;
  try {
    await CineAdmin.persistenceReady;
    currentAccess = await CineAdmin.requireRole(user, "blogEditor", async () => {
      const result = await functions.httpsCallable("isBlogEditor")();
      return result.data;
    });
    showAdmin(currentAccess);
    els.bloggerManager.classList.toggle("hidden", !currentAccess.canManageAll);
    if (currentAccess.canManageAll) loadBlogEditors();
    postPageSize = POST_PAGE_SIZE;
    resetForm();
    loadPosts();
  } catch (error) {
    if (isPermissionError(error)) {
      await CineAdmin.logout();
      showLogin();
      setMessage(els.loginMessage, "Bu hesap blogger olarak yetkilendirilmemiş.", "error");
      return;
    }
    showAdmin({ profile: { displayName: user.displayName || user.email } });
    setMessage(els.saveMessage, "Yetki kontrolü geçici olarak tamamlanamadı. Sayfayı yenileyin.", "error");
  }
});
