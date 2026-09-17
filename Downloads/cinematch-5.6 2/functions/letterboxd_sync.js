/* eslint-disable */
"use strict";

const admin = require("firebase-admin");
const axios = require("axios");
const cheerio = require("cheerio");
const crypto = require("crypto");
const zlib = require("zlib");
const { getFunctions } = require("firebase-admin/functions");
const { HttpsError } = require("firebase-functions/v2/https");

const PROVIDER = "letterboxd";
const SCHEMA_VERSION = 2;
const TASK_FUNCTION_NAME = "processLetterboxdSyncTask";
const LETTERBOXD_ORIGIN = "https://letterboxd.com";
const LETTERBOXD_USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36";
const MAX_PAGE_BYTES = 2 * 1024 * 1024;
const MAX_COMPRESSED_SNAPSHOT_BYTES = 64 * 1024 * 1024;
const MAX_UNCOMPRESSED_SNAPSHOT_BYTES = 256 * 1024 * 1024;
const MAX_PAGES_PER_PHASE = 1000;
const PAGES_PER_TASK = 12;
const MAX_LIBRARY_ITEMS = 50000;
const MAX_DIARY_ITEMS = 75000;
const HYDRATE_BATCH_SIZE = 40;
const INLINE_CATALOG_LIMIT = 40;
const AUTOMATIC_CATALOG_LIMIT = 400;
const LEGACY_MATCH_LIST_LIMIT = 1000;
const BULK_WRITE_CHUNK_SIZE = 400;
const MIN_NEW_JOB_INTERVAL_MS = 30 * 1000;
const SYNC_QUOTA_WINDOW_MS = 24 * 60 * 60 * 1000;
const SYNC_QUOTA_PER_WINDOW = 12;
// Bir task en fazla 30 dakika çalışır. Lease bunun biraz üzerinde tutularak
// at-least-once teslimatın aynı phase/cursor'u paralel işletmesi engellenir.
const TASK_CLAIM_TTL_MS = 31 * 60 * 1000;
const PHASE_ORDER = Object.freeze({
  profile: 0,
  films: 1,
  diary: 2,
  watchlist: 3,
  finalize: 4,
  hydrate: 5,
  complete: 6,
});

class LetterboxdSyncError extends Error {
  constructor(code, message, { permanent = false, cause } = {}) {
    super(message);
    this.name = "LetterboxdSyncError";
    this.code = code;
    this.permanent = permanent;
    if (cause) this.cause = cause;
  }
}

function cleanString(value, maxLength = 500) {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, maxLength);
}

function normalizeUsername(value) {
  const username = cleanString(value, 40).replace(/^@+/, "");
  if (!/^[A-Za-z0-9_.-]{2,40}$/.test(username)) return "";
  return username.toLowerCase();
}

function positiveInteger(value) {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : null;
}

function normalizeYear(value) {
  const year = Number(value);
  return Number.isInteger(year) && year >= 1870 && year <= 2200 ? year : null;
}

function normalizeRating(value) {
  if (value === null || value === undefined || value === "") return null;
  const rating = Number(value);
  if (!Number.isFinite(rating) || rating < 0.5 || rating > 5) return null;
  const doubled = Math.round(rating * 2);
  return Math.abs(doubled / 2 - rating) < 0.001 ? doubled / 2 : null;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function sha256(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function taskId(parts) {
  return `lb-${sha256(parts.join("|")).slice(0, 40)}`;
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (Number.isFinite(Number(value._seconds))) {
    return Number(value._seconds) * 1000;
  }
  return 0;
}

function isActiveProfile(data) {
  if (!data || typeof data !== "object") return false;
  if (data.registrationStatus === "active" && data.onboardingCompleted === true) {
    return true;
  }
  const age = Number(data.age);
  return !Object.prototype.hasOwnProperty.call(data, "registrationStatus") &&
    data.termsAccepted === true && Number.isFinite(age) && age >= 13 && age <= 120;
}

function suspiciousSnapshotShrink(previousCount, nextCount) {
  const previous = Math.max(0, Number(previousCount) || 0);
  const next = Math.max(0, Number(nextCount) || 0);
  // Küçük hesaplarda normal toplu silmelere karışma; büyük bir snapshot'ın
  // tek senkronizasyonda çoğunluğunu kaybetmesi ise HTML/pagination kırılması
  // olabileceğinden mevcut projeksiyonu koru.
  return previous >= 100 && previous - next >= 25 && next < previous * 0.6;
}

function canonicalFilmPath(value) {
  const raw = cleanString(value, 500);
  if (!raw) return "";
  try {
    const url = raw.startsWith("/")
      ? new URL(raw, LETTERBOXD_ORIGIN)
      : new URL(raw);
    if (url.protocol !== "https:" || url.hostname !== "letterboxd.com") return "";
    const match = url.pathname.match(/^\/film\/([a-z0-9][a-z0-9-]{0,159})\/?$/i);
    return match ? `/film/${match[1].toLowerCase()}/` : "";
  } catch (_) {
    return "";
  }
}

function filmKeyFromPath(path) {
  const match = cleanString(path, 500).match(/^\/film\/([a-z0-9][a-z0-9-]{0,159})\/$/);
  return match ? `film:${match[1]}` : "";
}

function normalizeClientFavorites(value) {
  if (!Array.isArray(value)) return [];
  const byKey = new Map();
  for (const raw of value.slice(0, 4)) {
    if (!raw || typeof raw !== "object") continue;
    const uri = canonicalFilmPath(raw.uri || raw.url);
    const key = filmKeyFromPath(uri);
    const title = cleanString(raw.title, 180);
    if (!uri || !key || !title) continue;
    byKey.set(key, {
      key,
      uri,
      title,
      year: normalizeYear(raw.year),
      rating: null,
      liked: false,
      watched: true,
      inWatchlist: false,
      favorite: true,
      letterboxdId: null,
      letterboxdLid: "",
      posterEndpoint: "",
    });
  }
  return [...byKey.values()];
}

function safeProfileUrl(value, username) {
  try {
    const url = value instanceof URL ? value : new URL(value, LETTERBOXD_ORIGIN);
    if (url.protocol !== "https:" || url.hostname !== "letterboxd.com") return "";
    const prefix = `/${username.toLowerCase()}/`;
    if (!url.pathname.toLowerCase().startsWith(prefix)) return "";
    url.hash = "";
    return url.toString();
  } catch (_) {
    return "";
  }
}

function parsePosterIdentifier(raw) {
  const value = cleanString(raw, 1200);
  if (!value) return { letterboxdId: null, letterboxdLid: "" };
  try {
    const decoded = JSON.parse(value);
    const uid = cleanString(decoded.uid, 100);
    const idMatch = uid.match(/^film:(\d+)$/);
    return {
      letterboxdId: idMatch ? positiveInteger(idMatch[1]) : null,
      letterboxdLid: cleanString(decoded.lid, 40),
    };
  } catch (_) {
    return { letterboxdId: null, letterboxdLid: "" };
  }
}

function titleAndYear($poster, $container) {
  const displayName = cleanString(
    $poster.attr("data-item-name") || $poster.attr("data-item-full-display-name"),
    240
  );
  const match = displayName.match(/^(.*) \((\d{4})\)$/);
  const imageTitle = cleanString(
    $poster.find("img[alt]").first().attr("alt") ||
      $container.find(".primaryname a").first().text(),
    180
  );
  return {
    title: imageTitle || cleanString(match ? match[1] : displayName, 180),
    year: normalizeYear(match && match[2]),
  };
}

function ratingFromContainer($container) {
  const rangeValue = $container.find('input[type="range"][value]').first().attr("value");
  const rangeRating = Number(rangeValue);
  if (Number.isFinite(rangeRating) && rangeRating >= 1 && rangeRating <= 10) {
    return rangeRating / 2;
  }
  let className = "";
  $container.find(".rating").each((_, element) => {
    if (!className) {
      const candidate = cleanString($container.find(element).attr("class"), 200);
      if (/\brated-\d+\b/.test(candidate)) className = candidate;
    }
  });
  const match = className.match(/\brated-(10|[1-9])\b/);
  return match ? Number(match[1]) / 2 : null;
}

function filmFromContainer($, element, defaults = {}) {
  const $container = $(element);
  const $poster = $container
    .find('[data-item-slug][data-item-link], [data-item-link^="/film/"]')
    .first();
  if (!$poster.length) return null;

  const slug = cleanString($poster.attr("data-item-slug"), 160).toLowerCase();
  const path = canonicalFilmPath($poster.attr("data-item-link")) ||
    canonicalFilmPath(slug ? `/film/${slug}/` : "");
  const key = filmKeyFromPath(path);
  const details = titleAndYear($poster, $container);
  if (!key || !path || !details.title) return null;

  const identifiers = parsePosterIdentifier($poster.attr("data-postered-identifier"));
  const viewingData = $container.find(".poster-viewingdata");
  const liked =
    viewingData.find(".liked-micro, .icon-liked").length > 0 ||
    $container.find(".liked-micro").length > 0;

  return {
    key,
    uri: path,
    title: details.title,
    year: details.year,
    rating: defaults.watched === true ? ratingFromContainer($container) : null,
    liked: defaults.watched === true && liked,
    watched: defaults.watched === true,
    inWatchlist: defaults.inWatchlist === true,
    favorite: defaults.favorite === true,
    letterboxdId: identifiers.letterboxdId,
    letterboxdLid: identifiers.letterboxdLid,
    posterEndpoint: cleanString($poster.attr("data-poster-url"), 500),
  };
}

function parseNextUrl($, username) {
  const href = cleanString(
    $("a.next[href], link[rel=\"next\"][href]").last().attr("href"),
    1000
  );
  return href ? safeProfileUrl(href, username) : "";
}

function paginationEvidence(
  $,
  nextUrl,
  itemCount,
  expectedPageSize,
  emptyConfirmed,
  pageNumber,
  documentComplete
) {
  if (nextUrl) return { present: true, lastPageConfirmed: false };
  if (emptyConfirmed) {
    // Boş profil ilk sayfada güvenle terminaldir. Daha sonraki bir sayfanın
    // boş dönmesi ise sayfalama sırasında veri kayması/geçici HTML ihtimalidir;
    // açık bir son-sayfa işareti olmadan mevcut verileri sildirmemelidir.
    if (pageNumber === 0 && documentComplete) {
      return { present: $(".pagination").length > 0, lastPageConfirmed: true };
    }
  }
  const $pagination = $(".pagination").last();
  const present = $pagination.length > 0;
  const numericPages = $pagination.find(".paginate-page").map((_, element) =>
    Number(cleanString($(element).text(), 20))
  ).get().filter((value) => Number.isInteger(value) && value > 0);
  const currentPage = Number(cleanString(
    $pagination.find(".paginate-current").first().text(),
    20
  ));
  const maxPage = numericPages.length ? Math.max(...numericPages) : 0;
  const disabledNext = $pagination.find(".paginate-nextprev.paginate-disabled")
    .filter((_, element) => $(element).find(".next").length > 0)
    .length > 0;
  const explicitLast = present && (
    disabledNext ||
    (Number.isInteger(currentPage) && currentPage > 0 && maxPage > 0 && currentPage >= maxPage)
  );
  const safeSinglePage = !present && pageNumber === 0 && itemCount < expectedPageSize;
  return {
    present,
    lastPageConfirmed: documentComplete && (explicitLast || safeSinglePage),
  };
}

function pageBelongsToUser($, username) {
  const expectedPrefix = `/${username.toLowerCase()}/`;
  const candidates = [
    $('meta[property="og:url"]').attr("content"),
    $('link[rel="canonical"]').attr("href"),
  ];
  if (candidates.some((candidate) => {
    const safe = safeProfileUrl(cleanString(candidate, 1000), username);
    return safe && new URL(safe).pathname.toLowerCase().startsWith(expectedPrefix);
  })) return true;
  return $(`a[href="/${username}/films/"], a[href^="/${username}/diary/"]`).length > 0;
}

function hasExplicitEmptyState($) {
  if ($(".empty, .empty-state, .no-results, .js-list-entries.-empty").length > 0) {
    return true;
  }
  const text = cleanString($("main, #content, .content-wrap").text(), 5000).toLowerCase();
  return /\b(no films|no diary entries|no entries|nothing here|hasn['’]t logged|haven['’]t logged|hasn['’]t watched|haven['’]t watched|watchlist is empty)\b/.test(text);
}

function hasCompleteHtmlDocument(html) {
  return typeof html === "string" && /<\/html>\s*$/i.test(html);
}

function dedupeFilms(items) {
  const byKey = new Map();
  for (const item of items) {
    if (!item || !item.key) continue;
    const previous = byKey.get(item.key);
    if (!previous) {
      byKey.set(item.key, item);
      continue;
    }
    byKey.set(item.key, {
      ...previous,
      ...item,
      title: item.title || previous.title,
      year: item.year || previous.year,
      rating: item.rating ?? previous.rating,
      liked: previous.liked || item.liked,
      watched: previous.watched || item.watched,
      inWatchlist: previous.inWatchlist || item.inWatchlist,
      favorite: previous.favorite || item.favorite,
      letterboxdId: item.letterboxdId || previous.letterboxdId,
      letterboxdLid: item.letterboxdLid || previous.letterboxdLid,
    });
  }
  return [...byKey.values()];
}

function parseFilmPage(html, username, defaults = { watched: true }) {
  const $ = cheerio.load(html);
  const items = [];
  $("li.griditem, li.poster-container").each((_, element) => {
    const film = filmFromContainer($, element, defaults);
    if (film) items.push(film);
  });
  const deduped = dedupeFilms(items);
  const emptyConfirmed = deduped.length === 0 && hasExplicitEmptyState($);
  const nextUrl = parseNextUrl($, username);
  const documentComplete = hasCompleteHtmlDocument(html);
  const pagination = paginationEvidence(
    $,
    nextUrl,
    deduped.length,
    positiveInteger(defaults.expectedPageSize) || 72,
    emptyConfirmed,
    Math.max(0, Number(defaults.pageNumber) || 0),
    documentComplete
  );
  return {
    items: deduped,
    nextUrl,
    valid: documentComplete && pageBelongsToUser($, username) &&
      (deduped.length > 0 || emptyConfirmed),
    emptyConfirmed,
    lastPageConfirmed: pagination.lastPageConfirmed,
  };
}

function parseProfilePage(html, username) {
  const $ = cheerio.load(html);
  const favorites = [];
  $("#favourites li, section#favourites li").each((_, element) => {
    const film = filmFromContainer($, element, { watched: true, favorite: true });
    if (film) favorites.push(film);
  });
  const pageOwner = cleanString(
    $('[data-owner]').first().attr("data-owner") ||
      $('meta[property="og:url"]').attr("content"),
    500
  ).toLowerCase();
  return {
    favorites: dedupeFilms(favorites).slice(0, 4),
    favoritesKnown: $("#favourites, section#favourites").length > 0,
    looksValid:
      hasCompleteHtmlDocument(html) &&
      pageBelongsToUser($, username) &&
      (pageOwner.includes(username.toLowerCase()) ||
        $(`a[href="/${username}/films/"]`).length > 0),
  };
}

function parseDiaryPage(html, username, defaults = {}) {
  const $ = cheerio.load(html);
  const items = [];
  $("tr.diary-entry-row").each((rowIndex, element) => {
    const $row = $(element);
    const baseFilm = filmFromContainer($, element, { watched: true });
    if (!baseFilm) return;
    const href = cleanString($row.find("a.daydate[href]").first().attr("href"), 500);
    const dateMatch = href.match(/\/for\/(\d{4})\/(\d{2})\/(\d{2})\/?$/);
    if (!dateMatch) return;
    const watchedDate = `${dateMatch[1]}-${dateMatch[2]}-${dateMatch[3]}`;
    const externalId = cleanString($row.attr("data-viewing-id"), 80);
    const reviewUri = cleanString($row.find(".col-review a[href]").first().attr("href"), 500);
    items.push({
      ...baseFilm,
      externalId,
      fallbackIdentity: externalId ? "" : sha256(
        `${baseFilm.key}|${watchedDate}|${reviewUri}|${rowIndex}`
      ),
      watchedDate,
      rating: ratingFromContainer($row),
      liked: $row.find(".col-like .icon-liked").length > 0,
      rewatch: $row.find(".col-rewatch.icon-status-on").length > 0,
      reviewUri,
    });
  });
  const unique = new Map();
  for (const item of items) {
    const identity = item.externalId || `${item.key}|${item.watchedDate}|${items.indexOf(item)}`;
    unique.set(identity, item);
  }
  const parsedItems = [...unique.values()];
  const emptyConfirmed = parsedItems.length === 0 && hasExplicitEmptyState($);
  const nextUrl = parseNextUrl($, username);
  const documentComplete = hasCompleteHtmlDocument(html);
  const pagination = paginationEvidence(
    $,
    nextUrl,
    parsedItems.length,
    50,
    emptyConfirmed,
    Math.max(0, Number(defaults.pageNumber) || 0),
    documentComplete
  );
  return {
    items: parsedItems,
    nextUrl,
    valid: documentComplete && pageBelongsToUser($, username) &&
      (parsedItems.length > 0 || emptyConfirmed),
    emptyConfirmed,
    lastPageConfirmed: pagination.lastPageConfirmed,
  };
}

function stableObject(value) {
  if (Array.isArray(value)) return value.map(stableObject);
  if (!value || typeof value !== "object") return value;
  return Object.keys(value)
    .sort()
    .reduce((result, key) => {
      result[key] = stableObject(value[key]);
      return result;
    }, {});
}

function checksum(value) {
  return sha256(JSON.stringify(stableObject(value)));
}

class LetterboxdHttpClient {
  constructor(username) {
    this.username = username;
    this.cookies = new Map();
  }

  _cookieHeader() {
    return [...this.cookies.entries()].map(([key, value]) => `${key}=${value}`).join("; ");
  }

  _captureCookies(headers) {
    const values = headers && headers["set-cookie"];
    if (!Array.isArray(values)) return;
    for (const value of values) {
      const pair = String(value).split(";", 1)[0];
      const index = pair.indexOf("=");
      if (index > 0) this.cookies.set(pair.slice(0, index), pair.slice(index + 1));
    }
  }

  async get(rawUrl, referer = `${LETTERBOXD_ORIGIN}/`, options = {}) {
    const url = safeProfileUrl(rawUrl, this.username);
    if (!url) {
      throw new LetterboxdSyncError("unsafe-url", "Güvenli olmayan Letterboxd adresi.", {
        permanent: true,
      });
    }

    const maxAttempts = Math.max(1, Math.min(4, Number(options.maxAttempts) || 4));
    let lastError;
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        const response = await axios.get(url, {
          timeout: 25000,
          maxContentLength: MAX_PAGE_BYTES,
          maxRedirects: 5,
          responseType: "text",
          validateStatus: () => true,
          headers: {
            "User-Agent": LETTERBOXD_USER_AGENT,
            Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
            "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
            Referer: referer,
            ...(this.cookies.size ? { Cookie: this._cookieHeader() } : {}),
          },
        });
        this._captureCookies(response.headers);
        const body = typeof response.data === "string" ? response.data : "";
        const responseUrl = cleanString(
          response.request && response.request.res && response.request.res.responseUrl,
          1000
        );
        const finalUrlIsSafe = !responseUrl ||
          Boolean(safeProfileUrl(responseUrl, this.username));
        const challenged =
          /<title>\s*Just a moment/i.test(body) ||
          body.includes("challenge-platform") ||
          body.includes("cf-chl-");
        if (response.status === 404) {
          throw new LetterboxdSyncError(
            "profile-not-found",
            "Letterboxd kullanıcısı bulunamadı.",
            { permanent: true }
          );
        }
        if (response.status === 200 && body && !challenged && finalUrlIsSafe) return body;
        if (response.status === 403 && options.allowForbidden === true) {
          throw new LetterboxdSyncError(
            "letterboxd-profile-blocked",
            "Letterboxd profil sayfasına sunucudan erişim engellendi.",
            { permanent: true }
          );
        }
        const retryable =
          challenged || response.status === 403 || response.status === 429 || response.status >= 500;
        if (!retryable) {
          throw new LetterboxdSyncError(
            "letterboxd-http",
            `Letterboxd HTTP ${response.status} yanıtı verdi.`,
            { permanent: response.status >= 400 && response.status < 500 }
          );
        }
        const retryAfter = Number(response.headers && response.headers["retry-after"]);
        const waitMs = Number.isFinite(retryAfter)
          ? Math.min(30000, Math.max(1000, retryAfter * 1000))
          : Math.min(12000, 900 * 2 ** attempt);
        await delay(waitMs);
        lastError = new Error(`Letterboxd HTTP ${response.status}`);
      } catch (error) {
        if (error instanceof LetterboxdSyncError) throw error;
        lastError = error;
        if (attempt < maxAttempts - 1) {
          await delay(Math.min(12000, 900 * 2 ** attempt));
        }
      }
    }
    throw new LetterboxdSyncError(
      "letterboxd-unavailable",
      "Letterboxd sayfasına şu anda ulaşılamıyor.",
      { cause: lastError }
    );
  }
}

