const { auth, functions } = CineAdmin;

function setMessage(target, text, type = "") {
  target.textContent = text || "";
  target.className = `message ${type}`.trim();
}

const els = {
  weekDate: document.getElementById("weekDate"),
  generateButton: document.getElementById("generateButton"),
  generatePromoButton: document.getElementById("generatePromoButton"),
  generateListButton: document.getElementById("generateListButton"),
  listLabel: document.getElementById("listLabel"),
  listHeadline: document.getElementById("listHeadline"),
  listCover: document.getElementById("listCover"),
  listCoverUpload: document.getElementById("listCoverUpload"),
  generateGridButton: document.getElementById("generateGridButton"),
  gridMovieLinks: document.getElementById("gridMovieLinks"),
  generateRatingButton: document.getElementById("generateRatingButton"),
  ratingHeadline: document.getElementById("ratingHeadline"),
  ratingMovieLinks: document.getElementById("ratingMovieLinks"),
  generateCineheardButton: document.getElementById("generateCineheardButton"),
  cineheardQuote: document.getElementById("cineheardQuote"),
  cineheardSource: document.getElementById("cineheardSource"),
  downloadButton: document.getElementById("downloadButton"),
  statusMessage: document.getElementById("statusMessage"),
  emptyPreview: document.getElementById("emptyPreview"),
  canvas: document.getElementById("socialCanvas"),
};

let currentWeekId = "";
let currentExportName = "cinematch-gorsel";

function localDateValue(date = new Date()) {
  const offset = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 10);
}
els.weekDate.value = localDateValue();
let authReady = false;

auth.onAuthStateChanged(async (user) => {
  if (!user) {
    window.location.replace("/admin-news");
    return;
  }
  try {
    await CineAdmin.requireRole(user, "newsAdmin", () =>
      functions.httpsCallable("isNewsAdmin")()
    );
    authReady = true;
  } catch (error) {
    setMessage(els.statusMessage, "Bu bölüm için admin yetkisi gerekli.", "error");
    els.generateButton.disabled = true;
  }
});

function posterUrl(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  return raw.startsWith("http") ? raw : `https://image.tmdb.org/t/p/w500${raw}`;
}

function loadImage(src) {
  return new Promise((resolve) => {
    if (!src) return resolve(null);
    const image = new Image();
    image.crossOrigin = "anonymous";
    image.onload = () => resolve(image);
    image.onerror = () => resolve(null);
    image.src = src;
  });
}

function roundRect(ctx, x, y, width, height, radius) {
  const r = Math.min(radius, width / 2, height / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + width, y, x + width, y + height, r);
  ctx.arcTo(x + width, y + height, x, y + height, r);
  ctx.arcTo(x, y + height, x, y, r);
  ctx.arcTo(x, y, x + width, y, r);
  ctx.closePath();
}

function coverImage(ctx, image, x, y, width, height) {
  const scale = Math.max(width / image.width, height / image.height);
  const sourceWidth = width / scale;
  const sourceHeight = height / scale;
  const sx = (image.width - sourceWidth) / 2;
  const sy = (image.height - sourceHeight) / 2;
  ctx.drawImage(image, sx, sy, sourceWidth, sourceHeight, x, y, width, height);
}

function fitText(ctx, text, maxWidth, startSize, weight = 800) {
  let size = startSize;
  do {
    ctx.font = `${weight} ${size}px Arial, Helvetica, sans-serif`;
    if (ctx.measureText(text).width <= maxWidth) return size;
    size -= 1;
  } while (size > 20);
  return size;
}

function truncateText(ctx, text, maxWidth) {
  if (ctx.measureText(text).width <= maxWidth) return text;
  let value = text;
  while (value.length > 1 && ctx.measureText(`${value}…`).width > maxWidth) {
    value = value.slice(0, -1);
  }
  return `${value}…`;
}

function wrapTextLines(ctx, text, maxWidth) {
  const paragraphs = String(text || "").trim().split(/\n+/);
  const lines = [];
  paragraphs.forEach((paragraph) => {
    const words = paragraph.trim().split(/\s+/).filter(Boolean);
    let line = "";
    words.forEach((word) => {
      const candidate = line ? `${line} ${word}` : word;
      if (line && ctx.measureText(candidate).width > maxWidth) {
        lines.push(line);
        line = word;
      } else {
        line = candidate;
      }
    });
    if (line) lines.push(line);
  });
  return lines;
}

function applyGrain(ctx) {
  const grainCanvas = document.createElement("canvas");
  grainCanvas.width = 180;
  grainCanvas.height = 180;
  const grainCtx = grainCanvas.getContext("2d");
  const grain = grainCtx.createImageData(grainCanvas.width, grainCanvas.height);
  let seed = 94731;
  for (let i = 0; i < grain.data.length; i += 4) {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    const tone = (seed >>> 24) > 127 ? 255 : 0;
    grain.data[i] = tone;
    grain.data[i + 1] = tone;
    grain.data[i + 2] = tone;
    grain.data[i + 3] = 18 + ((seed >>> 16) % 18);
  }
  grainCtx.putImageData(grain, 0, 0);
  ctx.save();
  ctx.globalAlpha = 0.28;
  ctx.globalCompositeOperation = "soft-light";
  ctx.fillStyle = ctx.createPattern(grainCanvas, "repeat");
  ctx.fillRect(0, 0, 1080, 1080);
  ctx.restore();
}

function formatWeek(startAt, endAt) {
  const options = { day: "numeric", month: "short" };
  const start = new Date(startAt);
  const end = new Date(new Date(endAt).getTime() - 86400000);
  return `${start.toLocaleDateString("tr-TR", options)} — ${end.toLocaleDateString("tr-TR", options)}`.toLocaleUpperCase("tr-TR");
}

