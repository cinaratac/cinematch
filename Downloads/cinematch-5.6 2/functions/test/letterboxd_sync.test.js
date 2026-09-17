/* eslint-disable */
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { __test } = require("../letterboxd_sync");

function poster({ slug, title, year, ratingClass = "", liked = false }) {
  return `
    <li class="griditem">
      <div class="react-component" data-item-slug="${slug}"
        data-item-link="/film/${slug}/" data-item-name="${title} (${year})"
        data-postered-identifier='{"lid":"abc","uid":"film:123"}'>
        <div class="poster"><img alt="${title}"></div>
      </div>
      <p class="poster-viewingdata">
        ${ratingClass ? `<span class="rating ${ratingClass}"></span>` : ""}
        ${liked ? '<span class="like liked-micro icon-liked"></span>' : ""}
      </p>
    </li>`;
}

test("films sayfası bütün puanları, beğeniyi ve güvenli next adresini okur", () => {
  const html = `
    <meta property="og:url" content="https://letterboxd.com/alice/films/">
    <ul class="grid">
      ${poster({ slug: "heat-1995", title: "Heat", year: 1995, ratingClass: "rated-7", liked: true })}
      ${poster({ slug: "arrival-2016", title: "Arrival", year: 2016, ratingClass: "rated-10" })}
    </ul>
    <a class="next" href="/alice/films/page/2/">Next</a></html>`;
  const result = __test.parseFilmPage(html, "alice", { watched: true });

  assert.equal(result.valid, true);
  assert.equal(result.items.length, 2);
  assert.equal(result.items[0].key, "film:heat-1995");
  assert.equal(result.items[0].rating, 3.5);
  assert.equal(result.items[0].liked, true);
  assert.equal(result.items[1].rating, 5);
  assert.equal(result.nextUrl, "https://letterboxd.com/alice/films/page/2/");
  assert.equal(result.lastPageConfirmed, false);
});

test("sayfalama kaybolursa dolu ilk sayfa yanlışlıkla son sayfa sayılmaz", () => {
  const items = Array.from({ length: 72 }, (_, index) => poster({
    slug: `film-${index}`,
    title: `Film ${index}`,
    year: 2000 + (index % 20),
  })).join("");
  const result = __test.parseFilmPage(
    `<meta property="og:url" content="https://letterboxd.com/alice/films/"><ul>${items}</ul></html>`,
    "alice",
    { watched: true }
  );
  assert.equal(result.valid, true);
  assert.equal(result.items.length, 72);
  assert.equal(result.nextUrl, "");
  assert.equal(result.lastPageConfirmed, false);
});

test("devre dışı next kontrolü son sayfayı açıkça doğrular", () => {
  const result = __test.parseFilmPage(
    `<meta property="og:url" content="https://letterboxd.com/alice/films/page/2/">
     <ul>${poster({ slug: "last-film", title: "Last Film", year: 2020 })}</ul>
     <div class="pagination">
       <div class="paginate-nextprev"><a class="previous" href="/alice/films/">Newer</a></div>
       <div class="paginate-nextprev paginate-disabled"><span class="next">Older</span></div>
       <div class="paginate-pages"><span class="paginate-page paginate-current">2</span></div>
     </div></html>`,
    "alice",
    { watched: true }
  );
  assert.equal(result.valid, true);
  assert.equal(result.lastPageConfirmed, true);
});

test("Diary gerçek viewing kimliği, tarih, puan, beğeni ve rewatch bilgisini korur", () => {
  const html = `
    <meta property="og:url" content="https://letterboxd.com/alice/diary/">
    <table id="diary-table"><tbody>
      <tr class="diary-entry-row" data-viewing-id="98765">
        <td><a class="daydate" href="/alice/diary/films/for/2026/08/03/">03</a></td>
        <td>${poster({ slug: "heat-1995", title: "Heat", year: 1995 })}</td>
        <td class="col-rating"><input type="range" value="9"></td>
        <td class="col-like"><span class="icon-liked"></span></td>
        <td class="col-rewatch icon-status-on"></td>
        <td class="col-review"><a href="/alice/film/heat-1995/">Review</a></td>
      </tr>
    </tbody></table></html>`;
  const result = __test.parseDiaryPage(html, "alice");

  assert.equal(result.valid, true);
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].externalId, "98765");
  assert.equal(result.items[0].watchedDate, "2026-08-03");
  assert.equal(result.items[0].rating, 4.5);
  assert.equal(result.items[0].liked, true);
  assert.equal(result.items[0].rewatch, true);
});