function legacyDiaryId(movieKey) {
  return `letterboxd_${Buffer.from(movieKey, "utf8").toString("base64url")}`;
}

function diaryIdentity(entry) {
  if (entry.externalId) return `viewing:${entry.externalId}`;
  if (entry.fallbackIdentity) return `fallback:${entry.fallbackIdentity}`;
  return `${entry.key}|${entry.watchedDate}|${entry.reviewUri || ""}`;
}

function mergeFilmRecord(previous, incoming) {
  if (!previous) return { ...incoming };
  return {
    ...previous,
    ...incoming,
    title: incoming.title || previous.title,
    year: incoming.year || previous.year,
    rating: incoming.rating ?? previous.rating,
    liked: previous.liked || incoming.liked,
    watched: previous.watched || incoming.watched,
    inWatchlist: previous.inWatchlist || incoming.inWatchlist,
    favorite: previous.favorite || incoming.favorite,
  };
}

function createLetterboxdSync({ resolveCatalogFilms }) {
  if (typeof resolveCatalogFilms !== "function") {
    throw new Error("resolveCatalogFilms dependency is required");
  }
  const db = admin.firestore();

  function bucket() {
    const projectId = cleanString(
      process.env.GCLOUD_PROJECT || admin.app().options.projectId,
      120
    );
    if (!projectId) throw new Error("firebase-project-id-unavailable");
    return admin.storage().bucket(`${projectId}.firebasestorage.app`);
  }

  function integrationRef(uid) {
    return db.collection("users").doc(uid).collection("integrations").doc(PROVIDER);
  }

  function jobRef(uid, jobId) {
    return db.collection("users").doc(uid).collection("integrationJobs").doc(jobId);
  }

  function jobPrefix(uid, jobId) {
    return `letterboxd_jobs/${uid}/${jobId}/`;
  }

  function manifestPath(uid) {
    return `letterboxd_manifests/${uid}.json.gz`;
  }

  async function readGzipJson(path, fallback) {
    try {
      const [buffer] = await bucket().file(path).download();
      if (buffer.length > MAX_COMPRESSED_SNAPSHOT_BYTES) {
        throw new LetterboxdSyncError(
          "snapshot-too-large",
          "Letterboxd senkronizasyon dosyası güvenli boyut sınırını aştı.",
          { permanent: true }
        );
      }
      const uncompressed = zlib.gunzipSync(buffer, {
        maxOutputLength: MAX_UNCOMPRESSED_SNAPSHOT_BYTES,
      });
      return JSON.parse(uncompressed.toString("utf8"));
    } catch (error) {
      if (error && error.code === 404) return fallback;
      if (/No such object|not found/i.test(String(error && error.message))) return fallback;
      throw error;
    }
  }

  async function writeGzipJson(path, value) {
    const data = zlib.gzipSync(Buffer.from(JSON.stringify(value), "utf8"), { level: 9 });
    if (data.length > MAX_COMPRESSED_SNAPSHOT_BYTES) {
      throw new LetterboxdSyncError(
        "snapshot-too-large",
        "Letterboxd senkronizasyon dosyası güvenli boyut sınırını aştı.",
        { permanent: true }
      );
    }
    await bucket().file(path).save(data, {
      resumable: false,
      validation: "crc32c",
      contentType: "application/gzip",
      metadata: { cacheControl: "no-store" },
    });
  }

  function chunkPath(uid, jobId, phase, pageStart) {
    const cursor = String(Math.max(0, Number(pageStart) || 0)).padStart(6, "0");
    return `${jobPrefix(uid, jobId)}${phase}/chunk-${cursor}.json.gz`;
  }

  async function readPagedSnapshot(active, phase, maxItems) {
    const prefix = `${jobPrefix(active.uid, active.jobId)}${phase}/chunk-`;
    const [files] = await bucket().getFiles({ prefix });
    const ordered = files
      .filter((file) => /\/chunk-\d{6}\.json\.gz$/.test(file.name))
      .sort((left, right) => left.name.localeCompare(right.name));
    if (!ordered.length) return null;

    const byIdentity = new Map();
    let expectedPage = 0;
    let complete = false;
    for (const file of ordered) {
      if (complete) {
        throw new LetterboxdSyncError("invalid-snapshot", "Fazladan Letterboxd parçası bulundu.");
      }
      const chunk = await readGzipJson(file.name, null);
      const rawStartPage = Number(chunk && chunk.startPage);
      const rawEndPage = Number(chunk && chunk.endPage);
      const startPage = Number.isInteger(rawStartPage) ? rawStartPage : -1;
      const endPage = Number.isInteger(rawEndPage) ? rawEndPage : -1;
      if (!chunk || startPage < 0 || startPage !== expectedPage || endPage <= startPage ||
          endPage > MAX_PAGES_PER_PHASE ||
          endPage - startPage > PAGES_PER_TASK || !Array.isArray(chunk.items)) {
        throw new LetterboxdSyncError(
          "invalid-snapshot",
          "Letterboxd parçaları sıralı ve eksiksiz değil."
        );
      }
      for (const item of chunk.items) {
        const identity = phase === "diary" ? diaryIdentity(item) : item && item.key;
        if (!identity) continue;
        if (phase === "diary") byIdentity.set(identity, item);
        else byIdentity.set(identity, mergeFilmRecord(byIdentity.get(identity), item));
      }
      if (byIdentity.size > maxItems) {
        throw new LetterboxdSyncError("too-many-items", "Letterboxd kayıt sınırı aşıldı.", {
          permanent: true,
        });
      }
      complete = chunk.complete === true;
      const nextUrl = cleanString(chunk.nextUrl, 1000);
      if ((complete && nextUrl) || (!complete && !nextUrl)) {
        throw new LetterboxdSyncError(
          "invalid-snapshot",
          "Letterboxd parçasının devam bilgisi geçersiz."
        );
      }
      expectedPage = endPage;
    }
    if (!complete) {
      throw new LetterboxdSyncError("partial-snapshot", "Letterboxd aktarımı eksik kaldı.");
    }
    return { items: [...byIdentity.values()], pages: expectedPage, complete: true };
  }

  async function enqueue(data, idSeed, delaySeconds = 0) {
    const queue = getFunctions().taskQueue(TASK_FUNCTION_NAME);
    let lastError;
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        await queue.enqueue(data, {
          id: taskId(idSeed),
          dispatchDeadlineSeconds: 1800,
          ...(delaySeconds > 0 ? { scheduleDelaySeconds: delaySeconds } : {}),
        });
        return;
      } catch (error) {
        const code = cleanString(error && error.code, 100);
        if (code.includes("task-already-exists") || code.includes("already-exists")) return;
        lastError = error;
        if (attempt < 3) await delay(300 * 2 ** attempt);
      }
    }
    throw lastError || new Error("letterboxd-task-enqueue-failed");
  }

  function nextTaskData(active, phase, extra = {}) {
    return {
      uid: active.uid,
      jobId: active.jobId,
      generation: active.generation,
      phase,
      ...extra,
    };
  }

  async function enqueueNextTask(active, task, delaySeconds = 2) {
    if (!task || task.uid !== active.uid || task.jobId !== active.jobId ||
        positiveInteger(task.generation) !== active.generation ||
        phaseRank(task.phase) < 0) {
      return false;
    }
    const cursor = task.phase === "hydrate"
      ? Math.max(0, Number(task.chunk) || 0)
      : Math.max(0, Number(task.page) || 0);
    await enqueue(task, [active.uid, active.jobId, task.phase, String(cursor)], delaySeconds);
    return true;
  }

  async function ensureStoredContinuation(active) {
    // active.jobData task başındaki snapshot'tır ve başka bir delivery aşamayı
    // ilerletmiş olabilir. Yalnız güncel continuation yeniden kuyruğa alınır.
    const latest = await jobRef(active.uid, active.jobId).get();
    const task = latest.exists ? (latest.data() || {}).nextTask : null;
    return enqueueNextTask(active, task);
  }

  async function recoverReusedContinuation(uid, jobId, generation) {
    if (!uid || !jobId || !positiveInteger(generation)) return false;
    const snapshot = await jobRef(uid, jobId).get();
    if (!snapshot.exists) return false;
    const data = snapshot.data() || {};
    if (positiveInteger(data.generation) !== generation) return false;
    const task = data.nextTask;
    if (!task || typeof task !== "object" || task.uid !== uid || task.jobId !== jobId ||
        positiveInteger(task.generation) !== generation || phaseRank(task.phase) < 0) {
      return false;
    }
    const claim = data.taskClaim && typeof data.taskClaim === "object"
      ? data.taskClaim
      : {};
    if (timestampMillis(claim.expiresAt) > Date.now()) return true;
    const cursor = task.phase === "hydrate"
      ? Math.max(0, Number(task.chunk) || 0)
      : Math.max(0, Number(task.page) || 0);
    await enqueue(
      task,
      [uid, jobId, "callable-recovery", task.phase, String(cursor),
        String(Math.max(0, Number(data.taskClaimEpoch) || 0))],
      2
    );
    return true;
  }

  async function requestSync(request) {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");
    const username = normalizeUsername(request.data && request.data.username);
    if (!username) {
      throw new HttpsError("invalid-argument", "Letterboxd kullanıcı adı geçersiz.");
    }
    const source = cleanString(request.data && request.data.source, 50) || "manual";
    const clientFavorites = normalizeClientFavorites(
      request.data && request.data.favorites
    );
    const now = Date.now();
    const integration = integrationRef(uid);
    const userRef = db.collection("users").doc(uid);
    const obsoleteJobIds = new Set();
    let response;

    await db.runTransaction(async (transaction) => {
      const [current, user] = await Promise.all([
        transaction.get(integration),
        transaction.get(userRef),
      ]);
      const userData = user.exists ? user.data() || {} : {};
      if (!isActiveProfile(userData)) {
        throw new HttpsError(
          "failed-precondition",
          "Letterboxd senkronizasyonu için aktif bir profil gerekiyor."
        );
      }
      // Eski uygulama sürümünün cache'inde kalmış kullanıcı adı, kullanıcı
      // bağlantıyı kaldırdıktan sonra hesabı yeniden bağlayamamalı. Lazy
      // migration yalnız sunucudaki canonical ad hâlâ aynıysa ve yeni Diary
      // şeması henüz oluşmadıysa geçerlidir.
      if (source === "lazy_diary_migration") {
        const canonicalUsername = normalizeUsername(userData.letterboxdUsername);
        const diarySchemaVersion = Math.max(0, Number(userData.diarySchemaVersion) || 0);
        if (canonicalUsername !== username || diarySchemaVersion >= SCHEMA_VERSION) {
          response = { ok: true, status: "not-needed", reused: true };
          return;
        }
      }
      const data = current.exists ? current.data() || {} : {};
      const leaseActive = timestampMillis(data.leaseExpiresAt) > now;
      if (data.status === "disconnecting") {
        throw new HttpsError(
          "failed-precondition",
          "Letterboxd bağlantısı kaldırılıyor. İşlem tamamlanınca tekrar deneyin."
        );
      }
      if (leaseActive && data.activeJobId) {
        if (normalizeUsername(data.pendingUsername || data.username) !== username) {
          throw new HttpsError(
            "failed-precondition",
            "Başka bir Letterboxd hesabının senkronizasyonu devam ediyor."
          );
        }
        response = {
          ok: true,
          status: data.status,
          jobId: data.activeJobId,
          generation: positiveInteger(data.generation),
          reused: true,
        };
        return;
      }
      const lastRequestAt = timestampMillis(data.requestedAt);
      if (data.status === "success" && data.username === username &&
          lastRequestAt > 0 && now - lastRequestAt < 10 * 60 * 1000) {
        response = {
          ok: true,
          status: "current",
          reused: true,
          cooldownSeconds: Math.ceil((10 * 60 * 1000 - (now - lastRequestAt)) / 1000),
        };
        return;
      }
      if (lastRequestAt > 0 && now - lastRequestAt < MIN_NEW_JOB_INTERVAL_MS) {
        throw new HttpsError(
          "resource-exhausted",
          "Yeni bir senkronizasyon başlatmadan önce kısa bir süre bekleyin."
        );
      }

      const quotaWindowStartedAt = timestampMillis(data.quotaWindowStartedAt);
      const quotaWindowActive = quotaWindowStartedAt > 0 &&
        now - quotaWindowStartedAt < SYNC_QUOTA_WINDOW_MS;
      const quotaCount = quotaWindowActive
        ? Math.max(0, Number(data.quotaCount) || 0)
        : 0;
      if (quotaCount >= SYNC_QUOTA_PER_WINDOW) {
        throw new HttpsError(
          "resource-exhausted",
          "Günlük Letterboxd senkronizasyon sınırına ulaşıldı."
        );
      }

      const generation = (positiveInteger(data.generation) || 0) + 1;
      const job = jobRef(uid, db.collection("_ids").doc().id);
      const initialTask = {
        uid,
        jobId: job.id,
        generation,
        phase: "profile",
      };
      const serverTime = admin.firestore.FieldValue.serverTimestamp();
      const previousJobId = cleanString(data.lastJobId, 128);
      const staleActiveJobId = cleanString(data.activeJobId, 128);
      if (previousJobId && previousJobId !== job.id) {
        obsoleteJobIds.add(previousJobId);
        transaction.delete(jobRef(uid, previousJobId));
      }
      if (staleActiveJobId && staleActiveJobId !== previousJobId &&
          staleActiveJobId !== job.id) {
        obsoleteJobIds.add(staleActiveJobId);
        transaction.delete(jobRef(uid, staleActiveJobId));
      }
      transaction.set(integration, {
        provider: PROVIDER,
        schemaVersion: SCHEMA_VERSION,
        pendingUsername: username,
        status: "queued",
        source,
        generation,
        activeJobId: job.id,
        requestedAt: serverTime,
        updatedAt: serverTime,
        quotaWindowStartedAt: quotaWindowActive
          ? data.quotaWindowStartedAt
          : serverTime,
        quotaCount: quotaCount + 1,
        leaseExpiresAt: admin.firestore.Timestamp.fromMillis(now + 35 * 60 * 1000),
        error: admin.firestore.FieldValue.delete(),
      }, { merge: true });
      transaction.set(job, {
        provider: PROVIDER,
        schemaVersion: SCHEMA_VERSION,
        username,
        generation,
        status: "queued",
        phase: "profile",
        nextTask: initialTask,
        source,
        ...(clientFavorites.length ? { clientFavorites } : {}),
        requestedAt: serverTime,
        updatedAt: serverTime,
      });
      response = { ok: true, status: "queued", jobId: job.id, generation };
    });

    if (response.reused && response.status !== "queued") {
      if (response.jobId) {
        await recoverReusedContinuation(
          uid,
          response.jobId,
          positiveInteger(response.generation)
        ).catch(() => {});
      }
      return response;
    }
    try {
      await enqueue(
        { uid, jobId: response.jobId, generation: response.generation, phase: "profile" },
        [uid, response.jobId, "profile", "0"]
      );
      if (obsoleteJobIds.size) {
        await Promise.all([...obsoleteJobIds].map((obsoleteJobId) =>
          bucket().deleteFiles({ prefix: jobPrefix(uid, obsoleteJobId) }).catch(() => {})
        ));
      }
      return response;
    } catch (error) {
      // CreateTask başarılı olup yanıt ağda kaybolmuş olabilir. Deterministik
      // task ID + retry bu belirsizliği çoğunlukla çözer; yine de queue tamamen
      // erişilemiyorsa ortak job'u failed yapma. Aynı callable tekrarlandığında
      // canlı queued job reuse edilip outbox yeniden enqueue edilir.
      await jobRef(uid, response.jobId).set({
        queueErrorCode: "queue-unavailable",
        queueErrorAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true }).catch(() => {});
      throw new HttpsError("unavailable", "Senkronizasyon kuyruğu başlatılamadı.");
    }
  }

  async function activeJob(data, { allowCompleted = false } = {}) {
    const uid = cleanString(data && data.uid, 128);
    const jobId = cleanString(data && data.jobId, 128);
    const generation = positiveInteger(data && data.generation);
    if (!uid || !jobId || !generation) return null;
    const [integration, job] = await db.getAll(integrationRef(uid), jobRef(uid, jobId));
    if (!integration.exists || !job.exists) return null;
    const integrationData = integration.data() || {};
    const jobData = job.data() || {};
    if (positiveInteger(integrationData.generation) !== generation ||
        positiveInteger(jobData.generation) !== generation) return null;
    if (!allowCompleted && integrationData.activeJobId !== jobId) return null;
    if (["cancelled", "disconnected", "failed"].includes(jobData.status)) return null;
    return { uid, jobId, generation, integrationData, jobData };
  }

  function supersededError() {
    return new LetterboxdSyncError(
      "superseded",
      "Bu senkronizasyon daha yeni bir işlem tarafından geçersiz kılındı.",
      { permanent: true }
    );
  }

  function taskClaimLostError() {
    return new LetterboxdSyncError(
      "task-claim-lost",
      "Bu görev aynı aşamanın daha güncel çalıştırmasına devredildi.",
      { permanent: true }
    );
  }

  function taskClaimKey(phase, cursorField, cursor) {
    return `${phase}:${cursorField ? Math.max(0, Number(cursor) || 0) : 0}`;
  }

  function ownsTaskClaim(active, jobData, phase, cursorField = "", cursor = 0) {
    const claim = jobData && typeof jobData.taskClaim === "object"
      ? jobData.taskClaim
      : {};
    return Boolean(active.invocationId) &&
      claim.owner === active.invocationId &&
      claim.key === taskClaimKey(phase, cursorField, cursor) &&
      (!active.taskClaim ||
        Math.max(0, Number(claim.epoch) || 0) === active.taskClaim.epoch);
  }

  function integrationMatches(active, data) {
    return positiveInteger(data && data.generation) === active.generation &&
      data.activeJobId === active.jobId;
  }

  function phaseRank(value) {
    const phase = cleanString(value, 30);
    return Object.prototype.hasOwnProperty.call(PHASE_ORDER, phase)
      ? PHASE_ORDER[phase]
      : -1;
  }

  async function assertStillActive(active) {
    const snapshot = await integrationRef(active.uid).get();
    if (!snapshot.exists || !integrationMatches(active, snapshot.data() || {})) {
      throw supersededError();
    }
    return snapshot.data() || {};
  }

  async function claimTask(
    active,
    phase,
    { cursorField = "", cursor = 0, extra = {}, integrationExtra = {} } = {}
  ) {
    const now = Date.now();
    const outcome = await db.runTransaction(async (transaction) => {
      const integration = integrationRef(active.uid);
      const job = jobRef(active.uid, active.jobId);
      const [current, currentJob] = await Promise.all([
        transaction.get(integration),
        transaction.get(job),
      ]);
      if (!current.exists || !integrationMatches(active, current.data() || {})) {
        throw supersededError();
      }
      if (!currentJob.exists) throw supersededError();
      const jobData = currentJob.data() || {};
      if (jobData.projectionCommitted === true && phase !== "hydrate") return false;
      const currentRank = phaseRank(jobData.phase);
      const requestedRank = phaseRank(phase);
      if (requestedRank < 0) {
        throw new LetterboxdSyncError("invalid-phase", "Geçersiz senkronizasyon aşaması.", {
          permanent: true,
        });
      }
      if (currentRank > requestedRank) return false;
      if (currentRank !== requestedRank) {
        throw new LetterboxdSyncError(
          "phase-not-ready",
          "Senkronizasyon aşaması henüz hazır değil."
        );
      }
      if (cursorField) {
        const expectedCursor = Math.max(0, Number(jobData[cursorField]) || 0);
        if (cursor < expectedCursor) return false;
        if (cursor > expectedCursor) {
          throw new LetterboxdSyncError(
            "cursor-not-ready",
            "Senkronizasyon sayfası henüz hazır değil."
          );
        }
      }
      const claimKey = taskClaimKey(phase, cursorField, cursor);
      const existingClaim = jobData.taskClaim && typeof jobData.taskClaim === "object"
        ? jobData.taskClaim
        : {};
      if (timestampMillis(existingClaim.expiresAt) > now &&
          existingClaim.owner !== active.invocationId) {
        return {
          state: "busy",
          key: cleanString(existingClaim.key, 100) || claimKey,
          epoch: Math.max(0, Number(existingClaim.epoch) || 0),
          expiresAt: timestampMillis(existingClaim.expiresAt),
        };
      }
      // Epoch claim alanından ayrı tutulur; transient release taskClaim'i silse
      // bile eski watchdog kimliği yeniden kullanılmaz.
      const epoch = Math.max(0, Number(jobData.taskClaimEpoch) || 0) + 1;
      transaction.set(job, {
        status: "running",
        phase,
        taskClaim: {
          key: claimKey,
          owner: active.invocationId,
          epoch,
          phase,
          cursor: cursorField ? Math.max(0, Number(cursor) || 0) : 0,
          expiresAt: admin.firestore.Timestamp.fromMillis(now + TASK_CLAIM_TTL_MS),
        },
        taskClaimEpoch: epoch,
        ...extra,
        queueErrorCode: admin.firestore.FieldValue.delete(),
        queueErrorAt: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      transaction.set(integration, {
        status: "running",
        phase,
        ...integrationExtra,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        leaseExpiresAt: admin.firestore.Timestamp.fromMillis(now + 35 * 60 * 1000),
      }, { merge: true });
      return { state: "claimed", key: claimKey, epoch };
    });
    if (outcome && outcome.state === "busy") {
      // Cloud Tasks retry'ları 31 dakikalık lease dolmadan tükenebilir. Her
      // claim epoch'u için deterministik bir watchdog, owner hard-crash ederse
      // aynı task'ı lease sonrasında yeniden çalıştırır.
      const delaySeconds = Math.max(
        5,
        Math.ceil((outcome.expiresAt - Date.now()) / 1000) + 30
      );
      await enqueue(
        active.taskData,
        [active.uid, active.jobId, "lease-recovery", outcome.key, String(outcome.epoch)],
        delaySeconds
      );
      return false;
    }
    if (!outcome || outcome.state !== "claimed") return false;
    active.taskClaim = { key: outcome.key, epoch: outcome.epoch };
    // Son queue attempt'i claim aldıktan sonra hard-crash olursa onu görecek
    // başka retry kalmaz. Yalnız bu nadir durumda proaktif watchdog kurarak
    // normal senkronlarda ek task/read maliyetinden kaçın.
    if (Math.max(0, Number(active.retryCount) || 0) >= 4) {
      await enqueue(
        active.taskData,
        [active.uid, active.jobId, "lease-recovery", outcome.key, String(outcome.epoch)],
        Math.ceil(TASK_CLAIM_TTL_MS / 1000) + 30
      );
    }
    return true;
  }

  async function touchJob(active, phase, extra = {}) {
    const now = Date.now();
    return db.runTransaction(async (transaction) => {
      const integration = integrationRef(active.uid);
      const job = jobRef(active.uid, active.jobId);
      const [current, currentJob] = await Promise.all([
        transaction.get(integration),
        transaction.get(job),
      ]);
      if (!current.exists || !integrationMatches(active, current.data() || {}) ||
          !currentJob.exists) {
        throw supersededError();
      }
      const jobData = currentJob.data() || {};
      if (!ownsTaskClaim(active, jobData, active.taskData.phase,
        active.taskData.phase === "hydrate" ? "hydrateChunk" :
          (["films", "diary", "watchlist"].includes(active.taskData.phase)
            ? `${active.taskData.phase}Page`
            : ""),
        active.taskData.phase === "hydrate"
          ? active.taskData.chunk
          : active.taskData.page)) {
        throw taskClaimLostError();
      }
      if (jobData.projectionCommitted === true && phase !== "hydrate") return false;
      const currentRank = phaseRank(jobData.phase);
      const targetRank = phaseRank(phase);
      if (targetRank < currentRank) return false;
      if (targetRank < 0 || targetRank > currentRank + 1) {
        throw new LetterboxdSyncError("invalid-phase-transition", "Geçersiz aşama geçişi.");
      }
      for (const [key, value] of Object.entries(extra)) {
        if (!/(Page|Chunk)$/.test(key)) continue;
        const nextValue = Number(value);
        const oldValue = Number(jobData[key]);
        if (Number.isFinite(nextValue) && Number.isFinite(oldValue) && nextValue < oldValue) {
          return false;
        }
      }
      transaction.set(job, {
        status: "running",
        phase,
        taskClaim: admin.firestore.FieldValue.delete(),
        ...extra,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      transaction.set(integration, {
        status: "running",
        phase,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        leaseExpiresAt: admin.firestore.Timestamp.fromMillis(now + 35 * 60 * 1000),
      }, { merge: true });
      return true;
    });
  }

  async function releaseTaskClaim(active) {
    if (!active || !active.invocationId) return;
    const reference = jobRef(active.uid, active.jobId);
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) return;
      const data = snapshot.data() || {};
      const claim = data.taskClaim && typeof data.taskClaim === "object"
        ? data.taskClaim
        : {};
      if (claim.owner !== active.invocationId) return;
      transaction.set(reference, {
        taskClaim: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });
  }

  async function processProfile(active) {
    const claimed = await claimTask(active, "profile", {
      extra: { startedAt: admin.firestore.FieldValue.serverTimestamp() },
    });
    if (!claimed) {
      await ensureStoredContinuation(active);
      return;
    }
    const username = normalizeUsername(active.jobData.username);
    const client = new LetterboxdHttpClient(username);
    const profileUrl = `${LETTERBOXD_ORIGIN}/${username}/`;
    const clientFavorites = normalizeClientFavorites(active.jobData.clientFavorites);
    let favoritesSnapshot = clientFavorites.length
      ? { items: clientFavorites, complete: true, source: "client" }
      : null;
    if (!favoritesSnapshot) {
      try {
        const html = await client.get(profileUrl, `${LETTERBOXD_ORIGIN}/`, {
          maxAttempts: 1,
          allowForbidden: true,
        });
        const parsed = parseProfilePage(html, username);
        if (!parsed.looksValid || !parsed.favoritesKnown) {
          throw new LetterboxdSyncError(
            parsed.looksValid ? "unexpected-markup" : "profile-not-found",
            parsed.looksValid
              ? "Letterboxd profil yapısı güvenli biçimde okunamadı."
              : "Letterboxd profili doğrulanamadı.",
            { permanent: true }
          );
        }
        favoritesSnapshot = { items: parsed.favorites, complete: true };
      } catch (error) {
        if (!(error instanceof LetterboxdSyncError) ||
            error.code !== "letterboxd-profile-blocked") {
          throw error;
        }
        // Letterboxd, Cloud Run çıkışlarını yalnızca profil kökünde zaman zaman
        // 403 ile engelliyor. Filmler/diary/watchlist sayfaları çalışmaya devam
        // ettiğinden bütün aktarımı durdurma; mevcut hesabın favorilerini finalize
        // aşamasında koru.
        favoritesSnapshot = { items: [], complete: true, unavailable: true };
      }
    }
    await writeGzipJson(
      `${jobPrefix(active.uid, active.jobId)}favorites.json.gz`,
      favoritesSnapshot
    );
    const nextTask = nextTaskData(active, "films", {
      url: `${LETTERBOXD_ORIGIN}/${username}/films/`,
      page: 0,
    });
    await touchJob(active, "films", {
      profileComplete: true,
      favoritesUnavailable: favoritesSnapshot.unavailable === true,
      filmsPage: 0,
      nextTask,
    });
    await enqueueNextTask(active, nextTask);
  }

  async function processPagedPhase(active, phase, parser, defaults, nextPhase, firstNextUrl) {
    const username = normalizeUsername(active.jobData.username);
    const requestedUrl = safeProfileUrl(active.taskData.url, username);
    if (!requestedUrl) {
      throw new LetterboxdSyncError("unsafe-url", "Geçersiz sayfalama adresi.", {
        permanent: true,
      });
    }
    const pageStart = Math.max(0, Number(active.taskData.page) || 0);
    if (pageStart >= MAX_PAGES_PER_PHASE) {
      throw new LetterboxdSyncError("too-many-pages", "Letterboxd sayfa sınırı aşıldı.", {
        permanent: true,
      });
    }
    const claimed = await claimTask(active, phase, {
      cursorField: `${phase}Page`,
      cursor: pageStart,
      extra: { [`${phase}Page`]: pageStart },
    });
    if (!claimed) {
      await ensureStoredContinuation(active);
      return;
    }
    const byIdentity = new Map();

    const client = new LetterboxdHttpClient(username);
    let url = requestedUrl;
    let page = pageStart;
    let nextUrl = "";
    for (let processed = 0; processed < PAGES_PER_TASK; processed++) {
      const html = await client.get(url, processed === 0 ? `${LETTERBOXD_ORIGIN}/${username}/` : url);
      const parsed = parser(html, username, { ...defaults, pageNumber: page });
      if (!parsed || parsed.valid !== true) {
        throw new LetterboxdSyncError(
          "unexpected-markup",
          `Letterboxd ${phase} sayfası güvenli biçimde okunamadı.`,
          { permanent: true }
        );
      }
      for (const item of parsed.items) {
        const identity = phase === "diary" ? diaryIdentity(item) : item.key;
        if (!identity) continue;
        if (phase === "diary") byIdentity.set(identity, item);
        else byIdentity.set(identity, mergeFilmRecord(byIdentity.get(identity), item));
      }
      page += 1;
      nextUrl = parsed.nextUrl;
      if (!nextUrl && parsed.lastPageConfirmed !== true) {
        throw new LetterboxdSyncError(
          "pagination-unconfirmed",
          `Letterboxd ${phase} sayfasının son sayfa olduğu doğrulanamadı.`,
          { permanent: true }
        );
      }
      if (!nextUrl) break;
      if (page >= MAX_PAGES_PER_PHASE) {
        throw new LetterboxdSyncError("too-many-pages", "Letterboxd sayfa sınırı aşıldı.", {
          permanent: true,
        });
      }
      url = nextUrl;
      await delay(350 + Math.floor(Math.random() * 180));
    }

    await writeGzipJson(chunkPath(active.uid, active.jobId, phase, pageStart), {
      startPage: pageStart,
      endPage: page,
      items: [...byIdentity.values()],
      complete: !nextUrl,
      nextUrl,
    });

    if (nextUrl) {
      const nextTask = nextTaskData(active, phase, { url: nextUrl, page });
      await touchJob(active, phase, {
        [`${phase}Page`]: page,
        nextTask,
      });
      await enqueueNextTask(active, nextTask);
      return;
    }

    const nextData = nextTaskData(active, nextPhase);
    if (firstNextUrl) {
      nextData.url = `${LETTERBOXD_ORIGIN}/${username}/${firstNextUrl}`;
      nextData.page = 0;
    }
    await touchJob(active, nextPhase, {
      [`${phase}Complete`]: true,
      [`${phase}Pages`]: page,
      nextTask: nextData,
      ...(firstNextUrl ? {
        [`${nextPhase}Page`]: 0,
      } : {}),
    });
    await enqueueNextTask(active, nextData);
  }

  function normalizedLibrary(films, favorites, watchlist) {
    const byKey = new Map();
    for (const film of films) byKey.set(film.key, mergeFilmRecord(byKey.get(film.key), film));
    for (const film of favorites) {
      byKey.set(film.key, mergeFilmRecord(byKey.get(film.key), {
        ...film,
        watched: true,
        favorite: true,
      }));
    }
    for (const film of watchlist) {
      byKey.set(film.key, mergeFilmRecord(byKey.get(film.key), {
        ...film,
        inWatchlist: true,
      }));
    }
    return [...byKey.values()]
      .filter((film) => film.key && film.title && film.uri)
      .map((film) => ({
        key: film.key,
        uri: film.uri,
        title: cleanString(film.title, 180),
        year: normalizeYear(film.year),
        rating: normalizeRating(film.rating),
        liked: film.liked === true,
        watched: film.watched === true,
        inWatchlist: film.inWatchlist === true,
        favorite: film.favorite === true,
        letterboxdId: positiveInteger(film.letterboxdId),
        letterboxdLid: cleanString(film.letterboxdLid, 40),
      }))
      .sort((a, b) => a.key.localeCompare(b.key));
  }

  function preservedProviderFavoriteKeys(userData, username) {
    if (normalizeUsername(userData && userData.letterboxdUsername) !== username) {
      return new Set();
    }
    const sources = userData && userData.filmSources &&
      typeof userData.filmSources === "object" ? userData.filmSources : {};
    const keys = new Set();
    const favoritesKeys = Array.isArray(userData && userData.favoritesKeys)
      ? userData.favoritesKeys
      : [];
    for (const rawKey of favoritesKeys) {
      const key = cleanString(String(rawKey), 180);
      if (key && sources[key] === PROVIDER) keys.add(key);
    }
    const favorites = Array.isArray(userData && userData.favorites)
      ? userData.favorites
      : [];
    for (const favorite of favorites) {
      if (!favorite || typeof favorite !== "object" || favorite.source !== PROVIDER) continue;
      const key = cleanString(favorite.key, 180);
      if (key) keys.add(key);
    }
    return keys;
  }

  function normalizedDiary(entries) {
    return entries
      .filter((entry) =>
        entry && entry.key && entry.title && /^\d{4}-\d{2}-\d{2}$/.test(entry.watchedDate)
      )
      .map((entry) => ({
        key: entry.key,
        uri: entry.uri,
        title: cleanString(entry.title, 180),
        year: normalizeYear(entry.year),
        watchedDate: entry.watchedDate,
        rating: normalizeRating(entry.rating),
        liked: entry.liked === true,
        rewatch: entry.rewatch === true,
        externalId: cleanString(entry.externalId, 80),
        fallbackIdentity: cleanString(entry.fallbackIdentity, 64),
        reviewUri: cleanString(entry.reviewUri, 500),
        letterboxdId: positiveInteger(entry.letterboxdId),
        letterboxdLid: cleanString(entry.letterboxdLid, 40),
      }))
      .sort((a, b) => {
        const date = b.watchedDate.localeCompare(a.watchedDate);
        return date || b.externalId.localeCompare(a.externalId);
      });
  }

  function buildDiaryRecords(entries) {
    return entries.map((entry) => ({
      id: `lb2_${sha256(diaryIdentity(entry)).slice(0, 40)}`,
      ...entry,
    }));
  }

  function libraryPriority(film, recentKeys) {
    if (recentKeys.has(film.key)) return 0;
    if (film.favorite) return 1;
    if (film.rating === 5 || (film.rating !== null && film.rating <= 1)) return 2;
    if (film.inWatchlist) return 3;
    if (film.liked || film.rating !== null) return 4;
    return 5;
  }

  function manifestEntry(value) {
    if (typeof value === "string") {
      return { checksum: value, catalogSignature: "", autoResolve: false };
    }
    return value && typeof value === "object"
      ? value
      : { checksum: "", catalogSignature: "", autoResolve: false };
  }

  function validManifest(value) {
    if (!value || value.schemaVersion !== SCHEMA_VERSION ||
        typeof value.snapshotChecksum !== "string" || !value.snapshotChecksum ||
        !value.library || typeof value.library !== "object" ||
        !value.diary || typeof value.diary !== "object") {
      return false;
    }
    return Number(value.libraryCount) === Object.keys(value.library).length &&
      Number(value.diaryCount) === Object.keys(value.diary).length;
  }

  async function writeBulk(operations) {
    if (!operations.length) return;
    const writer = db.bulkWriter();
    writer.onWriteError((error) => error.failedAttempts < 5);
    for (let start = 0; start < operations.length; start += BULK_WRITE_CHUNK_SIZE) {
      for (const operation of operations.slice(start, start + BULK_WRITE_CHUNK_SIZE)) {
        if (operation.type === "delete") writer.delete(operation.ref);
        else if (operation.options && operation.options.merge === false) {
          writer.set(operation.ref, operation.data);
        } else {
          writer.set(operation.ref, operation.data, operation.options || { merge: true });
        }
      }
      await writer.flush();
    }
    await writer.close();
  }

  async function deleteQueryInBatches(query) {
    let deleted = 0;
    while (true) {
      const snapshot = await query.limit(BULK_WRITE_CHUNK_SIZE).get();
      if (snapshot.empty) return deleted;
      await writeBulk(snapshot.docs.map((document) => ({
        type: "delete",
        ref: document.ref,
      })));
      deleted += snapshot.size;
      if (snapshot.size < BULK_WRITE_CHUNK_SIZE) return deleted;
    }
  }

  async function deleteProviderDocsMissing(active, collectionRef, allowedIds) {
    let cursor = null;
    let deleted = 0;
    while (true) {
      let query = collectionRef
        .where("source", "==", PROVIDER)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(BULK_WRITE_CHUNK_SIZE);
      if (cursor) query = query.startAfter(cursor);
      const snapshot = await query.get();
      if (snapshot.empty) return deleted;
      const operations = snapshot.docs
        .filter((document) => !Object.prototype.hasOwnProperty.call(allowedIds, document.id))
        .map((document) => ({ type: "delete", ref: document.ref }));
      if (operations.length) {
        await assertStillActive(active);
        await writeBulk(operations);
        deleted += operations.length;
      }
      cursor = snapshot.docs[snapshot.docs.length - 1];
      if (snapshot.size < BULK_WRITE_CHUNK_SIZE) return deleted;
    }
  }

  async function writeDiaryCatalogUpdates(active, diaryRef, keys, resolvedByKey) {
    let cursor = null;
    while (true) {
      let query = diaryRef
        .where("movieKey", "in", keys)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(BULK_WRITE_CHUNK_SIZE);
      if (cursor) query = query.startAfter(cursor);
      const snapshot = await query.get();
      if (snapshot.empty) return;
      const operations = [];
      for (const document of snapshot.docs) {
        const resolved = resolvedByKey.get(cleanString(document.data().movieKey, 180));
        if (!resolved) continue;
        operations.push({
          type: "set",
          ref: document.ref,
          data: {
            tmdbId: positiveInteger(resolved.tmdbId),
            posterUrl: cleanString(resolved.posterUrl, 1200),
          },
          options: { merge: true },
        });
      }
      if (operations.length) {
        await assertStillActive(active);
        await writeBulk(operations);
      }
      cursor = snapshot.docs[snapshot.docs.length - 1];
      if (snapshot.size < BULK_WRITE_CHUNK_SIZE) return;
    }
  }

  async function deleteNestedProviderLibrary(libraryRef) {
    let cursor = null;
    while (true) {
      let query = libraryRef
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(BULK_WRITE_CHUNK_SIZE);
      if (cursor) query = query.startAfter(cursor);
      const snapshot = await query.get();
      if (snapshot.empty) return;
      const operations = [];
      for (const document of snapshot.docs) {
        const data = document.data() || {};
        if (data.source === PROVIDER ||
            (data.letterboxd && typeof data.letterboxd === "object")) {
          operations.push({ type: "delete", ref: document.ref });
        }
      }
      await writeBulk(operations);
      cursor = snapshot.docs[snapshot.docs.length - 1];
      if (snapshot.size < BULK_WRITE_CHUNK_SIZE) return;
    }
  }

  async function finalize(active) {
    const claimed = await claimTask(active, "finalize");
    if (!claimed) {
      await ensureStoredContinuation(active);
      return;
    }
    const prefix = jobPrefix(active.uid, active.jobId);
    // Büyük hesaplarda üç fazın gzip açma tepe belleğini üst üste bindirme.
    const favoritesRaw = await readGzipJson(`${prefix}favorites.json.gz`, null);
    const filmsRaw = await readPagedSnapshot(active, "films", MAX_LIBRARY_ITEMS);
    const diaryRaw = await readPagedSnapshot(active, "diary", MAX_DIARY_ITEMS);
    const watchlistRaw = await readPagedSnapshot(active, "watchlist", MAX_LIBRARY_ITEMS);
    if (!favoritesRaw || !filmsRaw || !diaryRaw || !watchlistRaw ||
        favoritesRaw.complete !== true || filmsRaw.complete !== true ||
        diaryRaw.complete !== true || watchlistRaw.complete !== true) {
      throw new LetterboxdSyncError("partial-snapshot", "Letterboxd aktarımı eksik kaldı.");
    }

    const username = normalizeUsername(active.jobData.username);
    const userRef = db.collection("users").doc(active.uid);
    let favoriteItems = Array.isArray(favoritesRaw.items) ? favoritesRaw.items : [];
    if (favoritesRaw.unavailable === true) {
      const currentUser = await userRef.get();
      const preservedKeys = preservedProviderFavoriteKeys(
        currentUser.data() || {},
        username
      );
      favoriteItems = (Array.isArray(filmsRaw.items) ? filmsRaw.items : [])
        .filter((film) => preservedKeys.has(film.key))
        .map((film) => ({ ...film, favorite: true }));
    }
    const library = normalizedLibrary(
      Array.isArray(filmsRaw.items) ? filmsRaw.items : [],
      favoriteItems,
      Array.isArray(watchlistRaw.items) ? watchlistRaw.items : []
    );
    if (library.length > MAX_LIBRARY_ITEMS) {
      throw new LetterboxdSyncError(
        "too-many-items",
        "Birleştirilmiş Letterboxd kitaplığı güvenli kayıt sınırını aştı.",
        { permanent: true }
      );
    }
    const diary = normalizedDiary(Array.isArray(diaryRaw.items) ? diaryRaw.items : []);
    const diaryRecords = buildDiaryRecords(diary);
    const snapshotChecksum = checksum({ username, library, diary });
    const integration = integrationRef(active.uid);
    const libraryRef = db.collection("users").doc(active.uid).collection("library");
    const diaryRef = db.collection("users").doc(active.uid).collection("diary");
    const latestIntegration = await integration.get();
    const latestData = latestIntegration.data() || {};
    const storedManifest = await readGzipJson(manifestPath(active.uid), null);
    const storedManifestValid = validManifest(storedManifest);
    const projectionDirty = latestData.projectionDirty === true;
    const sameManifestAccount = storedManifestValid &&
      storedManifest.username === username;
    if (sameManifestAccount && (
      suspiciousSnapshotShrink(storedManifest.libraryCount, library.length) ||
      suspiciousSnapshotShrink(storedManifest.diaryCount, diaryRecords.length)
    )) {
      throw new LetterboxdSyncError(
        "suspicious-snapshot-shrink",
        "Letterboxd verisi beklenmedik ölçüde küçüldü; mevcut kayıtlar korundu."
      );
    }
    const manifestMatchesSnapshot = !projectionDirty && storedManifestValid &&
      storedManifest.snapshotChecksum === snapshotChecksum &&
      storedManifest.username === username;

    if (latestData.snapshotChecksum === snapshotChecksum && manifestMatchesSnapshot) {
      // Eski uygulama sürümü, ilk migration'dan sonra legacy tek-film Diary
      // belgeleri yazmış olabilir. Provider snapshot zaten eksiksizken bunları
      // düşük maliyetli sayfalı temizlikle yinelenen satırlara dönüşmeden kaldır.
      await deleteQueryInBatches(diaryRef.where("source", "==", "letterboxd_sync"));
      const nextTask = nextTaskData(active, "hydrate", { chunk: 0 });
      const now = admin.firestore.FieldValue.serverTimestamp();
      await db.runTransaction(async (transaction) => {
        const currentJobRef = jobRef(active.uid, active.jobId);
        const [current, currentJob] = await Promise.all([
          transaction.get(integration),
          transaction.get(currentJobRef),
        ]);
        if (!current.exists || !integrationMatches(active, current.data() || {})) {
          throw supersededError();
        }
        const currentJobData = currentJob.data() || {};
        if (!currentJob.exists || currentJobData.phase !== "finalize" ||
            currentJobData.projectionCommitted === true ||
            !ownsTaskClaim(active, currentJobData, "finalize")) {
          throw taskClaimLostError();
        }
        transaction.set(integration, {
          status: "success",
          username,
          pendingUsername: admin.firestore.FieldValue.delete(),
          lastCheckedAt: now,
          completedAt: now,
          updatedAt: now,
          leaseExpiresAt: admin.firestore.Timestamp.fromMillis(
            Date.now() + 35 * 60 * 1000
          ),
          error: admin.firestore.FieldValue.delete(),
        }, { merge: true });
        transaction.set(db.collection("users").doc(active.uid), {
          pendingLetterboxdUsername: admin.firestore.FieldValue.delete(),
          updatedAt: now,
        }, { merge: true });
        transaction.set(currentJobRef, {
          status: "success",
          phase: "hydrate",
          hydrateChunk: 0,
          nextTask,
          taskClaim: admin.firestore.FieldValue.delete(),
          projectionCommitted: true,
          unchanged: true,
          completedAt: now,
          updatedAt: now,
        }, { merge: true });
      });
      await enqueueNextTask(active, nextTask);
      await bucket().deleteFiles({ prefix }).catch(() => {});
      return;
    }

    const emptyManifest = {
      schemaVersion: SCHEMA_VERSION,
      library: {},
      diary: {},
    };
    // projectionDirty, önceki BulkWriter'ın kısmen uygulanmış olabileceğini
    // söyler. Bu durumda manifest checksum'ları değişmedi dese bile bütün güncel
    // provider kayıtlarını yeniden projekte et ve fazlalıkları reconcile et.
    const previousManifest = storedManifestValid && !projectionDirty
      ? storedManifest
      : emptyManifest;
    const autoResolveHistory = storedManifestValid ? storedManifest.library || {} : {};
    const previousLibrary = previousManifest.library || {};
    const previousDiary = previousManifest.diary || {};
    const recentKeys = new Set(diary.slice(0, 30).map((entry) => entry.key));
    const prioritizedLibrary = [...library]
      .sort((a, b) => {
        const priority = libraryPriority(a, recentKeys) - libraryPriority(b, recentKeys);
        return priority || a.key.localeCompare(b.key);
      });
    // Bir sonraki senkronizasyon öncelik sırasını değiştirse bile kullanıcı
    // başına otomatik TMDB bütçesi büyümesin. Hâlâ kitaplıkta bulunan önceki
    // seçimleri koru, boşalan yerleri yeni öncelikli filmlerle doldur.
    const automaticCatalogKeys = new Set();
    for (const film of prioritizedLibrary) {
      if (manifestEntry(autoResolveHistory[film.key]).autoResolve) {
        automaticCatalogKeys.add(film.key);
      }
      if (automaticCatalogKeys.size >= AUTOMATIC_CATALOG_LIMIT) break;
    }
    for (const film of prioritizedLibrary) {
      if (automaticCatalogKeys.size >= AUTOMATIC_CATALOG_LIMIT) break;
      automaticCatalogKeys.add(film.key);
    }
    const priorityFilms = prioritizedLibrary.slice(0, INLINE_CATALOG_LIMIT);
    const resolvedCatalog = await resolveCatalogFilms(priorityFilms);
    const resolvedByKey = resolvedCatalog instanceof Map
      ? resolvedCatalog
      : new Map(Object.entries(resolvedCatalog || {}));

    const revision = `${Date.now()}_${active.jobId.slice(0, 10)}`;
    const newManifest = {
      schemaVersion: SCHEMA_VERSION,
      username,
      snapshotChecksum,
      libraryCount: library.length,
      diaryCount: diaryRecords.length,
      library: {},
      diary: {},
    };
    const operations = [];

    for (const film of library) {
      const sourcePayload = {
        uri: film.uri,
        watched: film.watched,
        rating: film.rating,
        liked: film.liked,
        inWatchlist: film.inWatchlist,
        favorite: film.favorite,
        letterboxdId: film.letterboxdId,
        letterboxdLid: film.letterboxdLid,
      };
      const sourceChecksum = checksum(sourcePayload);
      const catalogSignature = checksum({ title: film.title, year: film.year });
      const autoResolve = automaticCatalogKeys.has(film.key);
      newManifest.library[film.key] = {
        checksum: sourceChecksum,
        catalogSignature,
        autoResolve,
      };
      const previous = manifestEntry(previousLibrary[film.key]);
      const catalogPrevious = manifestEntry(autoResolveHistory[film.key]);
      const resolved = resolvedByKey.get(film.key);
      const changed = previous.checksum !== sourceChecksum ||
        previous.catalogSignature !== catalogSignature ||
        previous.autoResolve !== autoResolve || resolved;
      if (!changed) continue;
      const isNew = !catalogPrevious.checksum;
      const catalogChanged = catalogPrevious.catalogSignature &&
        catalogPrevious.catalogSignature !== catalogSignature;
      const automaticStatusChanged = catalogPrevious.autoResolve !== autoResolve;
      operations.push({
        type: "set",
        ref: libraryRef.doc(film.key),
        data: {
          movieKey: film.key,
          source: PROVIDER,
          title: film.title,
          releaseYear: film.year,
          letterboxdUri: `${LETTERBOXD_ORIGIN}${film.uri}`,
          letterboxdId: film.letterboxdId,
          letterboxdLid: film.letterboxdLid,
          letterboxd: {
            ...sourcePayload,
            active: true,
            syncRevision: revision,
            syncedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          syncChecksum: sourceChecksum,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(resolved ? {
            tmdbId: positiveInteger(resolved.tmdbId),
            catalogDocId: cleanString(resolved.docId, 180),
            posterUrl: cleanString(resolved.posterUrl, 1200),
            resolutionStatus: "resolved",
            resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
          } : isNew || catalogChanged || automaticStatusChanged ? {
            resolutionStatus: autoResolve ? "pending" : "deferred",
            resolutionPriority: libraryPriority(film, recentKeys),
            ...(catalogChanged ? {
              tmdbId: admin.firestore.FieldValue.delete(),
              catalogDocId: admin.firestore.FieldValue.delete(),
              posterUrl: admin.firestore.FieldValue.delete(),
            } : {}),
          } : {}),
        },
        options: { merge: true },
      });
    }
    for (const oldKey of Object.keys(previousLibrary)) {
      if (newManifest.library[oldKey]) continue;
      operations.push({
        type: "delete",
        ref: libraryRef.doc(oldKey),
      });
    }

    for (const entry of diaryRecords) {
      const sourcePayload = {
        movieKey: entry.key,
        watchedDate: entry.watchedDate,
        rating: entry.rating,
        liked: entry.liked,
        rewatch: entry.rewatch,
        externalId: entry.externalId,
        fallbackIdentity: entry.fallbackIdentity,
        uri: entry.uri,
        title: entry.title,
        year: entry.year,
        reviewUri: entry.reviewUri,
        letterboxdId: entry.letterboxdId,
        letterboxdLid: entry.letterboxdLid,
      };
      const sourceChecksum = checksum(sourcePayload);
      newManifest.diary[entry.id] = sourceChecksum;
      if (previousDiary[entry.id] === sourceChecksum) continue;
      const resolved = resolvedByKey.get(entry.key);
      const watchedAt = admin.firestore.Timestamp.fromDate(
        new Date(`${entry.watchedDate}T12:00:00.000Z`)
      );
      operations.push({
        type: "set",
        ref: diaryRef.doc(entry.id),
        data: {
          id: entry.id,
          movieKey: entry.key,
          title: entry.title,
          ...(resolved ? {
            tmdbId: positiveInteger(resolved.tmdbId),
            posterUrl: cleanString(resolved.posterUrl, 1200),
          } : {}),
          ...(entry.year ? { releaseYear: entry.year } : {}),
          watchedAt,
          watchedDateKey: entry.watchedDate,
          recordedAt: admin.firestore.FieldValue.serverTimestamp(),
          source: PROVIDER,
          rating: entry.rating,
          liked: entry.liked,
          rewatch: entry.rewatch,
          externalId: entry.externalId,
          letterboxdUri: `${LETTERBOXD_ORIGIN}${entry.uri}`,
          syncRevision: revision,
        },
        // Rating gibi bir Letterboxd alanı değiştiğinde daha önce hydrate edilmiş
        // TMDB/poster bilgisini silme. Yeni kayıtta eksik alanlar doğal olarak
        // hydrate aşamasında tamamlanır.
        options: { merge: true },
      });
    }
    for (const oldId of Object.keys(previousDiary)) {
      if (!newManifest.diary[oldId]) {
        operations.push({ type: "delete", ref: diaryRef.doc(oldId) });
      }
    }
    // BulkWriter ile manifest/ana profil transaction'ı arasında crash olursa
    // eski geçerli manifestin "unchanged" kısa yoluna dönülmesin. Dirty fence
    // yalnız başarılı projection transaction'ında temizlenir.
    await db.runTransaction(async (transaction) => {
      const currentJobRef = jobRef(active.uid, active.jobId);
      const [currentIntegration, currentJob] = await Promise.all([
        transaction.get(integration),
        transaction.get(currentJobRef),
      ]);
      if (!currentIntegration.exists ||
          !integrationMatches(active, currentIntegration.data() || {})) {
        throw supersededError();
      }
      const currentJobData = currentJob.data() || {};
      if (!currentJob.exists || currentJobData.phase !== "finalize" ||
          currentJobData.projectionCommitted === true ||
          !ownsTaskClaim(active, currentJobData, "finalize")) {
        throw taskClaimLostError();
      }
      transaction.set(integration, {
        projectionDirty: true,
        projectionTargetChecksum: snapshotChecksum,
        projectionStartedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    // Manifest silinmiş/eksikse veya önceki projection yarım kaldıysa provider
    // belgelerini sayfalı reconcile et. Büyük hesaplarda iki koleksiyonu komple
    // belleğe almak yerine her 400 belgede fazlalıkları hemen siler.
    let reconciliationDeletes = 0;
    if (projectionDirty || !storedManifestValid) {
      reconciliationDeletes += await deleteProviderDocsMissing(
        active,
        libraryRef,
        newManifest.library
      );
      reconciliationDeletes += await deleteProviderDocsMissing(
        active,
        diaryRef,
        newManifest.diary
      );
    }
    await assertStillActive(active);
    const operationCount = operations.length + reconciliationDeletes;
    await writeBulk(operations);
    operations.length = 0;

    await deleteQueryInBatches(diaryRef.where("source", "==", "letterboxd_sync"));

    const favorites = library.filter((film) => film.favorite).slice(0, 4);
    const fiveStar = library.filter((film) => film.watched && film.rating === 5)
      .slice(0, LEGACY_MATCH_LIST_LIMIT);
    const disliked = library.filter((film) =>
      film.watched && film.rating !== null && film.rating <= 1
    ).slice(0, LEGACY_MATCH_LIST_LIMIT);
    const watchlist = library.filter((film) => film.inWatchlist)
      .slice(0, LEGACY_MATCH_LIST_LIMIT);
    const watched = prioritizedLibrary.filter((film) => film.watched)
      .slice(0, LEGACY_MATCH_LIST_LIMIT);
    function lite(film) {
      const resolved = resolvedByKey.get(film.key);
      return {
        key: film.key,
        title: film.title,
        url: `${LETTERBOXD_ORIGIN}${film.uri}`,
        posterUrl: cleanString(resolved && resolved.posterUrl, 1200),
        source: PROVIDER,
      };
    }
    const counts = {
      films: library.filter((film) => film.watched).length,
      diary: diary.length,
      ratings: library.filter((film) => film.rating !== null).length,
      likes: library.filter((film) => film.liked).length,
      watchlist: library.filter((film) => film.inWatchlist).length,
    };
    const serverTime = admin.firestore.FieldValue.serverTimestamp();
    const resolvedPosters = {};
    for (const film of [...fiveStar, ...disliked]) {
      const posterUrl = cleanString(resolvedByKey.get(film.key)?.posterUrl, 1200);
      if (posterUrl) resolvedPosters[film.key] = posterUrl;
    }

    await writeGzipJson(manifestPath(active.uid), newManifest);
    const nextTask = nextTaskData(active, "hydrate", { chunk: 0 });

    const tasteRef = db.collection("userTasteProfiles").doc(active.uid);
    const recentQuery = diaryRef.orderBy("watchedAt", "desc").limit(5);
    const deferredCatalogCount = library.filter((film) =>
      !automaticCatalogKeys.has(film.key)
    ).length;
    const pendingCatalogCount = Math.max(
      0,
      automaticCatalogKeys.size - resolvedByKey.size
    );
    await db.runTransaction(async (transaction) => {
      const currentJobRef = jobRef(active.uid, active.jobId);
      const [
        currentIntegration,
        currentJob,
        userSnapshot,
        tasteSnapshot,
        recentSnapshot,
      ] =
        await Promise.all([
          transaction.get(integration),
          transaction.get(currentJobRef),
          transaction.get(userRef),
          transaction.get(tasteRef),
          transaction.get(recentQuery),
        ]);
      if (!currentIntegration.exists ||
          !integrationMatches(active, currentIntegration.data() || {})) {
        throw supersededError();
      }
      const currentJobData = currentJob.data() || {};
      if (!currentJob.exists || currentJobData.phase !== "finalize" ||
          currentJobData.projectionCommitted === true ||
          !ownsTaskClaim(active, currentJobData, "finalize")) {
        throw taskClaimLostError();
      }
      const userData = userSnapshot.data() || {};
      if (!isActiveProfile(userData)) {
        throw supersededError();
      }
      const tasteData = tasteSnapshot.data() || {};
      const originalSources = userData.filmSources &&
        typeof userData.filmSources === "object"
        ? { ...userData.filmSources }
        : {};
      const sources = { ...originalSources };
      const protectedManualKeys = new Set();
      for (const field of [
        "favoritesKeys",
        "fiveStarKeys",
        "dislikedKeys",
        "watchlistKeys",
        "watchedKeys",
      ]) {
        const values = Array.isArray(userData[field]) ? userData[field] : [];
        for (const value of values) {
          const key = cleanString(String(value), 180);
          if (key && originalSources[key] !== PROVIDER) protectedManualKeys.add(key);
        }
      }
      function manualKeys(field) {
        const values = Array.isArray(userData[field]) ? userData[field] : [];
        return values.map(String).filter((key) =>
          key && originalSources[key] !== PROVIDER
        );
      }
      for (const [key, source] of Object.entries(sources)) {
        if (source === PROVIDER) delete sources[key];
      }
      function mergedLegacy(field, incoming) {
        const manual = manualKeys(field);
        const result = [...new Set([...manual, ...incoming.map((film) => film.key)])];
        for (const film of incoming) {
          if (!protectedManualKeys.has(film.key)) sources[film.key] = PROVIDER;
        }
        return result;
      }
      const favoriteKeys = mergedLegacy("favoritesKeys", favorites);
      const fiveStarKeys = mergedLegacy("fiveStarKeys", fiveStar);
      const dislikedKeys = mergedLegacy("dislikedKeys", disliked);
      const watchlistKeys = mergedLegacy("watchlistKeys", watchlist);
      const watchedKeys = mergedLegacy("watchedKeys", watched);
      function mergedLite(field, incoming, limit) {
        const byKey = new Map();
        const current = Array.isArray(userData[field]) ? userData[field] : [];
        for (const raw of current) {
          if (!raw || typeof raw !== "object" || raw.source === PROVIDER) continue;
          const key = cleanString(raw.key, 180);
          if (key) byKey.set(key, raw);
        }
        for (const film of incoming) {
          if (!byKey.has(film.key)) byKey.set(film.key, lite(film));
        }
        return [...byKey.values()].slice(0, limit);
      }
      const favoriteLite = mergedLite("favorites", favorites, 8);
      const watchlistLite = mergedLite("watchlist", watchlist, 30);
      const recentDiaryEntries = recentSnapshot.docs.map((document) => ({
        ...document.data(),
        id: document.id,
      }));
      const recentWatchedIds = recentDiaryEntries
        .map((entry) => cleanString(entry.movieKey, 180))
        .filter(Boolean);
      const tastePosters = {};
      const existingPosters = tasteData.posters && typeof tasteData.posters === "object"
        ? tasteData.posters
        : {};
      for (const [key, url] of Object.entries(existingPosters)) {
        if (originalSources[key] !== PROVIDER) {
          const safeUrl = cleanString(url, 1200);
          if (safeUrl) tastePosters[key] = safeUrl;
        }
      }
      Object.assign(tastePosters, resolvedPosters);
      // update() içindeki top-level filmSources alanı map'i bütünüyle değiştirir.
      // set(..., merge:true) eski filmSources.<key> leaf'lerini bırakıp manuel
      // filmleri ileride yanlışlıkla provider verisi sanabilirdi.
      transaction.update(userRef, {
        letterboxdUsername: username,
        letterboxdUsername_lc: username,
        lbUsername: username,
        pendingLetterboxdUsername: admin.firestore.FieldValue.delete(),
        librarySchemaVersion: SCHEMA_VERSION,
        diarySchemaVersion: SCHEMA_VERSION,
        letterboxdCounts: counts,
        favoritesKeys: favoriteKeys,
        favorites: favoriteLite,
        fiveStarKeys,
        dislikedKeys,
        watchlistKeys,
        watchlist: watchlistLite,
        watchedKeys,
        filmSources: sources,
        recentDiaryEntries,
        recentWatchedIds,
        recentWatchedUpdatedAt: serverTime,
        diaryUpdatedAt: serverTime,
        lastSyncedAt: serverTime,
        updatedAt: serverTime,
      });
      const tastePayload = {
        letterboxdUsername: username,
        loved: fiveStarKeys,
        disliked: dislikedKeys,
        posters: tastePosters,
        vector: admin.firestore.FieldValue.delete(),
        computedAtMs: Date.now(),
        updatedAt: serverTime,
      };
      if (tasteSnapshot.exists) transaction.update(tasteRef, tastePayload);
      else transaction.set(tasteRef, tastePayload);
      transaction.set(integration, {
        provider: PROVIDER,
        schemaVersion: SCHEMA_VERSION,
        username,
        pendingUsername: admin.firestore.FieldValue.delete(),
        status: "success",
        catalogStatus: pendingCatalogCount > 0
          ? "resolving"
          : (deferredCatalogCount > 0 ? "partial" : "complete"),
        deferredCatalogCount,
        counts,
        snapshotChecksum,
        lastSuccessfulSyncAt: serverTime,
        completedAt: serverTime,
        updatedAt: serverTime,
        leaseExpiresAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + 35 * 60 * 1000
        ),
        projectionDirty: admin.firestore.FieldValue.delete(),
        projectionTargetChecksum: admin.firestore.FieldValue.delete(),
        projectionStartedAt: admin.firestore.FieldValue.delete(),
        error: admin.firestore.FieldValue.delete(),
      }, { merge: true });
      transaction.set(currentJobRef, {
        status: "success",
        phase: "hydrate",
        hydrateChunk: 0,
        nextTask,
        taskClaim: admin.firestore.FieldValue.delete(),
        projectionCommitted: true,
        counts,
        writes: operationCount,
        completedAt: serverTime,
        updatedAt: serverTime,
      }, { merge: true });
    });
    await enqueueNextTask(active, nextTask, 5);
    await bucket().deleteFiles({ prefix }).catch(() => {});
  }

  async function hydrate(active) {
    if (active.jobData.projectionCommitted !== true) {
      throw new Error("letterboxd-finalize-not-committed");
    }
    const requestedChunk = Math.max(0, Number(active.taskData.chunk) || 0);
    const claimed = await claimTask(active, "hydrate", {
      cursorField: "hydrateChunk",
      cursor: requestedChunk,
      integrationExtra: {
        status: "success",
        catalogStatus: "resolving",
      },
    });
    if (!claimed) {
      await ensureStoredContinuation(active);
      return;
    }

    const library = db.collection("users").doc(active.uid).collection("library");
    const snapshot = await library
      .where("resolutionStatus", "==", "pending")
      .limit(HYDRATE_BATCH_SIZE)
      .get();
    if (snapshot.empty) {
      const diary = db.collection("users").doc(active.uid).collection("diary");
      const userRef = db.collection("users").doc(active.uid);
      const [missing, recent] = await Promise.all([
        library.where("resolutionStatus", "==", "missing").limit(1).get(),
        diary.orderBy("watchedAt", "desc").limit(5).get(),
      ]);
      const recentEntries = recent.docs.map((document) => ({
        ...document.data(),
        id: document.id,
      }));
      await db.runTransaction(async (transaction) => {
        const integration = integrationRef(active.uid);
        const currentJobRef = jobRef(active.uid, active.jobId);
        const [current, currentJob] = await Promise.all([
          transaction.get(integration),
          transaction.get(currentJobRef),
        ]);
        if (!current.exists || !integrationMatches(active, current.data() || {})) {
          throw supersededError();
        }
        const currentJobData = currentJob.data() || {};
        if (!currentJob.exists || currentJobData.phase !== "hydrate" ||
            currentJobData.projectionCommitted !== true ||
            Math.max(0, Number(currentJobData.hydrateChunk) || 0) !== requestedChunk ||
            !ownsTaskClaim(active, currentJobData, "hydrate", "hydrateChunk", requestedChunk)) {
          throw taskClaimLostError();
        }
        const data = current.data() || {};
        const deferredCount = Math.max(0, Number(data.deferredCatalogCount) || 0);
        const catalogStatus = deferredCount > 0 || !missing.empty
          ? "partial"
          : "complete";
        const now = admin.firestore.FieldValue.serverTimestamp();
        transaction.set(userRef, {
          recentDiaryEntries: recentEntries,
          recentWatchedIds: recentEntries.map((entry) => entry.movieKey).filter(Boolean),
          diaryUpdatedAt: now,
          updatedAt: now,
        }, { merge: true });
        transaction.set(integration, {
          catalogStatus,
          catalogCompletedAt: now,
          updatedAt: now,
          activeJobId: admin.firestore.FieldValue.delete(),
          lastJobId: active.jobId,
          leaseExpiresAt: admin.firestore.FieldValue.delete(),
        }, { merge: true });
        transaction.set(currentJobRef, {
          phase: "complete",
          catalogStatus,
          nextTask: admin.firestore.FieldValue.delete(),
          taskClaim: admin.firestore.FieldValue.delete(),
          updatedAt: now,
        }, { merge: true });
      });
      return;
    }

    const films = snapshot.docs.map((document) => {
      const data = document.data() || {};
      return {
        key: document.id,
        title: cleanString(data.title, 180),
        year: normalizeYear(data.releaseYear),
      };
    });
    const resolvedCatalog = await resolveCatalogFilms(films);
    const resolvedByKey = resolvedCatalog instanceof Map
      ? resolvedCatalog
      : new Map(Object.entries(resolvedCatalog || {}));
    const libraryOperations = [];
    const diary = db.collection("users").doc(active.uid).collection("diary");
    const resolvedKeys = [];
    const tastePosters = {};
    for (const document of snapshot.docs) {
      const resolved = resolvedByKey.get(document.id);
      libraryOperations.push({
        type: "set",
        ref: document.ref,
        data: resolved ? {
          tmdbId: positiveInteger(resolved.tmdbId),
          catalogDocId: cleanString(resolved.docId, 180),
          posterUrl: cleanString(resolved.posterUrl, 1200),
          resolutionStatus: "resolved",
          resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        } : {
          resolutionStatus: "missing",
          resolutionAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        options: { merge: true },
      });
      if (!resolved) continue;
      resolvedKeys.push(document.id);
      const data = document.data() || {};
      const rating = normalizeRating(data.letterboxd && data.letterboxd.rating);
      if (rating === 5 || (rating !== null && rating <= 1)) {
        const posterUrl = cleanString(resolved.posterUrl, 1200);
        if (posterUrl) tastePosters[document.id] = posterUrl;
      }
    }
    for (let index = 0; index < resolvedKeys.length; index += 30) {
      const keys = resolvedKeys.slice(index, index + 30);
      await writeDiaryCatalogUpdates(active, diary, keys, resolvedByKey);
    }
    await assertStillActive(active);
    // Diary/taste bağımlılıklarını önce idempotent biçimde tamamla.
    // resolutionStatus marker'ı bundan önce yazılır ve process çökerse film
    // pending sorgusundan düşerek eksik posterin kalıcı olmasına yol açardı.
    if (Object.keys(tastePosters).length) {
      await db.collection("userTasteProfiles").doc(active.uid).set({
        posters: tastePosters,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    await assertStillActive(active);
    await writeBulk(libraryOperations);

    const chunk = requestedChunk + 1;
    const nextTask = nextTaskData(active, "hydrate", { chunk });
    await db.runTransaction(async (transaction) => {
      const integration = integrationRef(active.uid);
      const currentJobRef = jobRef(active.uid, active.jobId);
      const [current, currentJob] = await Promise.all([
        transaction.get(integration),
        transaction.get(currentJobRef),
      ]);
      if (!current.exists || !integrationMatches(active, current.data() || {})) {
        throw supersededError();
      }
      const currentJobData = currentJob.data() || {};
      if (!currentJob.exists || currentJobData.phase !== "hydrate" ||
          currentJobData.projectionCommitted !== true ||
          Math.max(0, Number(currentJobData.hydrateChunk) || 0) !== requestedChunk ||
          !ownsTaskClaim(active, currentJobData, "hydrate", "hydrateChunk", requestedChunk)) {
        throw taskClaimLostError();
      }
      transaction.set(integration, {
        catalogStatus: "resolving",
        catalogLastBatchResolved: resolvedByKey.size,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      transaction.set(currentJobRef, {
        hydrateChunk: chunk,
        nextTask,
        taskClaim: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });
    await enqueueNextTask(active, nextTask);
  }

  async function failJob(active, error) {
    const code = cleanString(error && error.code, 80) || "sync-failed";
    const message = cleanString(error && error.message, 300) ||
      "Letterboxd senkronizasyonu tamamlanamadı.";
    const serverTime = admin.firestore.FieldValue.serverTimestamp();
    const failed = await db.runTransaction(async (transaction) => {
      const integration = integrationRef(active.uid);
      const currentJobRef = jobRef(active.uid, active.jobId);
      const [current, currentJob] = await Promise.all([
        transaction.get(integration),
        transaction.get(currentJobRef),
      ]);
      if (!current.exists || !currentJob.exists ||
          !integrationMatches(active, current.data() || {})) {
        return false;
      }
      const currentJobData = currentJob.data() || {};
      const liveClaim = currentJobData.taskClaim &&
        typeof currentJobData.taskClaim === "object"
        ? currentJobData.taskClaim
        : {};
      if (active.taskClaim) {
        if (liveClaim.owner !== active.invocationId ||
            liveClaim.key !== active.taskClaim.key ||
            Math.max(0, Number(liveClaim.epoch) || 0) !== active.taskClaim.epoch) {
          return false;
        }
      } else if (timestampMillis(liveClaim.expiresAt) > Date.now()) {
        return false;
      }
      transaction.set(integration, {
        status: "failed",
        error: { code, message },
        failedAt: serverTime,
        updatedAt: serverTime,
        activeJobId: admin.firestore.FieldValue.delete(),
        lastJobId: active.jobId,
        leaseExpiresAt: admin.firestore.FieldValue.delete(),
      }, { merge: true });
      transaction.set(currentJobRef, {
        status: "failed",
        nextTask: admin.firestore.FieldValue.delete(),
        taskClaim: admin.firestore.FieldValue.delete(),
        errorCode: code,
        errorMessage: message,
        failedAt: serverTime,
        updatedAt: serverTime,
      }, { merge: true });
      return true;
    });
    if (failed) {
      await bucket().deleteFiles({ prefix: jobPrefix(active.uid, active.jobId) }).catch(() => {});
    }
    return failed;
  }

  async function finishHydrationWithError(active, error) {
    const code = cleanString(error && error.code, 80) || "catalog-hydration-failed";
    const message = cleanString(error && error.message, 300) ||
      "Bazı film bilgileri daha sonra tamamlanacak.";
    const now = admin.firestore.FieldValue.serverTimestamp();
    return db.runTransaction(async (transaction) => {
      const integration = integrationRef(active.uid);
      const currentJobRef = jobRef(active.uid, active.jobId);
      const [current, currentJob] = await Promise.all([
        transaction.get(integration),
        transaction.get(currentJobRef),
      ]);
      if (!current.exists || !currentJob.exists ||
          !integrationMatches(active, current.data() || {})) return false;
      const currentJobData = currentJob.data() || {};
      const liveClaim = currentJobData.taskClaim &&
        typeof currentJobData.taskClaim === "object"
        ? currentJobData.taskClaim
        : {};
      if (active.taskClaim) {
        if (liveClaim.owner !== active.invocationId ||
            liveClaim.key !== active.taskClaim.key ||
            Math.max(0, Number(liveClaim.epoch) || 0) !== active.taskClaim.epoch) {
          return false;
        }
      } else if (timestampMillis(liveClaim.expiresAt) > Date.now()) {
        return false;
      }
      transaction.set(integration, {
        status: "success",
        catalogStatus: "partial",
        catalogError: { code, message },
        activeJobId: admin.firestore.FieldValue.delete(),
        lastJobId: active.jobId,
        leaseExpiresAt: admin.firestore.FieldValue.delete(),
        updatedAt: now,
      }, { merge: true });
      transaction.set(currentJobRef, {
        status: "partial",
        phase: "complete",
        nextTask: admin.firestore.FieldValue.delete(),
        taskClaim: admin.firestore.FieldValue.delete(),
        errorCode: code,
        errorMessage: message,
        updatedAt: now,
      }, { merge: true });
      return true;
    });
  }

  async function processTask(request) {
    const data = request.data || {};
    const phase = cleanString(data.phase, 30);
    const active = await activeJob(data);
    if (!active) return;
    active.taskData = data;
    active.invocationId = crypto.randomUUID();
    active.retryCount = Math.max(0, Number(request.retryCount) || 0);
    try {
      switch (phase) {
        case "profile":
          await processProfile(active);
          break;
        case "films":
          await processPagedPhase(
            active,
            "films",
            parseFilmPage,
            { watched: true },
            "diary",
            "diary/"
          );
          break;
        case "diary":
          await processPagedPhase(active, "diary", parseDiaryPage, {}, "watchlist", "watchlist/");
          break;
        case "watchlist":
          await processPagedPhase(
            active,
            "watchlist",
            parseFilmPage,
            { inWatchlist: true, expectedPageSize: 28 },
            "finalize",
            ""
          );
          break;
        case "finalize":
          await finalize(active);
          break;
        case "hydrate":
          await hydrate(active);
          break;
        default:
          throw new LetterboxdSyncError("invalid-phase", "Geçersiz senkronizasyon aşaması.", {
            permanent: true,
          });
      }
    } catch (error) {
      if (error instanceof LetterboxdSyncError && error.code === "task-claim-lost") {
        return;
      }
      if (error instanceof LetterboxdSyncError && error.code === "superseded") {
        await jobRef(active.uid, active.jobId).delete().catch(() => {});
        await bucket().deleteFiles({
          prefix: jobPrefix(active.uid, active.jobId),
        }).catch(() => {});
        return;
      }
      console.error("Letterboxd sync task failed", {
        uid: active.uid,
        jobId: active.jobId,
        phase,
        retryCount: request.retryCount,
        code: error && error.code,
        message: error && error.message,
      });
      const permanent = error instanceof LetterboxdSyncError && error.permanent;
      const exhausted = Number(request.retryCount || 0) >= 4;
      await jobRef(active.uid, active.jobId).set({
        lastErrorCode: cleanString(error && error.code, 80) || "sync-failed",
        lastErrorMessage: cleanString(error && error.message, 300),
        lastRetryCount: Number(request.retryCount || 0),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true }).catch(() => {});
      if (permanent || exhausted) {
        let terminated = false;
        if (phase === "hydrate" && active.jobData.projectionCommitted === true) {
          terminated = await finishHydrationWithError(active, error);
        } else {
          terminated = await failJob(active, error);
        }
        if (!terminated) await ensureStoredContinuation(active).catch(() => {});
        return;
      }
      // Yalnız retry edilecek transient hatada claim'i bırak. Terminal state
      // transaction'ı claim CAS'i ile atomik olduğundan yeni owner'ı ezemez.
      await releaseTaskClaim(active).catch(() => {});
      throw error;
    }
  }

  async function disconnect(request) {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Oturum açmanız gerekiyor.");
    const integration = integrationRef(uid);
    const userRef = db.collection("users").doc(uid);
    const libraryRef = userRef.collection("library");
    const diaryRef = userRef.collection("diary");
    const disconnectOwner = crypto.randomUUID();
    let disconnectGeneration;
    let skipCleanup = false;
    let skippedStatus = "disconnecting";

    await db.runTransaction(async (transaction) => {
      const [current, user] = await Promise.all([
        transaction.get(integration),
        transaction.get(userRef),
      ]);
      const userData = user.data() || {};
      if (!user.exists || !isActiveProfile(userData)) {
        throw new HttpsError("failed-precondition", "Aktif profil bulunamadı.");
      }
      const data = current.data() || {};
      const leaseActive = timestampMillis(data.leaseExpiresAt) > Date.now();
      if (data.status === "disconnected" && !data.username && !data.pendingUsername) {
        disconnectGeneration = positiveInteger(data.generation) || 1;
        skipCleanup = true;
        skippedStatus = "disconnected";
        return;
      }
      if (data.status === "disconnecting" && leaseActive) {
        disconnectGeneration = positiveInteger(data.generation) || 1;
        // Başka callable canlı maintenance lease'i tutuyorsa aynı yıkıcı
        // cleanup'a paralel girme. İlk owner tamamlayacak; hard-crash halinde
        // lease dolduktan sonra yeni çağrı generation artırıp devralır.
        skipCleanup = true;
        return;
      }
      if (leaseActive && data.activeJobId) {
        throw new HttpsError(
          "failed-precondition",
          "Senkronizasyon sürerken bağlantı kaldırılamaz. Kısa süre sonra tekrar deneyin."
        );
      }
      const lastJobId = cleanString(data.lastJobId, 128);
      if (lastJobId) transaction.delete(jobRef(uid, lastJobId));
      disconnectGeneration = (positiveInteger(data.generation) || 0) + 1;
      if (data.activeJobId) {
        transaction.set(jobRef(uid, cleanString(data.activeJobId, 128)), {
          status: "cancelled",
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      transaction.set(integration, {
        provider: PROVIDER,
        generation: disconnectGeneration,
        status: "disconnecting",
        activeJobId: admin.firestore.FieldValue.delete(),
        lastJobId: admin.firestore.FieldValue.delete(),
        disconnectOwner,
        leaseExpiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    if (skipCleanup) {
      if (skippedStatus === "disconnecting") {
        throw new HttpsError(
          "failed-precondition",
          "Letterboxd bağlantısı başka bir istekte kaldırılıyor. Kısa süre sonra tekrar deneyin."
        );
      }
      return { ok: true, status: skippedStatus };
    }

    const manifest = await readGzipJson(manifestPath(uid), null);
    if (manifest && manifest.library && typeof manifest.library === "object") {
      const keys = Object.keys(manifest.library);
      for (let start = 0; start < keys.length; start += BULK_WRITE_CHUNK_SIZE) {
        await writeBulk(keys.slice(start, start + BULK_WRITE_CHUNK_SIZE).map((key) => ({
          type: "delete",
          ref: libraryRef.doc(key),
        })));
      }
    } else {
      await deleteNestedProviderLibrary(libraryRef);
    }
    if (manifest && manifest.diary && typeof manifest.diary === "object") {
      const ids = Object.keys(manifest.diary);
      for (let start = 0; start < ids.length; start += BULK_WRITE_CHUNK_SIZE) {
        await writeBulk(ids.slice(start, start + BULK_WRITE_CHUNK_SIZE).map((id) => ({
          type: "delete",
          ref: diaryRef.doc(id),
        })));
      }
    }
    // Eksik/stale manifestte kalan provider belgelerini de düşük bellekli
    // sayfalı sorgularla temizle.
    await deleteQueryInBatches(libraryRef.where("source", "==", PROVIDER));
    await deleteQueryInBatches(
      diaryRef.where("source", "in", ["letterboxd", "letterboxd_sync"])
    );

    // Integration hâlâ disconnecting + lease altında iken storage'ı temizle.
    // Önce disconnected yapıp sonra UID prefix'ini silmek, aradaki dar aralıkta
    // başlayan yeni job'ın staging dosyalarını yanlışlıkla silebilirdi.
    await bucket().file(manifestPath(uid)).delete({ ignoreNotFound: true });
    await bucket().deleteFiles({ prefix: `letterboxd_jobs/${uid}/` });

    const serverTime = admin.firestore.FieldValue.serverTimestamp();
    const tasteRef = db.collection("userTasteProfiles").doc(uid);
    const recentQuery = diaryRef.orderBy("watchedAt", "desc").limit(5);
    await db.runTransaction(async (transaction) => {
      const [current, user, taste, recent] = await Promise.all([
        transaction.get(integration),
        transaction.get(userRef),
        transaction.get(tasteRef),
        transaction.get(recentQuery),
      ]);
      const currentData = current.data() || {};
      if (!current.exists || currentData.status !== "disconnecting" ||
          positiveInteger(currentData.generation) !== disconnectGeneration ||
          currentData.disconnectOwner !== disconnectOwner) {
        throw new HttpsError("aborted", "Bağlantı kaldırma işlemi geçersiz kılındı.");
      }
      const data = user.data() || {};
      const tasteData = taste.data() || {};
      const originalSources = data.filmSources && typeof data.filmSources === "object"
        ? { ...data.filmSources }
        : {};
      const sources = { ...originalSources };
      function withoutLetterboxd(field) {
        const values = Array.isArray(data[field]) ? data[field].map(String) : [];
        return values.filter((key) => originalSources[key] !== PROVIDER);
      }
      function withoutLetterboxdLite(field) {
        const values = Array.isArray(data[field]) ? data[field] : [];
        return values.filter((item) =>
          item && typeof item === "object" && item.source !== PROVIDER
        );
      }
      for (const [key, source] of Object.entries(sources)) {
        if (source === PROVIDER) delete sources[key];
      }
      const recentEntries = recent.docs.map((document) => ({
        ...document.data(),
        id: document.id,
      }));
      const cleanPosters = {};
      const currentPosters = tasteData.posters && typeof tasteData.posters === "object"
        ? tasteData.posters
        : {};
      for (const [key, url] of Object.entries(currentPosters)) {
        if (originalSources[key] !== PROVIDER) {
          const safeUrl = cleanString(url, 1200);
          if (safeUrl) cleanPosters[key] = safeUrl;
        }
      }
      transaction.update(userRef, {
        letterboxdUsername: admin.firestore.FieldValue.delete(),
        letterboxdUsername_lc: admin.firestore.FieldValue.delete(),
        lbUsername: admin.firestore.FieldValue.delete(),
        pendingLetterboxdUsername: admin.firestore.FieldValue.delete(),
        letterboxdCounts: admin.firestore.FieldValue.delete(),
        favoritesKeys: withoutLetterboxd("favoritesKeys"),
        favorites: withoutLetterboxdLite("favorites"),
        fiveStarKeys: withoutLetterboxd("fiveStarKeys"),
        dislikedKeys: withoutLetterboxd("dislikedKeys"),
        watchlistKeys: withoutLetterboxd("watchlistKeys"),
        watchlist: withoutLetterboxdLite("watchlist"),
        watchedKeys: withoutLetterboxd("watchedKeys"),
        filmSources: sources,
        recentDiaryEntries: recentEntries,
        recentWatchedIds: recentEntries.map((entry) => entry.movieKey).filter(Boolean),
        updatedAt: serverTime,
        diaryUpdatedAt: serverTime,
      });
      const tastePayload = {
        letterboxdUsername: admin.firestore.FieldValue.delete(),
        loved: withoutLetterboxd("fiveStarKeys"),
        disliked: withoutLetterboxd("dislikedKeys"),
        posters: cleanPosters,
        vector: admin.firestore.FieldValue.delete(),
        updatedAt: serverTime,
      };
      if (taste.exists) transaction.update(tasteRef, tastePayload);
      else transaction.set(tasteRef, tastePayload);
      transaction.set(integration, {
        provider: PROVIDER,
        generation: disconnectGeneration,
        status: "disconnected",
        username: admin.firestore.FieldValue.delete(),
        pendingUsername: admin.firestore.FieldValue.delete(),
        activeJobId: admin.firestore.FieldValue.delete(),
        disconnectOwner: admin.firestore.FieldValue.delete(),
        snapshotChecksum: admin.firestore.FieldValue.delete(),
        counts: admin.firestore.FieldValue.delete(),
        projectionDirty: admin.firestore.FieldValue.delete(),
        projectionTargetChecksum: admin.firestore.FieldValue.delete(),
        projectionStartedAt: admin.firestore.FieldValue.delete(),
        disconnectedAt: serverTime,
        updatedAt: serverTime,
        leaseExpiresAt: admin.firestore.FieldValue.delete(),
        error: admin.firestore.FieldValue.delete(),
      }, { merge: true });
    });
    return { ok: true };
  }

  return { requestSync, processTask, disconnect };
}

module.exports = {
  createLetterboxdSync,
  __test: {
    parseFilmPage,
    parseProfilePage,
    parseDiaryPage,
    legacyDiaryId,
    canonicalFilmPath,
    normalizeUsername,
    suspiciousSnapshotShrink,
    normalizeClientFavorites,
  },
};