async function drawReport(report) {
  const ctx = els.canvas.getContext("2d");
  const movies = report.movies || [];
  const images = await Promise.all(movies.map((movie) => loadImage(posterUrl(movie.posterUrl))));
  const logo = await loadImage("images/app_logo.png");

  // Tasarım koordinatlarını 1080 × 1080 tutup gerçek PNG'yi iki kat
  // çözünürlükte üretir; tüm yazı ve şekiller daha keskin çıkar.
  ctx.setTransform(2, 0, 0, 2, 0, 0);
  ctx.clearRect(0, 0, 1080, 1080);
  ctx.fillStyle = "#080d0a";
  ctx.fillRect(0, 0, 1080, 1080);

  if (images[0]) {
    const backdrop = document.createElement("canvas");
    backdrop.width = 1080;
    backdrop.height = 700;
    const backdropCtx = backdrop.getContext("2d");

    backdropCtx.save();
    backdropCtx.filter = "blur(10px) saturate(75%)";
    coverImage(backdropCtx, images[0], -24, -24, 1128, 748);
    backdropCtx.restore();

    // Birinci filmin görselini merkezde görünür bırakıp bütün kenarlara
    // yaklaştıkça tamamen saydamlaştır.
    backdropCtx.globalCompositeOperation = "destination-in";
    const edgeFade = backdropCtx.createRadialGradient(730, 145, 70, 730, 145, 760);
    edgeFade.addColorStop(0, "rgba(255,255,255,.95)");
    edgeFade.addColorStop(0.38, "rgba(255,255,255,.68)");
    edgeFade.addColorStop(0.70, "rgba(255,255,255,.28)");
    edgeFade.addColorStop(1, "rgba(255,255,255,0)");
    backdropCtx.fillStyle = edgeFade;
    backdropCtx.fillRect(0, 0, backdrop.width, backdrop.height);

    // Alt sınırı görünür bir çizgi oluşturmadan uzun bir mesafede erit.
    const bottomFade = backdropCtx.createLinearGradient(0, 210, 0, backdrop.height);
    bottomFade.addColorStop(0, "rgba(255,255,255,1)");
    bottomFade.addColorStop(0.38, "rgba(255,255,255,.82)");
    bottomFade.addColorStop(0.72, "rgba(255,255,255,.30)");
    bottomFade.addColorStop(1, "rgba(255,255,255,0)");
    backdropCtx.fillStyle = bottomFade;
    backdropCtx.fillRect(0, 0, backdrop.width, backdrop.height);

    ctx.save();
    ctx.globalAlpha = 0.42;
    ctx.drawImage(backdrop, 0, 0);
    ctx.restore();
  }

  const shade = ctx.createLinearGradient(0, 0, 0, 650);
  shade.addColorStop(0, "rgba(8,13,10,.10)");
  shade.addColorStop(1, "#080d0a");
  ctx.fillStyle = shade;
  ctx.fillRect(0, 0, 1080, 700);

  const glow = ctx.createRadialGradient(940, 80, 0, 940, 80, 500);
  glow.addColorStop(0, "rgba(41,202,44,.30)");
  glow.addColorStop(1, "rgba(41,202,44,0)");
  ctx.fillStyle = glow;
  ctx.fillRect(400, 0, 680, 650);

  if (logo) {
    ctx.save();
    roundRect(ctx, 66, 58, 70, 70, 18);
    ctx.clip();
    coverImage(ctx, logo, 66, 58, 70, 70);
    ctx.restore();
  }
  ctx.fillStyle = "#ffffff";
  ctx.font = "900 28px Arial, Helvetica, sans-serif";
  ctx.fillText("Cinematch", 154, 91);
  ctx.fillStyle = "rgba(255,255,255,.56)";
  ctx.font = "500 17px Arial, Helvetica, sans-serif";
  ctx.fillText("TOPLULUĞUN SEÇİMİ", 154, 119);

  ctx.fillStyle = "#29ca2c";
  roundRect(ctx, 788, 65, 226, 46, 23);
  ctx.fill();
  ctx.fillStyle = "#071008";
  ctx.textAlign = "center";
  ctx.font = "900 16px Arial, Helvetica, sans-serif";
  ctx.fillText(formatWeek(report.startAt, report.endAt), 901, 95);
  ctx.textAlign = "left";

  ctx.fillStyle = "#ffffff";
  ctx.font = "900 70px Arial, Helvetica, sans-serif";
  ctx.fillText("BU HAFTANIN", 66, 224);
  ctx.font = "900 67px Arial, Helvetica, sans-serif";
  ctx.fillText("EN ÇOK İZLENEN", 66, 292);
  ctx.fillStyle = "#29ca2c";
  ctx.fillText("10 FİLMİ", 66, 370);

  const columnX = [66, 558];
  const startY = 432;
  const rowHeight = 120;
  const posterWidth = 72;
  const posterHeight = 102;

  movies.slice(0, 10).forEach((movie, index) => {
    const column = index < 5 ? 0 : 1;
    const row = index % 5;
    const x = columnX[column];
    const y = startY + row * rowHeight;
    const image = images[index];

    ctx.fillStyle = index === 0 ? "#29ca2c" : "rgba(255,255,255,.12)";
    ctx.beginPath();
    ctx.arc(x + 18, y + 51, 18, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = index === 0 ? "#071008" : "#ffffff";
    ctx.textAlign = "center";
    ctx.font = "900 18px Arial, Helvetica, sans-serif";
    ctx.fillText(String(index + 1), x + 18, y + 57);
    ctx.textAlign = "left";

    const featuredOffset = index === 0 ? 4 : 0;
    const itemPosterWidth = posterWidth + (index === 0 ? 8 : 0);
    const itemPosterHeight = posterHeight + (index === 0 ? 8 : 0);
    ctx.save();
    roundRect(ctx, x + 48 - featuredOffset, y - featuredOffset, itemPosterWidth, itemPosterHeight, 8);
    ctx.clip();
    ctx.fillStyle = "#202722";
    ctx.fillRect(x + 48 - featuredOffset, y - featuredOffset, itemPosterWidth, itemPosterHeight);
    if (image) {
      coverImage(ctx, image, x + 48 - featuredOffset, y - featuredOffset, itemPosterWidth, itemPosterHeight);
    }
    ctx.restore();

    const textX = x + 138 + (index === 0 ? 5 : 0);
    const maxText = 326 - (index === 0 ? 5 : 0);
    const fontSize = fitText(ctx, String(movie.title || "İsimsiz Film"), maxText, index === 0 ? 28 : 25);
    ctx.fillStyle = "#ffffff";
    ctx.font = `800 ${fontSize}px Arial, Helvetica, sans-serif`;
    ctx.fillText(truncateText(ctx, String(movie.title || "İsimsiz Film"), maxText), textX, y + 40);
    ctx.fillStyle = "rgba(255,255,255,.55)";
    ctx.font = "500 18px Arial, Helvetica, sans-serif";
    const meta = movie.year ? String(movie.year) : "";
    ctx.fillText(meta, textX, y + 70);
    ctx.fillStyle = "rgba(255,255,255,.10)";
    ctx.fillRect(textX, y + 91, maxText, 1);
  });

  ctx.fillStyle = "#29ca2c";
  ctx.beginPath();
  ctx.arc(72, 1041, 7, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "rgba(255,255,255,.58)";
  ctx.font = "500 18px Arial, Helvetica, sans-serif";
  ctx.fillText("Sıradaki filmini birlikte bul.", 92, 1048);
  ctx.fillStyle = "#ffffff";
  ctx.textAlign = "right";
  ctx.font = "900 20px Arial, Helvetica, sans-serif";
  ctx.fillText("cinematchsocial", 1014, 1048);
  ctx.textAlign = "left";

  // Çok hafif sinematik film greni. Sabit tohum sayesinde önizleme her
  // üretimde titreşmez ve doku yalnızca tasarıma derinlik katar.
  applyGrain(ctx);

  els.emptyPreview.classList.add("hidden");
  els.canvas.classList.remove("hidden");
}

async function drawPromo() {
  const [logo, dunePoster, interstellarPoster, oppenheimerPoster, laLaLandPoster, appStoreBadge] =
    await Promise.all([
      loadImage("images/app_logo.png"),
      loadImage("images/promo-posters/dune-part-two.jpg"),
      loadImage("images/promo-posters/interstellar.jpg"),
      loadImage("images/promo-posters/oppenheimer.jpg"),
      loadImage("images/promo-posters/la-la-land.jpg"),
      loadImage("images/download-on-app-store.svg"),
    ]);
  if (!logo) throw new Error("Cinematch logosu yüklenemedi.");

  const ctx = els.canvas.getContext("2d");
  ctx.setTransform(2, 0, 0, 2, 0, 0);
  ctx.clearRect(0, 0, 1080, 1080);
  const background = ctx.createLinearGradient(0, 0, 1080, 1080);
  background.addColorStop(0, "#111713");
  background.addColorStop(0.5, "#070b09");
  background.addColorStop(1, "#0d1710");
  ctx.fillStyle = background;
  ctx.fillRect(0, 0, 1080, 1080);

  // Logo: arkasında daire veya dekoratif halka yok.
  ctx.save();
  roundRect(ctx, 482, 42, 116, 116, 28);
  ctx.clip();
  coverImage(ctx, logo, 482, 42, 116, 116);
  ctx.restore();
  ctx.textAlign = "center";
  ctx.fillStyle = "#ffffff";
  ctx.font = "900 42px Arial, Helvetica, sans-serif";
  ctx.fillText("Cinematch", 540, 209);
  ctx.fillStyle = "rgba(255,255,255,.58)";
  ctx.font = "600 17px Arial, Helvetica, sans-serif";
  ctx.fillText("İzle, paylaş, keşfet ve tanış", 540, 239);
  ctx.textAlign = "left";

  function drawPoster(x, y, width, height, title, subtitle, colors, angle) {
    ctx.save();
    ctx.translate(x + width / 2, y + height / 2);
    ctx.rotate(angle);
    ctx.shadowColor = "rgba(0,0,0,.65)";
    ctx.shadowBlur = 28;
    ctx.shadowOffsetY = 14;
    roundRect(ctx, -width / 2, -height / 2, width, height, 14);
    ctx.clip();
    const posterGradient = ctx.createLinearGradient(-width / 2, -height / 2, width / 2, height / 2);
    posterGradient.addColorStop(0, colors[0]);
    posterGradient.addColorStop(1, colors[1]);
    ctx.fillStyle = posterGradient;
    ctx.fillRect(-width / 2, -height / 2, width, height);
    ctx.shadowColor = "transparent";

    ctx.globalAlpha = 0.42;
    ctx.fillStyle = colors[2];
    ctx.beginPath();
    ctx.arc(width * 0.18, -height * 0.12, width * 0.55, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;

    const posterShade = ctx.createLinearGradient(0, -height * 0.08, 0, height / 2);
    posterShade.addColorStop(0, "rgba(0,0,0,0)");
    posterShade.addColorStop(1, "rgba(0,0,0,.82)");
    ctx.fillStyle = posterShade;
    ctx.fillRect(-width / 2, -height / 2, width, height);
    ctx.textAlign = "center";
    ctx.fillStyle = "#ffffff";
    ctx.font = `900 ${Math.max(15, width * 0.13)}px Arial, Helvetica, sans-serif`;
    ctx.fillText(title, 0, height * 0.31);
    ctx.fillStyle = "rgba(255,255,255,.68)";
    ctx.font = `700 ${Math.max(8, width * 0.055)}px Arial, Helvetica, sans-serif`;
    ctx.fillText(subtitle, 0, height * 0.39);
    ctx.restore();
  }

  function drawPosterImage(image, x, y, width, height, angle) {
    if (!image) return;
    ctx.save();
    ctx.translate(x + width / 2, y + height / 2);
    ctx.rotate(angle);
    ctx.shadowColor = "rgba(0,0,0,.72)";
    ctx.shadowBlur = 30;
    ctx.shadowOffsetY = 15;
    roundRect(ctx, -width / 2, -height / 2, width, height, 14);
    ctx.clip();
    ctx.shadowColor = "transparent";
    coverImage(ctx, image, -width / 2, -height / 2, width, height);
    const posterFinish = ctx.createLinearGradient(0, -height / 2, 0, height / 2);
    posterFinish.addColorStop(0, "rgba(0,0,0,.02)");
    posterFinish.addColorStop(1, "rgba(0,0,0,.18)");
    ctx.fillStyle = posterFinish;
    ctx.fillRect(-width / 2, -height / 2, width, height);
    ctx.restore();
  }

  // Post kartının arkasından görünen sinematik poster şeridi.
  drawPosterImage(dunePoster, 25, 315, 190, 280, -0.085);
  drawPosterImage(interstellarPoster, 45, 595, 174, 256, 0.055);
  drawPosterImage(oppenheimerPoster, 865, 300, 188, 278, 0.075);
  drawPosterImage(laLaLandPoster, 865, 590, 176, 258, -0.05);

  // Uygulamadaki PostTile görsel dilini taşıyan örnek film postu.
  const cardX = 234;
  const cardY = 278;
  const cardW = 612;
  const cardH = 558;
  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,.72)";
  ctx.shadowBlur = 44;
  ctx.shadowOffsetY = 18;
  ctx.fillStyle = "#151a17";
  roundRect(ctx, cardX, cardY, cardW, cardH, 28);
  ctx.fill();
  ctx.restore();
  ctx.strokeStyle = "rgba(255,255,255,.10)";
  ctx.lineWidth = 1;
  roundRect(ctx, cardX, cardY, cardW, cardH, 28);
  ctx.stroke();

  // Post başlığı
  ctx.save();
  ctx.beginPath();
  ctx.arc(cardX + 47, cardY + 50, 25, 0, Math.PI * 2);
  ctx.clip();
  coverImage(ctx, logo, cardX + 22, cardY + 25, 50, 50);
  ctx.restore();
  ctx.fillStyle = "#ffffff";
  ctx.font = "800 18px Arial, Helvetica, sans-serif";
  ctx.fillText("sinefilruhu", cardX + 88, cardY + 45);
  ctx.fillStyle = "rgba(255,255,255,.48)";
  ctx.font = "500 13px Arial, Helvetica, sans-serif";
  ctx.fillText("2 dakika önce", cardX + 88, cardY + 67);
  ctx.fillStyle = "rgba(255,255,255,.55)";
  ctx.font = "800 25px Arial, Helvetica, sans-serif";
  ctx.textAlign = "right";
  ctx.fillText("•••", cardX + cardW - 25, cardY + 51);
  ctx.textAlign = "left";

  ctx.fillStyle = "#ffffff";
  ctx.font = "900 25px Arial, Helvetica, sans-serif";
  ctx.fillText("Dune: Part Two — Büyük ekran büyüsü", cardX + 28, cardY + 120);
  ctx.fillStyle = "rgba(255,255,255,.78)";
  ctx.font = "500 17px Arial, Helvetica, sans-serif";
  ctx.fillText("Görüntüleri, müziği ve atmosferiyle uzun zamandır", cardX + 28, cardY + 158);
  ctx.fillText("izlediğim en etkileyici bilim kurgu deneyimlerinden biri.", cardX + 28, cardY + 184);
  ctx.fillText("Paul’ün yolculuğu bu kez çok daha görkemli. ✨", cardX + 28, cardY + 210);

  ctx.fillStyle = "#ffc02e";
  ctx.font = "27px Arial, Helvetica, sans-serif";
  ctx.fillText("★★★★★", cardX + 28, cardY + 253);

  // PostTile içindeki film kartı
  const movieX = cardX + 28;
  const movieY = cardY + 278;
  const movieW = cardW - 56;
  const movieH = 112;
  ctx.fillStyle = "rgba(255,255,255,.055)";
  roundRect(ctx, movieX, movieY, movieW, movieH, 15);
  ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,.08)";
  roundRect(ctx, movieX, movieY, movieW, movieH, 15);
  ctx.stroke();
  if (dunePoster) {
    ctx.save();
    roundRect(ctx, movieX, movieY, 75, movieH, 15);
    ctx.clip();
    coverImage(ctx, dunePoster, movieX, movieY, 75, movieH);
    ctx.restore();
  } else {
    drawPoster(movieX, movieY, 75, movieH, "DUNE", "PART TWO", ["#c47635", "#20120c", "#ffd095"], 0);
  }
  ctx.fillStyle = "rgba(41,202,44,.13)";
  roundRect(ctx, movieX + 95, movieY + 18, 71, 24, 5);
  ctx.fill();
  ctx.fillStyle = "#49db4c";
  ctx.font = "900 11px Arial, Helvetica, sans-serif";
  ctx.fillText("İZLİYOR", movieX + 108, movieY + 34);
  ctx.fillStyle = "#ffffff";
  ctx.font = "800 19px Arial, Helvetica, sans-serif";
  ctx.fillText("Dune: Part Two", movieX + 95, movieY + 72);
  ctx.fillStyle = "rgba(255,255,255,.45)";
  ctx.font = "700 28px Arial, Helvetica, sans-serif";
  ctx.fillText("›", movieX + movieW - 31, movieY + 69);

  ctx.fillStyle = "#38c93b";
  ctx.font = "600 15px Arial, Helvetica, sans-serif";
  ctx.fillText("#bilimkurgu   #dune   #sinema", cardX + 28, cardY + 425);
  ctx.strokeStyle = "rgba(255,255,255,.08)";
  ctx.beginPath();
  ctx.moveTo(cardX + 28, cardY + 452);
  ctx.lineTo(cardX + cardW - 28, cardY + 452);
  ctx.stroke();

  // Beğeni, yorum ve paylaş aksiyonları
  ctx.fillStyle = "rgba(255,255,255,.60)";
  ctx.font = "26px Arial, Helvetica, sans-serif";
  ctx.fillText("♡", cardX + 31, cardY + 500);
  ctx.font = "700 15px Arial, Helvetica, sans-serif";
  ctx.fillText("248", cardX + 65, cardY + 498);
  ctx.strokeStyle = "rgba(255,255,255,.60)";
  ctx.lineWidth = 2;
  roundRect(ctx, cardX + 128, cardY + 478, 25, 20, 8);
  ctx.stroke();
  ctx.fillStyle = "rgba(255,255,255,.60)";
  ctx.fillText("32", cardX + 164, cardY + 498);
  ctx.textAlign = "right";
  ctx.font = "700 22px Arial, Helvetica, sans-serif";
  ctx.fillText("↗", cardX + cardW - 32, cardY + 500);
  ctx.textAlign = "left";

  // Mağaza rozetleri
  const playBadge = await loadImage("images/appstore.png");
  if (playBadge) {
    // Dosyanın şeffaf boşluklarını kırparak gerçek rozet bölümünü çizer.
    ctx.drawImage(playBadge, 42, 42, 562, 168, 214, 919, 316, 94);
  }
  if (appStoreBadge) {
    ctx.drawImage(appStoreBadge, 550, 914, 311, 104);
  }

  applyGrain(ctx);
  els.emptyPreview.classList.add("hidden");
  els.canvas.classList.remove("hidden");
}

function drawWrappedHeadline(ctx, text, centerX, startY, maxWidth, maxLines) {
  const words = String(text || "").trim().split(/\s+/).filter(Boolean);
  const lines = [];
  let line = "";
  words.forEach((word) => {
    const candidate = line ? `${line} ${word}` : word;
    if (ctx.measureText(candidate).width <= maxWidth || !line) {
      line = candidate;
    } else if (lines.length < maxLines - 1) {
      lines.push(line);
      line = word;
    } else {
      line = `${line} ${word}`;
    }
  });
  if (line) lines.push(line);
  const lineHeight = 82;
  lines.slice(0, maxLines).forEach((value, index) => {
    ctx.fillText(truncateText(ctx, value, maxWidth), centerX, startY + index * lineHeight);
  });
  return lines.length;
}

async function drawListPromo(headline, label, coverKey, uploadedCoverUrl = "") {
  const covers = {
    dune: "images/promo-posters/dune-part-two.jpg",
    interstellar: "images/promo-posters/interstellar.jpg",
    oppenheimer: "images/promo-posters/oppenheimer.jpg",
    lalaland: "images/promo-posters/la-la-land.jpg",
  };
  const [logo, cover] = await Promise.all([
    loadImage("images/app_logo.png"),
    loadImage(uploadedCoverUrl || covers[coverKey] || covers.dune),
  ]);
  if (!logo || !cover) throw new Error("Liste kapağı görselleri yüklenemedi.");

  const ctx = els.canvas.getContext("2d");
  ctx.setTransform(2, 0, 0, 2, 0, 0);
  ctx.clearRect(0, 0, 1080, 1080);
  ctx.fillStyle = "#080d0a";
  ctx.fillRect(0, 0, 1080, 1080);
  ctx.save();
  ctx.globalAlpha = 0.68;
  coverImage(ctx, cover, 0, 0, 1080, 1080);
  ctx.restore();

  // Custom list kartlarında kullanılan alttan koyulaşan kapak yaklaşımı.
  const cinematicShade = ctx.createLinearGradient(0, 0, 0, 1080);
  cinematicShade.addColorStop(0, "rgba(3,7,5,.18)");
  cinematicShade.addColorStop(0.42, "rgba(3,7,5,.06)");
  cinematicShade.addColorStop(0.68, "rgba(3,7,5,.48)");
  cinematicShade.addColorStop(1, "rgba(3,7,5,.96)");
  ctx.fillStyle = cinematicShade;
  ctx.fillRect(0, 0, 1080, 1080);

  const sideShade = ctx.createLinearGradient(0, 0, 1080, 0);
  sideShade.addColorStop(0, "rgba(0,0,0,.34)");
  sideShade.addColorStop(0.24, "rgba(0,0,0,0)");
  sideShade.addColorStop(0.76, "rgba(0,0,0,0)");
  sideShade.addColorStop(1, "rgba(0,0,0,.34)");
  ctx.fillStyle = sideShade;
  ctx.fillRect(0, 0, 1080, 1080);

  ctx.save();
  roundRect(ctx, 500, 52, 80, 80, 20);
  ctx.clip();
  coverImage(ctx, logo, 500, 52, 80, 80);
  ctx.restore();

  ctx.textAlign = "center";
  ctx.fillStyle = "rgba(255,255,255,.82)";
  const labelText = String(label || "CINEMATCH LİSTELERİ");
  const labelSize = fitText(ctx, labelText, 900, 22, 900);
  ctx.font = `900 ${labelSize}px Arial, Helvetica, sans-serif`;
  ctx.letterSpacing = "4px";
  ctx.fillText(truncateText(ctx, labelText, 900), 540, 764);
  ctx.letterSpacing = "0px";

  ctx.fillStyle = "#ffffff";
  ctx.font = "900 68px Arial, Helvetica, sans-serif";
  drawWrappedHeadline(
    ctx,
    headline || "Mutlaka izlemen gereken 10 bilim kurgu filmi",
    540,
    842,
    940,
    2
  );

  ctx.fillStyle = "#29ca2c";
  roundRect(ctx, 474, 1012, 132, 5, 3);
  ctx.fill();
  ctx.fillStyle = "rgba(255,255,255,.72)";
  ctx.font = "800 19px Arial, Helvetica, sans-serif";
  ctx.fillText("cinematchsocial", 540, 1055);
  ctx.textAlign = "left";

  applyGrain(ctx);
  els.emptyPreview.classList.add("hidden");
  els.canvas.classList.remove("hidden");
}

function parseTmdbMovieLinks(value) {
  const lines = String(value || "").split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  const ids = [];
  const invalid = [];
  lines.forEach((line) => {
    const linkMatch = line.match(/themoviedb\.org\/movie\/(\d+)/i);
    const bareMatch = line.match(/^(\d+)$/);
    const id = Number((linkMatch && linkMatch[1]) || (bareMatch && bareMatch[1]));
    if (Number.isInteger(id) && id > 0) {
      if (!ids.includes(id)) ids.push(id);
    } else {
      invalid.push(line);
    }
  });
  return { ids, invalid };
}

async function drawMovieGrid(movies) {
  const ctx = els.canvas.getContext("2d");
  const logo = await loadImage("images/app_logo.png");
  const posters = await Promise.all(
    movies.map((movie) => loadImage(posterUrl(movie.posterUrl)))
  );
  ctx.setTransform(2, 0, 0, 2, 0, 0);
  ctx.clearRect(0, 0, 1080, 1080);

  const background = ctx.createLinearGradient(0, 0, 1080, 1080);
  background.addColorStop(0, "#101713");
  background.addColorStop(0.48, "#070c09");
  background.addColorStop(1, "#0c1510");
  ctx.fillStyle = background;
  ctx.fillRect(0, 0, 1080, 1080);
  const greenGlow = ctx.createRadialGradient(980, 40, 0, 980, 40, 620);
  greenGlow.addColorStop(0, "rgba(41,202,44,.16)");
  greenGlow.addColorStop(1, "rgba(41,202,44,0)");
  ctx.fillStyle = greenGlow;
  ctx.fillRect(340, 0, 740, 720);

  if (logo) {
    ctx.save();
    roundRect(ctx, 44, 36, 68, 68, 17);
    ctx.clip();
    coverImage(ctx, logo, 44, 36, 68, 68);
    ctx.restore();
  }

  const count = movies.length;
  const columns = count === 1 ? 1 : Math.ceil(Math.sqrt(count * 1.25));
  const rows = Math.ceil(count / columns);
  const areaX = 44;
  const areaY = 134;
  const areaWidth = 992;
  const areaHeight = 836;
  const gap = Math.max(10, Math.min(22, 28 - Math.max(columns, rows) * 2));
  const cellWidth = (areaWidth - (columns - 1) * gap) / columns;
  const cellHeight = (areaHeight - (rows - 1) * gap) / rows;
  const labelHeight = Math.max(34, Math.min(54, cellHeight * 0.22));
  const posterHeight = Math.min(cellHeight - labelHeight, cellWidth * 1.5);
  const posterWidth = posterHeight * (2 / 3);

  movies.forEach((movie, index) => {
    const row = Math.floor(index / columns);
    const column = index % columns;
    const itemsInRow = row === rows - 1 && count % columns
      ? count % columns
      : columns;
    const rowWidth = itemsInRow * cellWidth + (itemsInRow - 1) * gap;
    const rowStartX = (1080 - rowWidth) / 2;
    const cellX = rowStartX + column * (cellWidth + gap);
    const cellY = areaY + row * (cellHeight + gap);
    const imageX = cellX + (cellWidth - posterWidth) / 2;
    const imageY = cellY;

    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,.55)";
    ctx.shadowBlur = Math.max(8, posterWidth * 0.09);
    ctx.shadowOffsetY = 8;
    roundRect(ctx, imageX, imageY, posterWidth, posterHeight, Math.max(5, posterWidth * 0.045));
    ctx.clip();
    ctx.fillStyle = "#1a211d";
    ctx.fillRect(imageX, imageY, posterWidth, posterHeight);
    if (posters[index]) {
      coverImage(ctx, posters[index], imageX, imageY, posterWidth, posterHeight);
    } else {
      ctx.fillStyle = "rgba(255,255,255,.25)";
      ctx.textAlign = "center";
      ctx.font = `700 ${Math.max(12, posterWidth * 0.12)}px Arial, Helvetica, sans-serif`;
      ctx.fillText("AFİŞ YOK", imageX + posterWidth / 2, imageY + posterHeight / 2);
    }
    ctx.restore();

    const labelY = imageY + posterHeight + Math.max(8, labelHeight * 0.18);
    ctx.textAlign = "center";
    ctx.fillStyle = "#ffffff";
    const titleSize = Math.max(11, Math.min(19, cellWidth * 0.105));
    ctx.font = `800 ${titleSize}px Arial, Helvetica, sans-serif`;
    ctx.fillText(
      truncateText(ctx, String(movie.title || "İsimsiz Film"), cellWidth - 4),
      cellX + cellWidth / 2,
      labelY + titleSize
    );
    if (movie.year) {
      ctx.fillStyle = "rgba(255,255,255,.48)";
      ctx.font = `600 ${Math.max(10, titleSize * 0.72)}px Arial, Helvetica, sans-serif`;
      ctx.fillText(String(movie.year), cellX + cellWidth / 2, labelY + titleSize + Math.max(15, titleSize));
    }
    ctx.textAlign = "left";
  });

  ctx.fillStyle = "#ffffff";
  ctx.textAlign = "right";
  ctx.font = "900 18px Arial, Helvetica, sans-serif";
  ctx.fillText("cinematchsocial", 1034, 1040);
  ctx.textAlign = "left";
  applyGrain(ctx);
  els.emptyPreview.classList.add("hidden");
  els.canvas.classList.remove("hidden");
}