test("profil favorileri dört filmle sınırlanır", () => {
  const html = `
    <a href="/alice/films/">Films</a>
    <section id="favourites"><ul>
      ${poster({ slug: "one", title: "One", year: 2001 })}
      ${poster({ slug: "two", title: "Two", year: 2002 })}
      ${poster({ slug: "three", title: "Three", year: 2003 })}
      ${poster({ slug: "four", title: "Four", year: 2004 })}
      ${poster({ slug: "five", title: "Five", year: 2005 })}
    </ul></section></html>`;
  const result = __test.parseProfilePage(html, "alice");
  assert.equal(result.looksValid, true);
  assert.equal(result.favoritesKnown, true);
  assert.equal(result.favorites.length, 4);
});

test("istemciden gelen favoriler yalnız güvenli Letterboxd filmlerini kabul eder", () => {
  const result = __test.normalizeClientFavorites([
    { title: "Heat", url: "https://letterboxd.com/film/heat-1995/", year: 1995 },
    { title: "Kötü", url: "https://example.com/film/bad/", year: 2020 },
    { title: "", url: "https://letterboxd.com/film/no-title/" },
  ]);
  assert.equal(result.length, 1);
  assert.equal(result[0].key, "film:heat-1995");
  assert.equal(result[0].favorite, true);
});

test("beklenmeyen 200 HTML'i boş snapshot olarak kabul edilmez", () => {
  const interstitial = __test.parseFilmPage(
    `<html><body><main>Please sign in to continue</main></body></html>`,
    "alice",
    { watched: true }
  );
  assert.equal(interstitial.items.length, 0);
  assert.equal(interstitial.valid, false);

  const confirmedEmpty = __test.parseFilmPage(
    `<meta property="og:url" content="https://letterboxd.com/alice/films/">
     <main><div class="empty-state">No films</div></main></html>`,
    "alice",
    { watched: true }
  );
  assert.equal(confirmedEmpty.items.length, 0);
  assert.equal(confirmedEmpty.emptyConfirmed, true);
  assert.equal(confirmedEmpty.valid, true);
  assert.equal(confirmedEmpty.lastPageConfirmed, true);
});

test("ikinci sayfadaki boş durum açık son işareti olmadan terminal sayılmaz", () => {
  const result = __test.parseFilmPage(
    `<meta property="og:url" content="https://letterboxd.com/alice/films/page/2/">
     <main><div class="empty-state">No films</div></main></html>`,
    "alice",
    { watched: true, pageNumber: 1 }
  );
  assert.equal(result.valid, true);
  assert.equal(result.emptyConfirmed, true);
  assert.equal(result.lastPageConfirmed, false);
});

test("kesilmiş küçük ilk sayfa tam snapshot sayılmaz", () => {
  const items = Array.from({ length: 10 }, (_, index) => poster({
    slug: `short-${index}`,
    title: `Short ${index}`,
    year: 2010 + index,
  })).join("");
  const prefix =
    `<meta property="og:url" content="https://letterboxd.com/alice/films/"><ul>${items}</ul>`;
  const truncated = __test.parseFilmPage(prefix, "alice", { watched: true });
  const complete = __test.parseFilmPage(`${prefix}</html>`, "alice", { watched: true });
  assert.equal(truncated.valid, false);
  assert.equal(truncated.lastPageConfirmed, false);
  assert.equal(complete.lastPageConfirmed, true);
});

test("yalnız büyük ve şüpheli snapshot küçülmeleri korunmaya alınır", () => {
  assert.equal(__test.suspiciousSnapshotShrink(1000, 300), true);
  assert.equal(__test.suspiciousSnapshotShrink(1000, 700), false);
  assert.equal(__test.suspiciousSnapshotShrink(80, 1), false);
});

test("harici ve başka kullanıcıya ait sayfalama adresleri reddedilir", () => {
  const external = __test.parseFilmPage(
    `<a class="next" href="https://example.com/alice/films/page/2/"></a>`,
    "alice",
    { watched: true }
  );
  const otherUser = __test.parseFilmPage(
    `<a class="next" href="/bob/films/page/2/"></a>`,
    "alice",
    { watched: true }
  );
  assert.equal(external.nextUrl, "");
  assert.equal(otherUser.nextUrl, "");
});

test("legacy Diary kimliği film başına deterministiktir", () => {
  assert.equal(
    __test.legacyDiaryId("film:heat-1995"),
    __test.legacyDiaryId("film:heat-1995")
  );
  assert.notEqual(
    __test.legacyDiaryId("film:heat-1995"),
    __test.legacyDiaryId("film:arrival-2016")
  );
});