function normalizeRating(value) {
  const rating = Number(value);
  if (!Number.isFinite(rating)) return 0;
  return Math.max(0, Math.min(10, rating));
}

async function drawRatingRanking(sourceMovies, headline) {
  const movies = [...sourceMovies]
    .map((movie) => ({ ...movie, voteAverage: normalizeRating(movie.voteAverage) }))
    .sort((a, b) =>
      b.voteAverage - a.voteAverage ||
      String(a.title || "").localeCompare(String(b.title || ""), "tr")
    )
    .slice(0, 10);
  const [logo, ...posters] = await Promise.all([
    loadImage("images/app_logo.png"),
    ...movies.map((movie) => loadImage(posterUrl(movie.heroPosterUrl || movie.posterUrl))),
  ]);
  const ctx = els.canvas.getContext("2d");
  ctx.setTransform(2, 0, 0, 2, 0, 0);
  ctx.clearRect(0, 0, 1080, 1080);

  const background = ctx.createLinearGradient(0, 0, 1080, 1080);
  background.addColorStop(0, "#101713");
  background.addColorStop(0.48, "#070c09");
  background.addColorStop(1, "#0a130d");
  ctx.fillStyle = background;
  ctx.fillRect(0, 0, 1080, 1080);

  const greenGlow = ctx.createRadialGradient(940, 120, 30, 940, 120, 720);
  greenGlow.addColorStop(0, "rgba(41,202,44,.25)");
  greenGlow.addColorStop(0.48, "rgba(27,128,40,.08)");
  greenGlow.addColorStop(1, "rgba(41,202,44,0)");
  ctx.fillStyle = greenGlow;
  ctx.fillRect(300, 0, 780, 900);

  // Lider filmin kapağı sağda kalır ve listenin bulunduğu sol tarafa doğru
  // tamamen saydamlaşır.
  if (posters[0]) {
    const hero = document.createElement("canvas");
    hero.width = 500;
    hero.height = 900;
    const heroCtx = hero.getContext("2d");
    coverImage(heroCtx, posters[0], 0, 0, hero.width, hero.height);
    heroCtx.globalCompositeOperation = "destination-in";
    const horizontalFade = heroCtx.createLinearGradient(0, 0, hero.width, 0);
    horizontalFade.addColorStop(0, "rgba(255,255,255,0)");
    horizontalFade.addColorStop(0.36, "rgba(255,255,255,.08)");
    horizontalFade.addColorStop(0.68, "rgba(255,255,255,.58)");
    horizontalFade.addColorStop(1, "rgba(255,255,255,.96)");
    heroCtx.fillStyle = horizontalFade;
    heroCtx.fillRect(0, 0, hero.width, hero.height);

    const verticalFade = heroCtx.createLinearGradient(0, 0, 0, hero.height);
    verticalFade.addColorStop(0, "rgba(255,255,255,0)");
    verticalFade.addColorStop(0.12, "rgba(255,255,255,.88)");
    verticalFade.addColorStop(0.74, "rgba(255,255,255,.88)");
    verticalFade.addColorStop(1, "rgba(255,255,255,0)");
    heroCtx.fillStyle = verticalFade;
    heroCtx.fillRect(0, 0, hero.width, hero.height);

    ctx.save();
    ctx.globalAlpha = 0.52;
    ctx.drawImage(hero, 580, 110);
    ctx.restore();
  }

  // Barların arkasında ayrı bir siyah kutu oluşturmak yerine bütün tuvale
  // yayılan bir okunabilirlik geçişi kullan. Böylece hiçbir kenarda dikdörtgen
  // sınırı görünmez ve lider kapağı arka planla doğal biçimde birleşir.
  const readabilityShade = ctx.createLinearGradient(0, 0, 1080, 0);
  readabilityShade.addColorStop(0, "rgba(4,9,6,.82)");
  readabilityShade.addColorStop(0.54, "rgba(4,9,6,.62)");
  readabilityShade.addColorStop(0.78, "rgba(4,9,6,.18)");
  readabilityShade.addColorStop(1, "rgba(4,9,6,0)");
  ctx.fillStyle = readabilityShade;
  ctx.fillRect(0, 0, 1080, 1080);

  if (logo) {
    ctx.save();
    roundRect(ctx, 56, 38, 68, 68, 17);
    ctx.clip();
    coverImage(ctx, logo, 56, 38, 68, 68);
    ctx.restore();
  }

  const headlineText = String(headline || "").trim();
  if (headlineText) {
    const headlineSize = fitText(ctx, headlineText, 860, 25, 900);
    ctx.fillStyle = "#ffffff";
    ctx.font = `900 ${headlineSize}px Arial, Helvetica, sans-serif`;
    ctx.fillText(truncateText(ctx, headlineText, 860), 146, 81);
  }

  const chartTop = 128;
  const chartBottom = 1010;
  const rowHeight = Math.min(148, (chartBottom - chartTop) / movies.length);
  const chartHeight = rowHeight * movies.length;
  const rowStartY = chartTop + ((chartBottom - chartTop) - chartHeight) / 2;
  const posterHeight = Math.min(126, rowHeight - 6);
  const posterWidth = Math.min(94, posterHeight * 0.78);
  const posterX = 56;
  const barX = posterX + posterWidth - 3;
  const maxBarWidth = 1024 - barX;
  const barHeight = posterHeight - 10;
  const highestRating = movies[0].voteAverage;
  const lowestRating = movies[movies.length - 1].voteAverage;
  const ratingSpread = highestRating - lowestRating;
  const gapWeight = ratingSpread <= 0.75
    ? 0.035
    : ratingSpread <= 1.5
      ? 0.05
      : 0.065;

  movies.forEach((movie, index) => {
    const rowY = rowStartY + index * rowHeight + (rowHeight - posterHeight) / 2;
    const rating = movie.voteAverage;
    const barY = rowY + (posterHeight - barHeight) / 2;

    // Uzunlukları seçkinin liderine olan puan farkından üret. Küçük puan
    // farkları küçük görsel farklara dönüşür; geniş puan aralıklarında ölçek
    // kendiliğinden açılır. Eşit puanlar daima eşit uzunlukta kalır.
    const scoreGap = highestRating - rating;
    const fillRatio = Math.max(0.55, 1 - scoreGap * gapWeight);
    const fillWidth = maxBarWidth * fillRatio;

    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,.34)";
    ctx.shadowBlur = 12;
    ctx.shadowOffsetY = 4;
    const absoluteGreen = rating / 10;
    const relativeGreen = ratingSpread > 0
      ? (rating - lowestRating) / ratingSpread
      : absoluteGreen;
    const greenStrength = ratingSpread > 0
      ? absoluteGreen * 0.3 + relativeGreen * 0.7
      : absoluteGreen;
    const startSaturation = 24 + greenStrength * 58;
    const startLightness = 24 + greenStrength * 14;
    const endSaturation = 20 + greenStrength * 56;
    const endLightness = 18 + greenStrength * 10;
    const barGradient = ctx.createLinearGradient(barX, 0, barX + fillWidth, 0);
    barGradient.addColorStop(
      0,
      `hsl(133, ${startSaturation}%, ${startLightness}%)`
    );
    barGradient.addColorStop(
      1,
      `hsl(132, ${endSaturation}%, ${endLightness}%)`
    );
    ctx.fillStyle = barGradient;
    roundRect(ctx, barX, barY, fillWidth, barHeight, 8);
    ctx.fill();
    ctx.restore();

    const title = String(movie.title || "İsimsiz Film");
    const year = movie.year ? String(movie.year) : "";
    const textX = barX + 28;
    const textY = barY + barHeight / 2;
    const titleSize = Math.max(19, Math.min(27, barHeight * 0.4));
    const yearSize = Math.max(16, titleSize * 0.76);
    const ratingSize = Math.max(21, titleSize + 2);
    const ratingText = rating.toFixed(1);
    const ratingRight = barX + fillWidth - 20;

    ctx.font = `900 ${ratingSize}px Arial, Helvetica, sans-serif`;
    const ratingWidth = ctx.measureText(ratingText).width;
    ctx.font = `500 ${yearSize}px Arial, Helvetica, sans-serif`;
    const yearWidth = year ? ctx.measureText(year).width + 13 : 0;
    ctx.font = `900 ${titleSize}px Arial, Helvetica, sans-serif`;
    const titleMaxWidth = Math.max(
      60,
      ratingRight - ratingWidth - 30 - yearWidth - textX
    );
    const visibleTitle = truncateText(ctx, title, titleMaxWidth);

    ctx.fillStyle = "#ffffff";
    ctx.textAlign = "left";
    ctx.fillText(visibleTitle, textX, textY + titleSize * 0.34);
    const titleWidth = ctx.measureText(visibleTitle).width;
    if (year) {
      ctx.fillStyle = "rgba(255,255,255,.58)";
      ctx.font = `500 ${yearSize}px Arial, Helvetica, sans-serif`;
      ctx.fillText(year, textX + titleWidth + 13, textY + yearSize * 0.34);
    }

    ctx.fillStyle = "#ffffff";
    ctx.textAlign = "right";
    ctx.font = `900 ${ratingSize}px Arial, Helvetica, sans-serif`;
    ctx.fillText(ratingText, ratingRight, textY + ratingSize * 0.34);
    ctx.textAlign = "left";

    ctx.save();
    ctx.shadowColor = "rgba(0,0,0,.52)";
    ctx.shadowBlur = 10;
    ctx.shadowOffsetY = 4;
    roundRect(ctx, posterX, rowY, posterWidth, posterHeight, 7);
    ctx.clip();
    ctx.fillStyle = "#1b231e";
    ctx.fillRect(posterX, rowY, posterWidth, posterHeight);
    if (posters[index]) {
      coverImage(ctx, posters[index], posterX, rowY, posterWidth, posterHeight);
    }
    ctx.restore();
  });

  ctx.fillStyle = "#ffffff";
  ctx.textAlign = "right";
  ctx.font = "900 19px Arial, Helvetica, sans-serif";
  ctx.fillText("cinematchsocial", 1024, 1044);
  ctx.textAlign = "left";

  applyGrain(ctx);
  els.emptyPreview.classList.add("hidden");
  els.canvas.classList.remove("hidden");
}

async function drawCineheard(quote, source) {
  const ctx = els.canvas.getContext("2d");
  const logo = await loadImage("images/app_logo.png");
  ctx.setTransform(2, 0, 0, 2, 0, 0);
  ctx.clearRect(0, 0, 1080, 1080);

  const background = ctx.createLinearGradient(0, 0, 1080, 1080);
  background.addColorStop(0, "#111713");
  background.addColorStop(0.52, "#070c09");
  background.addColorStop(1, "#0c1710");
  ctx.fillStyle = background;
  ctx.fillRect(0, 0, 1080, 1080);

  const glow = ctx.createRadialGradient(860, 180, 20, 860, 180, 700);
  glow.addColorStop(0, "rgba(41,202,44,.19)");
  glow.addColorStop(0.52, "rgba(24,115,42,.07)");
  glow.addColorStop(1, "rgba(0,0,0,0)");
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, 1080, 900);

  if (logo) {
    ctx.save();
    roundRect(ctx, 501, 52, 78, 78, 19);
    ctx.clip();
    coverImage(ctx, logo, 501, 52, 78, 78);
    ctx.restore();
  }
  ctx.textAlign = "center";
  ctx.fillStyle = "rgba(255,255,255,.68)";
  ctx.font = "800 14px Arial, Helvetica, sans-serif";
  ctx.letterSpacing = "3px";
  ctx.fillText("CINEHEARD", 540, 160);
  ctx.letterSpacing = "0px";

  ctx.fillStyle = "rgba(41,202,44,.13)";
  ctx.font = "900 230px Georgia, 'Times New Roman', serif";
  ctx.fillText("“", 180, 440);

  let fontSize = 70;
  let lines = [];
  do {
    ctx.font = `900 ${fontSize}px Arial, Helvetica, sans-serif`;
    lines = wrapTextLines(ctx, quote, 810);
    if (lines.length <= 5 && lines.length * fontSize * 1.12 <= 390) break;
    fontSize -= 2;
  } while (fontSize > 34);

  const lineHeight = fontSize * 1.12;
  const quoteHeight = lines.length * lineHeight;
  const quoteStartY = 515 - quoteHeight / 2;
  ctx.fillStyle = "#f7f8f7";
  ctx.font = `900 ${fontSize}px Arial, Helvetica, sans-serif`;
  lines.forEach((line, index) => {
    ctx.fillText(line, 540, quoteStartY + (index + 1) * lineHeight);
  });

  const sourceY = quoteStartY + quoteHeight + 66;
  ctx.fillStyle = "#29ca2c";
  ctx.fillRect(510, sourceY - 8, 60, 3);
  ctx.fillStyle = "rgba(255,255,255,.66)";
  ctx.font = "italic 500 24px Georgia, 'Times New Roman', serif";
  ctx.fillText(`— ${source}`, 540, sourceY + 38);

  ctx.textAlign = "right";
  ctx.fillStyle = "#ffffff";
  ctx.font = "900 18px Arial, Helvetica, sans-serif";
  ctx.fillText("cinematchsocial", 1034, 1040);
  ctx.textAlign = "left";
  applyGrain(ctx);
  els.emptyPreview.classList.add("hidden");
  els.canvas.classList.remove("hidden");
}

els.generateButton.addEventListener("click", async () => {
  if (!authReady) {
    setMessage(els.statusMessage, "Admin oturumu hazırlanıyor, tekrar deneyin.", "error");
    return;
  }
  els.generateButton.disabled = true;
  els.downloadButton.disabled = true;
  setMessage(els.statusMessage, "Haftalık liste verileri hazırlanıyor…");
  try {
    const selected = els.weekDate.value ? new Date(`${els.weekDate.value}T12:00:00+03:00`) : new Date();
    const callable = functions.httpsCallable("generateWeeklySocialReport");
    const response = await callable({ weekEnd: selected.toISOString() });
    const report = response.data || {};
    if (!report.movies || !report.movies.length) {
      throw new Error("Seçilen haftada profillere eklenen film bulunamadı.");
    }
    setMessage(els.statusMessage, "Posterler yükleniyor…");
    await drawReport(report);
    currentWeekId = report.weekId || els.weekDate.value;
    currentExportName = `cinematch-top10-${currentWeekId || "haftalik"}`;
    els.downloadButton.disabled = false;
    setMessage(els.statusMessage, `${report.movies.length} filmle görsel hazır.`, "success");
  } catch (error) {
    setMessage(els.statusMessage, error.message || String(error), "error");
  } finally {
    els.generateButton.disabled = false;
  }
});

els.generatePromoButton.addEventListener("click", async () => {
  els.generatePromoButton.disabled = true;
  els.downloadButton.disabled = true;
  setMessage(els.statusMessage, "Uygulama tanıtım görseli hazırlanıyor…");
  try {
    await drawPromo();
    currentExportName = "cinematch-sinefil-arsivi";
    els.downloadButton.disabled = false;
    setMessage(els.statusMessage, "Uygulama tanıtım görseli hazır.", "success");
  } catch (error) {
    setMessage(els.statusMessage, error.message || String(error), "error");
  } finally {
    els.generatePromoButton.disabled = false;
  }
});

els.generateListButton.addEventListener("click", async () => {
  const headline = els.listHeadline.value.trim();
  if (!headline) {
    setMessage(els.statusMessage, "Liste başlığını yazın.", "error");
    els.listHeadline.focus();
    return;
  }
  els.generateListButton.disabled = true;
  els.downloadButton.disabled = true;
  setMessage(els.statusMessage, "Cinematch liste kapağı hazırlanıyor…");
  let uploadedCoverUrl = "";
  try {
    const uploadedFile = els.listCoverUpload.files && els.listCoverUpload.files[0];
    if (uploadedFile) {
      if (!uploadedFile.type.startsWith("image/")) {
        throw new Error("Lütfen geçerli bir görsel dosyası seçin.");
      }
      uploadedCoverUrl = URL.createObjectURL(uploadedFile);
    }
    await drawListPromo(
      headline,
      els.listLabel.value.trim() || "CINEMATCH LİSTELERİ",
      els.listCover.value,
      uploadedCoverUrl
    );
    currentExportName = "cinematch-listesi";
    els.downloadButton.disabled = false;
    setMessage(els.statusMessage, "Liste kapağı hazır.", "success");
  } catch (error) {
    setMessage(els.statusMessage, error.message || String(error), "error");
  } finally {
    if (uploadedCoverUrl) URL.revokeObjectURL(uploadedCoverUrl);
    els.generateListButton.disabled = false;
  }
});

els.generateGridButton.addEventListener("click", async () => {
  if (!authReady) {
    setMessage(els.statusMessage, "Admin oturumu hazırlanıyor, tekrar deneyin.", "error");
    return;
  }
  const parsed = parseTmdbMovieLinks(els.gridMovieLinks.value);
  if (parsed.invalid.length) {
    setMessage(
      els.statusMessage,
      `${parsed.invalid.length} satır geçerli bir TMDB film linki değil.`,
      "error"
    );
    return;
  }
  if (!parsed.ids.length) {
    setMessage(els.statusMessage, "En az bir TMDB film linki ekleyin.", "error");
    els.gridMovieLinks.focus();
    return;
  }
  if (parsed.ids.length > 36) {
    setMessage(els.statusMessage, "Tek görselde en fazla 36 film kullanılabilir.", "error");
    return;
  }

  els.generateGridButton.disabled = true;
  els.downloadButton.disabled = true;
  setMessage(els.statusMessage, `${parsed.ids.length} filmin bilgileri TMDB’den alınıyor…`);
  try {
    const callable = functions.httpsCallable("getSocialGridMovies");
    const response = await callable({ ids: parsed.ids });
    const result = response.data || {};
    const movies = Array.isArray(result.movies) ? result.movies : [];
    if (!movies.length) throw new Error("TMDB’den film bilgisi alınamadı.");
    setMessage(els.statusMessage, "Posterler yükleniyor ve ızgara hesaplanıyor…");
    await drawMovieGrid(movies);
    currentExportName = "cinematch-film-listesi";
    els.downloadButton.disabled = false;
    const missingCount = Array.isArray(result.missingIds) ? result.missingIds.length : 0;
    setMessage(
      els.statusMessage,
      missingCount
        ? `${movies.length} filmle görsel hazır; ${missingCount} film bulunamadı.`
        : `${movies.length} filmle görsel hazır.`,
      "success"
    );
  } catch (error) {
    setMessage(els.statusMessage, error.message || String(error), "error");
  } finally {
    els.generateGridButton.disabled = false;
  }
});

els.generateRatingButton.addEventListener("click", async () => {
  if (!authReady) {
    setMessage(els.statusMessage, "Admin oturumu hazırlanıyor, tekrar deneyin.", "error");
    return;
  }
  const parsed = parseTmdbMovieLinks(els.ratingMovieLinks.value);
  if (parsed.invalid.length) {
    setMessage(
      els.statusMessage,
      `${parsed.invalid.length} satır geçerli bir TMDB film linki değil.`,
      "error"
    );
    return;
  }
  if (!parsed.ids.length) {
    setMessage(els.statusMessage, "En az bir TMDB film linki ekleyin.", "error");
    els.ratingMovieLinks.focus();
    return;
  }
  if (parsed.ids.length > 10) {
    setMessage(els.statusMessage, "Puan sıralamasına en fazla 10 film ekleyebilirsiniz.", "error");
    return;
  }

  els.generateRatingButton.disabled = true;
  els.downloadButton.disabled = true;
  setMessage(els.statusMessage, `${parsed.ids.length} filmin TMDB puanları alınıyor…`);
  try {
    const callable = functions.httpsCallable("getSocialGridMovies");
    const response = await callable({ ids: parsed.ids });
    const result = response.data || {};
    const movies = Array.isArray(result.movies) ? result.movies : [];
    if (!movies.length) throw new Error("TMDB’den film bilgisi alınamadı.");
    if (!movies.some((movie) => Number.isFinite(Number(movie.voteAverage)))) {
      throw new Error("TMDB puan bilgisi alınamadı.");
    }
    setMessage(els.statusMessage, "Filmler puana göre sıralanıyor ve görsel hazırlanıyor…");
    await drawRatingRanking(movies, els.ratingHeadline.value);
    currentExportName = "cinematch-tmdb-puan-siralamasi";
    els.downloadButton.disabled = false;
    const missingCount = Array.isArray(result.missingIds) ? result.missingIds.length : 0;
    setMessage(
      els.statusMessage,
      missingCount
        ? `${movies.length} filmle sıralama hazır; ${missingCount} film bulunamadı.`
        : `${movies.length} filmle puan sıralaması hazır.`,
      "success"
    );
  } catch (error) {
    setMessage(els.statusMessage, error.message || String(error), "error");
  } finally {
    els.generateRatingButton.disabled = false;
  }
});

els.generateCineheardButton.addEventListener("click", async () => {
  const quote = els.cineheardQuote.value.trim();
  const source = els.cineheardSource.value.trim();
  if (!quote || !source) {
    setMessage(els.statusMessage, "Sözü ve söyleyen/kaynak bilgisini yazın.", "error");
    (!quote ? els.cineheardQuote : els.cineheardSource).focus();
    return;
  }
  els.generateCineheardButton.disabled = true;
  els.downloadButton.disabled = true;
  setMessage(els.statusMessage, "Cineheard görseli hazırlanıyor…");
  try {
    await drawCineheard(quote, source);
    currentExportName = "cinematch-cineheard";
    els.downloadButton.disabled = false;
    setMessage(els.statusMessage, "Cineheard görseli hazır.", "success");
  } catch (error) {
    setMessage(els.statusMessage, error.message || String(error), "error");
  } finally {
    els.generateCineheardButton.disabled = false;
  }
});

els.downloadButton.addEventListener("click", () => {
  const link = document.createElement("a");
  link.download = `${currentExportName}.png`;
  link.href = els.canvas.toDataURL("image/png");
  link.click();
});
