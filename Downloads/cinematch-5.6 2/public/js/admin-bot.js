// Firebase başlatma, oturum kalıcılığı ve yetki önbelleği admin-shared.js
// içinde ortaklaştırıldı (bkz. js/admin-shared.js).
const { auth, functions } = CineAdmin;
const authPersistenceReady = CineAdmin.persistenceReady;

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
  refreshButton: document.getElementById("refreshButton"),
  overviewReportDays: document.getElementById("overviewReportDays"),
  overviewCsvButton: document.getElementById("overviewCsvButton"),
  outcomesCsvButton: document.getElementById("outcomesCsvButton"),
  performanceReportDays: document.getElementById("performanceReportDays"),
  performanceCsvButton: document.getElementById("performanceCsvButton"),
  grafanaDashboardLink: document.getElementById("grafanaDashboardLink"),
  monitoringGrafanaStatus: document.getElementById("monitoringGrafanaStatus"),
  monitoringMetricsStatus: document.getElementById("monitoringMetricsStatus"),
  monitoringLogsStatus: document.getElementById("monitoringLogsStatus"),
  monitoringEnvironment: document.getElementById("monitoringEnvironment"),
  monitoringSetupNote: document.getElementById("monitoringSetupNote"),
  currentUserLabel: document.getElementById("currentUserLabel"),
  mainTitle: document.getElementById("mainTitle"),
  globalMessage: document.getElementById("globalMessage"),

  kpiSessions: document.getElementById("kpiSessions"),
  kpiMessages: document.getElementById("kpiMessages"),
  kpiTools: document.getElementById("kpiTools"),
  kpiRating: document.getElementById("kpiRating"),

  sessionSearch: document.getElementById("sessionSearch"),
  sessionCount: document.getElementById("sessionCount"),
  sessionList: document.getElementById("sessionList"),
  sessionPager: document.getElementById("sessionPager"),

  tabButtons: document.querySelectorAll(".tab-btn"),
  tabPanels: {
    overview: document.getElementById("tab-overview"),
    conversation: document.getElementById("tab-conversation"),
    tools: document.getElementById("tab-tools"),
    performance: document.getElementById("tab-performance"),
    monitoring: document.getElementById("tab-monitoring"),
  },

  ovSessions: document.getElementById("ovSessions"),
  ovActive: document.getElementById("ovActive"),
  ovMessages: document.getElementById("ovMessages"),
  ovUsers: document.getElementById("ovUsers"),
  ovTools: document.getElementById("ovTools"),
  ovToolSuccess: document.getElementById("ovToolSuccess"),
  ovAvgRating: document.getElementById("ovAvgRating"),
  ovEvalCount: document.getElementById("ovEvalCount"),
  ovClassified: document.getElementById("ovClassified"),
  ovSuccessRate: document.getElementById("ovSuccessRate"),
  ovFallbackRate: document.getElementById("ovFallbackRate"),
  ovTechnicalRate: document.getElementById("ovTechnicalRate"),
  topMoviesTable: document.querySelector("#topMoviesTable tbody"),

  conversationEmpty: document.getElementById("conversationEmpty"),
  conversationContent: document.getElementById("conversationContent"),
  sessionMeta: document.getElementById("sessionMeta"),
  sessionSummary: document.getElementById("sessionSummary"),
  sessionIntentBreakdown: document.getElementById("sessionIntentBreakdown"),
  sessionOutcomeBreakdown: document.getElementById("sessionOutcomeBreakdown"),
  sessionClassificationNote: document.getElementById("sessionClassificationNote"),
  sessionPerfSummaryGrid: document.getElementById("sessionPerfSummaryGrid"),
  sessionPerfMetricsTable: document.querySelector("#sessionPerfMetricsTable tbody"),
  voiceRecordingsList: document.getElementById("voiceRecordingsList"),
  voiceAiEvaluations: document.getElementById("voiceAiEvaluations"),
  transcriptList: document.getElementById("transcriptList"),
  sessionToolsTable: document.querySelector("#sessionToolsTable tbody"),
  sessionToolsEmpty: document.getElementById("sessionToolsEmpty"),
  evaluateForm: document.getElementById("evaluateForm"),
  evalRating: document.getElementById("evalRating"),
  evalNote: document.getElementById("evalNote"),
  evalMessage: document.getElementById("evalMessage"),
  evaluationsTable: document.querySelector("#evaluationsTable tbody"),

  toolCallsTable: document.querySelector("#toolCallsTable tbody"),
  toolCallsPager: document.getElementById("toolCallsPager"),

  perfSummaryGrid: document.getElementById("perfSummaryGrid"),
  perfMetricsTable: document.querySelector("#perfMetricsTable tbody"),
  perfPager: document.getElementById("perfPager"),
};

// Backend erişim bilgisi (getBotAdminAccess'ten alınır, sadece bellekte tutulur)
let botAccess = null; // { baseUrl, key }

let sessions = [];
let sessionOffset = 0;
const SESSION_PAGE_SIZE = 20;
let activeSessionId = null;

let toolCallsOffset = 0;
const TOOL_PAGE_SIZE = 25;

const { setMessage, escapeHtml, isPermissionError } = CineAdmin;

const INTENT_LABELS = Object.freeze({
  film_onerisi_istendi: "Film önerisi",
  kategoriye_gore_film_arama: "Kategoriye göre film",
  oyuncuya_gore_film_arama: "Oyuncuya göre film",
  oyuncu_bilgisi_soruldu: "Oyuncu bilgisi",
  yonetmene_gore_film_arama: "Yönetmene göre film",
  yonetmen_bilgisi_soruldu: "Yönetmen bilgisi",
  film_bilgisi_soruldu: "Film bilgisi",
  cinematch_destegi_istendi: "CineMatch desteği",
  gorsel_analizi_istendi: "Görsel analizi",
  sinema_sohbeti: "Sinema sohbeti",
  selamlasma: "Selamlaşma",
  alakasiz_sohbet: "Alakasız sohbet",
  anlasilamayan_istek: "Anlaşılamayan istek",
});

const OUTCOME_LABELS = Object.freeze({
  islem_basarili: "İşlem başarılı",
  anlasilamadi_fallback: "Anlaşılamadı / fallback",
  teknik_hata: "Teknik hata",
  kismi_basarili: "Kısmi başarılı",
  veri_bulunamadi: "Veri bulunamadı",
  kapsam_disi_yonlendirildi: "Kapsam dışı yönlendirildi",
});

const INTENT_CHART_COLORS = [
  "#18a63a", "#2f80ed", "#7b61ff", "#c98a1f", "#e67e22",
  "#16a085", "#8e44ad", "#d35400", "#2980b9", "#27ae60",
  "#6c757d", "#9b59b6", "#d93838",
];

const OUTCOME_CHART_COLORS = Object.freeze({
  islem_basarili: "#18a63a",
  anlasilamadi_fallback: "#c98a1f",
  teknik_hata: "#d93838",
  kismi_basarili: "#e67e22",
  veri_bulunamadi: "#7b61ff",
  kapsam_disi_yonlendirildi: "#6c757d",
});

function classificationLabel(code, type) {
  if (!code) return "Etiketsiz";
  const labels = type === "intent" ? INTENT_LABELS : OUTCOME_LABELS;
  return labels[code] || code.replaceAll("_", " ");
}

function outcomeTone(code) {
  if (code === "islem_basarili") return "success";
  if (code === "teknik_hata") return "error";
  if (code === "kismi_basarili") return "partial";
  if (code === "anlasilamadi_fallback" || code === "veri_bulunamadi") return "fallback";
  return "neutral";
}

function formatRate(value) {
  if (value == null || value === "") return "–";
  const number = Number(value);
  return Number.isFinite(number) ? `${number.toFixed(1)}%` : "–";
}

function formatConfidence(value) {
  if (value == null || value === "") return "";
  const number = Number(value);
  return Number.isFinite(number) ? `${Math.round(number * 100)}% güven` : "";
}

function renderClassificationBadge(code, type, confidence = null) {
  if (!code) {
    return '<span class="classification-badge unclassified">Etiketsiz eski kayıt</span>';
  }
  const tone = type === "outcome" ? outcomeTone(code) : "intent";
  const confidenceText = formatConfidence(confidence);
  return `
    <span class="classification-badge ${tone}" title="${escapeHtml(code)}">
      ${escapeHtml(classificationLabel(code, type))}
      ${confidenceText ? `<small>${escapeHtml(confidenceText)}</small>` : ""}
    </span>`;
}

function countClassificationCodes(rows, key) {
  return (rows || []).reduce((counts, row) => {
    const code = row?.[key];
    if (code) counts[code] = (counts[code] || 0) + 1;
    return counts;
  }, {});
}

function renderClassificationBreakdown(element, counts, type) {
  const entries = Object.entries(counts || {})
    .filter(([, count]) => Number(count) > 0)
    .sort((a, b) => Number(b[1]) - Number(a[1]));
  if (!entries.length) {
    element.innerHTML = '<p class="muted-note">Henüz sınıflandırılmış tur yok.</p>';
    return;
  }

  const total = entries.reduce((sum, [, count]) => sum + Number(count), 0);
  element.innerHTML = entries.map(([code, count]) => {
    const percentage = total ? Math.round((Number(count) / total) * 100) : 0;
    return `
      <div class="classification-breakdown-row">
        ${renderClassificationBadge(code, type)}
        <strong>${Number(count)} <small>(${percentage}%)</small></strong>
      </div>`;
  }).join("");
}

function formatDate(value) {
  if (!value) return "-";
  // SQLite CURRENT_TIMESTAMP -> "YYYY-MM-DD HH:MM:SS" (UTC varsayılır)
  const iso = value.includes("T") ? value : value.replace(" ", "T") + "Z";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return value;
  return d.toLocaleString("tr-TR", { dateStyle: "short", timeStyle: "short" });
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

// ---------------------------------------------------------------------
// Backend (Flask /api/admin/...) çağrıları
// ---------------------------------------------------------------------

async function botFetch(path, options = {}) {
  if (!botAccess) throw new Error("Bot backend erişimi hazır değil.");

  // Cloud Function'in yetkili yonetici icin dondurdugu backend adresini kullan.
  // Eski function surumu baseUrl dondurmezse mevcut Render adresiyle uyumluluk
  // korunur; admin anahtari yine yalnizca bellekte tutulur.
  const baseUrl = String(
    botAccess.baseUrl || "https://cinematchbotai.onrender.com"
  ).replace(/\/$/, "");
  const res = await fetch(`${baseUrl}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "X-Admin-Key": botAccess.key, // Şifreyi hala güvenli bir şekilde alıyoruz
      ...(options.headers || {}),
    },
  });

  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.status === "error") {
    throw new Error(body.message || `İstek başarısız (${res.status})`);
  }
  return body;
}

async function downloadBotReport(path, fallbackName, button) {
  if (!botAccess) throw new Error("Bot backend erişimi hazır değil.");
  const originalText = button.textContent;
  button.disabled = true;
  button.textContent = "Hazırlanıyor…";
  try {
    const baseUrl = String(
      botAccess.baseUrl || "https://cinematchbotai.onrender.com"
    ).replace(/\/$/, "");
    const response = await fetch(`${baseUrl}${path}`, {
      headers: {
        Accept: "text/csv",
        "X-Admin-Key": botAccess.key,
      },
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.message || `Rapor indirilemedi (${response.status})`);
    }

    const blob = await response.blob();
    const objectUrl = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = fallbackName;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(objectUrl);
    setMessage(els.globalMessage, `${fallbackName} indirildi.`, "success");
  } catch (error) {
    setMessage(els.globalMessage, error.message, "error");
  } finally {
    button.disabled = false;
    button.textContent = originalText;
  }
}

els.overviewCsvButton.addEventListener("click", () => {
  const days = els.overviewReportDays.value;
  downloadBotReport(
    `/api/admin/reports/overview.csv?days=${encodeURIComponent(days)}`,
    `cinebot-genel-rapor-${days}-gun.csv`,
    els.overviewCsvButton
  );
});

els.outcomesCsvButton.addEventListener("click", () => {
  const days = els.overviewReportDays.value;
  downloadBotReport(
    `/api/admin/reports/outcomes.csv?days=${encodeURIComponent(days)}&limit=5000`,
    `cinebot-sonuclar-${days}-gun.csv`,
    els.outcomesCsvButton
  );
});

els.performanceCsvButton.addEventListener("click", () => {
  const days = els.performanceReportDays.value;
  downloadBotReport(
    `/api/admin/reports/performance.csv?days=${encodeURIComponent(days)}&limit=5000`,
    `cinebot-performans-${days}-gun.csv`,
    els.performanceCsvButton
  );
});

async function loadMonitoring() {
  try {
    const { data } = await botFetch("/api/admin/monitoring");
    els.monitoringMetricsStatus.textContent = data.metrics_auth_enabled
      ? "Aktif · Bearer korumalı"
      : "Aktif · ağ koruması gerekli";
    els.monitoringLogsStatus.textContent = data.structured_logging
      ? "Aktif · JSON"
      : "Kapalı";
    els.monitoringEnvironment.textContent = data.environment || "–";

    if (data.grafana_configured && data.grafana_dashboard_url) {
      els.monitoringGrafanaStatus.textContent = "Bağlı";
      els.grafanaDashboardLink.href = data.grafana_dashboard_url;
      els.grafanaDashboardLink.classList.remove("hidden");
      els.monitoringSetupNote.classList.add("hidden");
    } else {
      els.monitoringGrafanaStatus.textContent = "URL bekleniyor";
      els.grafanaDashboardLink.removeAttribute("href");
      els.grafanaDashboardLink.classList.add("hidden");
      els.monitoringSetupNote.classList.remove("hidden");
    }
  } catch (error) {
    els.monitoringGrafanaStatus.textContent = "Kontrol edilemedi";
    setMessage(els.globalMessage, error.message, "error");
  }
}
// ---------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------

function switchTab(tabName) {
  els.tabButtons.forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.tab === tabName);
  });
  Object.entries(els.tabPanels).forEach(([name, panel]) => {
    panel.classList.toggle("hidden", name !== tabName);
  });

  const titles = {
    overview: "Genel Bakış",
    conversation: "Konuşma Detayı",
    tools: "Tool Çağrıları",
    performance: "Performans",
    monitoring: "Monitoring",
  };
  els.mainTitle.textContent = titles[tabName] || "Bot Paneli";

  if (tabName === "tools" && !els.toolCallsTable.children.length) {
    loadToolCalls();
  }

  if (tabName === "performance" && !els.perfMetricsTable.children.length) {
    loadPerformanceMetrics();
  }

  if (tabName === "monitoring") {
    loadMonitoring();
  }
}

els.tabButtons.forEach((btn) => {
  btn.addEventListener("click", () => switchTab(btn.dataset.tab));
});

// ---------------------------------------------------------------------
// Genel Bakış (overview + basit grafikler)
// ---------------------------------------------------------------------

function renderBarChart(canvasId, labels, data, color, chartKey) {
  const colors = Array.isArray(color) ? color : [color];
  renderNativeBarChart(
    canvasId,
    labels.map((label, index) => ({ label, value: data[index] })),
    colors,
    (value) => String(value)
  );
}

function renderNativeBarChart(canvasId, entries, colors, formatValue) {
  const canvas = document.getElementById(canvasId);
  if (!canvas) return;
  canvas.style.display = "none";

  const containerId = `native-${canvasId}`;
  let container = document.getElementById(containerId);
  if (!container) {
    container = document.createElement("div");
    container.id = containerId;
    container.className = "native-bar-chart";
    canvas.insertAdjacentElement("afterend", container);
  }

  const available = entries.filter(
    (entry) => typeof entry.value === "number" && Number.isFinite(entry.value)
  );
  if (!available.length) {
    container.innerHTML = '<p class="chart-empty">Henüz grafik verisi yok.</p>';
    return;
  }

  const maxValue = Math.max(...available.map((entry) => entry.value), 0);
  container.innerHTML = available.map((entry, index) => {
    const width = maxValue > 0 ? (entry.value / maxValue) * 100 : 0;
    const visibleWidth = entry.value > 0 ? Math.max(width, 2) : 0;
    const color = colors[index % colors.length] || "#18a63a";
    return `
      <div class="native-bar-row">
        <div class="native-bar-meta">
          <span>${escapeHtml(entry.label)}</span>
          <strong>${escapeHtml(formatValue(entry.value))}</strong>
        </div>
        <div class="native-bar-track">
          <div class="native-bar-fill" style="width:${visibleWidth}%;background:${color}"></div>
        </div>
      </div>`;
  }).join("");
}

function renderNativeLineChart(canvasId, entries) {
  const canvas = document.getElementById(canvasId);
  if (!canvas) return;
  canvas.style.display = "none";

  const containerId = `native-${canvasId}`;
  let container = document.getElementById(containerId);
  if (!container) {
    container = document.createElement("div");
    container.id = containerId;
    canvas.insertAdjacentElement("afterend", container);
  }
  container.className = "native-line-chart";

  const available = entries.filter(
    (entry) => typeof entry.value === "number" && Number.isFinite(entry.value)
  );
  if (!available.length) {
    container.innerHTML = '<p class="chart-empty">Henüz grafik verisi yok.</p>';
    return;
  }

  const width = 1000;
  const height = 360;
  const margin = { top: 24, right: 28, bottom: 62, left: 82 };
  const plotWidth = width - margin.left - margin.right;
  const plotHeight = height - margin.top - margin.bottom;
  const maxValue = Math.max(...available.map((entry) => entry.value), 1);
  const yMax = Math.ceil((maxValue * 1.1) / 1000) * 1000 || 1000;
  const xAt = (index) => margin.left + (
    available.length === 1 ? plotWidth / 2 : (index / (available.length - 1)) * plotWidth
  );
  const yAt = (value) => margin.top + plotHeight - (value / yMax) * plotHeight;
  const points = available.map((entry, index) => `${xAt(index)},${yAt(entry.value)}`).join(" ");
  const labelStep = Math.max(1, Math.ceil(available.length / 8));

  const grid = Array.from({ length: 5 }, (_, index) => {
    const ratio = index / 4;
    const y = margin.top + plotHeight * ratio;
    const value = Math.round(yMax * (1 - ratio));
    return `
      <line x1="${margin.left}" y1="${y}" x2="${width - margin.right}" y2="${y}" class="line-grid" />
      <text x="${margin.left - 12}" y="${y + 4}" text-anchor="end" class="line-axis-label">${value} ms</text>`;
  }).join("");

  const xLabels = available.map((entry, index) => {
    if (index % labelStep !== 0 && index !== available.length - 1) return "";
    return `<text x="${xAt(index)}" y="${height - 24}" text-anchor="middle" class="line-axis-label">${escapeHtml(entry.timeLabel)}</text>`;
  }).join("");

  const circles = available.map((entry, index) => `
    <circle cx="${xAt(index)}" cy="${yAt(entry.value)}" r="5" class="line-point">
      <title>${escapeHtml(`${entry.timeLabel} — ${entry.value} ms (${(entry.value / 1000).toFixed(2)} sn), ${entry.count} ölçüm`)}</title>
    </circle>`).join("");

  const pointValues = available.map((entry, index) => {
    const pointY = yAt(entry.value);
    const placeBelow = pointY < margin.top + 24 || index % 2 === 1;
    const labelY = pointY + (placeBelow ? 22 : -13);
    return `<text x="${xAt(index)}" y="${labelY}" text-anchor="middle" class="line-value-label">${entry.value} ms</text>`;
  }).join("");

  container.innerHTML = `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Zamana göre ortalama E2E çizgi grafiği">
      ${grid}
      <line x1="${margin.left}" y1="${margin.top + plotHeight}" x2="${width - margin.right}" y2="${margin.top + plotHeight}" class="line-axis" />
      <polyline points="${points}" class="line-series" />
      ${circles}
      ${pointValues}
      ${xLabels}
    </svg>`;
}

async function loadOverview() {
  setMessage(els.globalMessage, "Genel bakış yükleniyor...");
  try {
    const { data } = await botFetch("/api/admin/overview?days=14");

    els.kpiSessions.textContent = data.total_sessions ?? "–";
    els.kpiMessages.textContent = data.total_messages ?? "–";
    els.kpiTools.textContent = data.total_tool_calls ?? "–";
    els.kpiRating.textContent = data.avg_rating != null ? data.avg_rating : "–";

    els.ovSessions.textContent = data.total_sessions ?? "–";
    els.ovActive.textContent = data.active_sessions ?? "–";
    els.ovMessages.textContent = data.total_messages ?? "–";
    els.ovUsers.textContent = data.total_users ?? "–";
    els.ovTools.textContent = data.total_tool_calls ?? "–";

    const successRate = data.total_tool_calls
      ? Math.round((data.successful_tool_calls / data.total_tool_calls) * 100)
      : null;
    els.ovToolSuccess.textContent = successRate != null ? `${successRate}%` : "–";
    els.ovAvgRating.textContent = data.avg_rating != null ? `${data.avg_rating} / 5` : "Henüz yok";
    els.ovEvalCount.textContent = data.total_evaluations ?? 0;
    els.ovClassified.textContent = data.classified_messages ?? "–";
    els.ovSuccessRate.textContent = formatRate(data.success_rate);
    els.ovFallbackRate.textContent = formatRate(data.fallback_rate);
    els.ovTechnicalRate.textContent = formatRate(data.technical_error_rate);

    const intentDistribution = data.intent_distribution || [];
    renderBarChart(
      "intentChart",
      intentDistribution.map((item) => classificationLabel(item.intent, "intent")),
      intentDistribution.map((item) => Number(item.count) || 0),
      INTENT_CHART_COLORS,
      "intents"
    );

    const outcomeDistribution = data.outcome_distribution || [];
    renderBarChart(
      "outcomeChart",
      outcomeDistribution.map((item) => classificationLabel(item.outcome, "outcome")),
      outcomeDistribution.map((item) => Number(item.count) || 0),
      outcomeDistribution.map((item) => OUTCOME_CHART_COLORS[item.outcome] || "#6c757d"),
      "outcomes"
    );

    renderBarChart(
      "dailyChart",
      (data.daily_messages || []).map((d) => d.day.slice(5)),
      (data.daily_messages || []).map((d) => d.c),
      "#18a63a",
      "daily"
    );

    renderBarChart(
      "toolChart",
      ["Başarılı", "Başarısız"],
      [data.successful_tool_calls || 0, data.failed_tool_calls || 0],
      ["#18a63a", "#d93838"],
      "tool"
    );

    renderBarChart(
      "ratingChart",
      (data.rating_distribution || []).map((r) => `${r.rating}★`),
      (data.rating_distribution || []).map((r) => r.c),
      "#c98a1f",
      "rating"
    );

    els.topMoviesTable.innerHTML = (data.top_movies || [])
      .map((m) => `<tr><td>${escapeHtml(m.movie_name)}</td><td>${m.c}</td><td>${formatMs(m.avg_duration_ms)}</td></tr>`)
      .join("") || '<tr><td colspan="3">Henüz veri yok.</td></tr>';

    setMessage(els.globalMessage, "");
  } catch (error) {
    setMessage(els.globalMessage, error.message, "error");
  }
}

// ---------------------------------------------------------------------
// Konuşma listesi (sidebar)
// ---------------------------------------------------------------------

function renderSessionList() {
  if (!sessions.length) {
    els.sessionList.innerHTML = '<p class="message">Konuşma bulunamadı.</p>';
    return;
  }
  els.sessionList.innerHTML = "";
  sessions.forEach((s) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "article-item";
    button.dataset.id = s.session_id;
    const ratingBadge = s.avg_rating != null
      ? `<span class="rating-badge">★ ${Number(s.avg_rating).toFixed(1)}</span>`
      : "";
    const classificationBadges = [
      s.last_intent ? renderClassificationBadge(s.last_intent, "intent") : "",
      s.last_outcome ? renderClassificationBadge(s.last_outcome, "outcome") : "",
    ].join("");
    button.innerHTML = `
      <strong>${escapeHtml(s.username || s.user_id)}</strong>
      <span>Oturum ID: ${escapeHtml(s.session_id || "-")}</span>
      <span>${s.message_count} mesaj · ${s.is_active ? "aktif" : "kapalı"} · ${formatDate(s.last_active_at)}</span>
      ${classificationBadges ? `<div class="session-list-badges">${classificationBadges}</div>` : ""}
      ${ratingBadge}
    `;
    button.addEventListener("click", () => openSession(s.session_id));
    els.sessionList.appendChild(button);
  });
  markActiveSession(activeSessionId);
}

function markActiveSession(id) {
  document.querySelectorAll(".article-item").forEach((button) => {
    // Firestore oturum ID'leri metindir. Number(...) her iki değeri de NaN'a
    // dönüştürdüğü için seçili kart hiçbir zaman işaretlenemiyordu.
    button.classList.toggle("active", String(button.dataset.id) === String(id));
  });
}

function renderSessionPager(total) {
  const page = Math.floor(sessionOffset / SESSION_PAGE_SIZE) + 1;
  const totalPages = Math.max(1, Math.ceil(total / SESSION_PAGE_SIZE));
  els.sessionPager.innerHTML = `
    <button id="sessionPrev" ${sessionOffset === 0 ? "disabled" : ""}>‹ Önceki</button>
    <span>${page} / ${totalPages}</span>
    <button id="sessionNext" ${sessionOffset + SESSION_PAGE_SIZE >= total ? "disabled" : ""}>Sonraki ›</button>
  `;
  document.getElementById("sessionPrev")?.addEventListener("click", () => {
    sessionOffset = Math.max(0, sessionOffset - SESSION_PAGE_SIZE);
    loadSessions();
  });
  document.getElementById("sessionNext")?.addEventListener("click", () => {
    sessionOffset += SESSION_PAGE_SIZE;
    loadSessions();
  });
}

async function loadSessions() {
  try {
    const search = els.sessionSearch.value.trim();
    const params = new URLSearchParams({
      limit: SESSION_PAGE_SIZE,
      offset: sessionOffset,
    });
    if (search) params.set("search", search);

    const { data, pagination } = await botFetch(`/api/admin/sessions?${params}`);
    sessions = data;
    els.sessionCount.textContent = `${pagination.total} oturum`;
    renderSessionList();
    renderSessionPager(pagination.total);
  } catch (error) {
    els.sessionList.innerHTML = `<p class="message error">${escapeHtml(error.message)}</p>`;
  }
}

let searchDebounce = null;
els.sessionSearch.addEventListener("input", () => {
  clearTimeout(searchDebounce);
  searchDebounce = setTimeout(() => {
    sessionOffset = 0;
    loadSessions();
  }, 300);
});

// ---------------------------------------------------------------------
// Konuşma detayı
// ---------------------------------------------------------------------

async function openSession(sessionId) {
  activeSessionId = sessionId;
  markActiveSession(sessionId);
  switchTab("conversation");

  els.conversationEmpty.classList.add("hidden");
  els.conversationContent.classList.remove("hidden");
  els.transcriptList.innerHTML = '<p class="message">Yükleniyor...</p>';

  try {
    const { data } = await botFetch(`/api/admin/sessions/${sessionId}`);
    const {
      session,
      transcript,
      tool_calls,
      evaluations,
      user_facts,
      performance_metrics = [],
      performance_averages = {},
      voice_recordings = [],
      voice_ai_evaluations = [],
    } = data;
    const intentCounts = Object.keys(session.intent_counts || {}).length
      ? session.intent_counts
      : countClassificationCodes(transcript, "intent");
    const outcomeCounts = Object.keys(session.outcome_counts || {}).length
      ? session.outcome_counts
      : countClassificationCodes(transcript, "outcome");
    const classifiedTurns = transcript.filter((turn) => turn.intent && turn.outcome);
    const classificationVersions = [
      ...new Set(classifiedTurns.map((turn) => turn.classification_version).filter(Boolean)),
    ];
    const lastClassifiedTurn = [...transcript].reverse().find(
      (turn) => turn.intent || turn.outcome
    );
    const lastIntent = session.last_intent || lastClassifiedTurn?.intent;
    const lastOutcome = session.last_outcome || lastClassifiedTurn?.outcome;

    els.sessionMeta.innerHTML = `
      <div><span>Oturum ID</span>${escapeHtml(session.session_id || "-")}</div>
      <div><span>Kullanıcı</span>${escapeHtml(session.username || "-")}</div>
      <div><span>User ID</span>${escapeHtml(session.user_id)}</div>
      <div><span>Başladı</span>${formatDate(session.started_at)}</div>
      <div><span>Son Aktiflik</span>${formatDate(session.last_active_at)}</div>
      <div><span>Mesaj Sayısı</span>${session.message_count}</div>
      <div><span>Durum</span>${session.is_active ? "Aktif" : "Kapalı"}</div>
      <div><span>Son Niyet</span>${escapeHtml(classificationLabel(lastIntent, "intent"))}</div>
      <div><span>Son Sonuç</span>${escapeHtml(classificationLabel(lastOutcome, "outcome"))}</div>
      <div><span>Bilinen Bilgiler</span>${escapeHtml(JSON.stringify(user_facts || {}))}</div>
    `;

    els.sessionSummary.textContent = session.summary && session.summary.trim()
      ? session.summary
      : "Bu oturum için henüz otomatik özet üretilmedi.";

    renderClassificationBreakdown(els.sessionIntentBreakdown, intentCounts, "intent");
    renderClassificationBreakdown(els.sessionOutcomeBreakdown, outcomeCounts, "outcome");
    const unclassifiedTurns = Math.max(0, transcript.length - classifiedTurns.length);
    els.sessionClassificationNote.textContent = classifiedTurns.length
      ? `${classifiedTurns.length}/${transcript.length} tur sınıflandırıldı`
        + (unclassifiedTurns ? ` · ${unclassifiedTurns} eski tur etiketsiz` : "")
        + (classificationVersions.length
          ? ` · Sürüm: ${classificationVersions.join(", ")}`
          : "")
      : "Bu oturumdaki kayıtlar etiketleme sistemi devreye alınmadan önce oluşturulmuş.";

    renderPerfSummaryInto(els.sessionPerfSummaryGrid, performance_averages);
    renderPerfRowsInto(
      els.sessionPerfMetricsTable,
      performance_metrics,
      "Bu oturuma ait performans ölçümü yok."
    );

    els.voiceRecordingsList.innerHTML = voice_recordings.length
      ? voice_recordings.map((recording) => recording.status === "ready" ? `
          <div class="voice-recording-card">
            <div class="bubble-time">${formatDate(recording.created_at)}</div>
            <label>
              Kullanıcı (${formatMs(recording.user_duration_ms)})
              <audio controls preload="none" src="${escapeHtml(recording.user_audio_url || "")}"></audio>
            </label>
            <label>
              CineMatch (${formatMs(recording.agent_duration_ms)})
              <audio controls preload="none" src="${escapeHtml(recording.agent_audio_url || "")}"></audio>
            </label>
          </div>
        ` : `
          <div class="voice-recording-card">
            <div class="bubble-time">${formatDate(recording.created_at)}</div>
            <p class="message error">
              Kayıt durumu: ${escapeHtml(recording.status || "bilinmiyor")}
              ${recording.error ? `— ${escapeHtml(recording.error)}` : ""}
            </p>
          </div>
        `).join("")
      : '<p class="message">Bu oturumda ses kaydı yok.</p>';

    els.voiceAiEvaluations.innerHTML = voice_ai_evaluations.length
      ? voice_ai_evaluations.map((evaluation) => {
          const reEvaluateButton = `
            <button
              class="secondary-btn re-evaluate-voice"
              type="button"
              data-recording-id="${escapeHtml(evaluation.recording_id || evaluation.id || "")}">
              Tekrar değerlendir
            </button>`;
          if (evaluation.status !== "completed") {
            return `
              <div class="ai-evaluation-card">
                <p class="message ${evaluation.status === "failed" ? "error" : ""}">
                  Değerlendirme durumu: ${escapeHtml(evaluation.status || "bilinmiyor")}
                  ${evaluation.error ? `— ${escapeHtml(evaluation.error)}` : ""}
                </p>
                ${evaluation.status === "queued" || evaluation.status === "processing" ? "" : reEvaluateButton}
              </div>
            `;
          }
          const criteria = Object.values(evaluation.criteria || {});
          const issues = evaluation.issues || [];
          const recommendations = evaluation.prompt_recommendations || [];
          const strengths = evaluation.strengths || [];
          return `
            <div class="ai-evaluation-card">
              <div class="evaluation-heading">
                <strong>${Number(evaluation.overall_score).toFixed(0)}/100</strong>
                <span>${formatDate(evaluation.created_at)}</span>
                ${reEvaluateButton}
              </div>
              <p>${escapeHtml(evaluation.summary || "")}</p>
              <h4>Kriter Puanları</h4>
              <div class="evaluation-criteria">
                ${criteria.map((criterion) => `
                  <div>
                    <span>${escapeHtml(criterion.label || "-")}</span>
                    <strong>${criterion.observed ? `${criterion.score}/10` : "Gözlenemedi"}</strong>
                    <small>${escapeHtml(criterion.reason || "")}</small>
                  </div>
                `).join("")}
              </div>
              <h4>Güçlü Yönler</h4>
              ${strengths.length
                ? `<ul>${strengths.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>`
                : '<p class="muted-note">Belirtilmedi.</p>'}
              <h4>Tespit Edilen Sorunlar</h4>
              ${issues.length
                ? `<ul>${issues.map((issue) => `
                    <li>
                      <strong>[${escapeHtml(issue.severity || "-")}] ${escapeHtml(issue.type || "-")}</strong>
                      — ${escapeHtml(issue.evidence || "")}
                      <br><small>Öneri: ${escapeHtml(issue.recommendation || "")}</small>
                    </li>
                  `).join("")}</ul>`
                : '<p class="muted-note">Sorun tespit edilmedi.</p>'}
              <h4>Prompt İyileştirme Önerileri</h4>
              ${recommendations.length
                ? `<div class="prompt-recommendations">${recommendations.map((item) => `
                    <div>
                      <strong>${escapeHtml(item.priority || "-")} — ${escapeHtml(item.problem || "")}</strong>
                      <code>${escapeHtml(item.suggested_instruction || "")}</code>
                      <small>${escapeHtml(item.expected_effect || "")}</small>
                    </div>
                  `).join("")}</div>`
                : '<p class="muted-note">Prompt değişikliği önerilmedi.</p>'}
            </div>
          `;
        }).join("")
      : '<p class="message">Bu oturum için AI değerlendirmesi yok.</p>';

    els.voiceAiEvaluations.querySelectorAll(".re-evaluate-voice").forEach((button) => {
      button.addEventListener("click", async () => {
        const recordingId = button.dataset.recordingId;
        if (!recordingId || button.disabled) return;
        button.disabled = true;
        const originalText = button.textContent;
        button.textContent = "Kuyruğa alınıyor...";
        try {
          await botFetch(`/api/admin/voice-recordings/${encodeURIComponent(recordingId)}/qa/re-evaluate`, {
            method: "POST",
          });
          await openSession(activeSessionId);
        } catch (error) {
          button.disabled = false;
          button.textContent = originalText;
          setMessage(els.globalMessage, error.message, "error");
        }
      });
    });

    els.transcriptList.innerHTML = transcript.length
      ? transcript.map((turn) => {
          const errorDetail = turn.error_stage || turn.error_type
            ? `<span class="classification-error-detail">
                Hata: ${escapeHtml(turn.error_stage || "bilinmeyen aşama")}
                ${turn.error_type ? ` · ${escapeHtml(turn.error_type)}` : ""}
              </span>`
            : "";
          const classificationBadges = turn.intent || turn.outcome
            ? [
                turn.intent
                  ? renderClassificationBadge(turn.intent, "intent", turn.intent_confidence)
                  : "",
                turn.outcome
                  ? renderClassificationBadge(turn.outcome, "outcome", turn.outcome_confidence)
                  : "",
              ].join("")
            : '<span class="classification-badge unclassified">Etiketsiz eski kayıt</span>';
          return `
          <div class="bubble-row">
            <div class="bubble bubble-user">${escapeHtml(turn.user_message)}</div>
            <div class="bubble bubble-bot">${escapeHtml(turn.bot_response)}</div>
            <div class="turn-classification">
              ${classificationBadges}
              <span class="turn-channel">
                ${escapeHtml(turn.channel || "bilinmeyen kanal")}
                · ${escapeHtml(turn.input_type || "bilinmeyen girdi")}
              </span>
              ${errorDetail}
            </div>
            <div class="bubble-time">
              ${formatDate(turn.created_at)}
              ${turn.classification_version
                ? ` · ${escapeHtml(turn.classification_version)}`
                : ""}
            </div>
          </div>
        `;}).join("")
      : '<p class="message">Bu oturumda mesaj yok.</p>';

    if (tool_calls.length) {
      els.sessionToolsEmpty.classList.add("hidden");
      els.sessionToolsTable.innerHTML = tool_calls.map((t) => {
        const ok = /"Response":\s*"True"/.test(t.api_response);
        const isGuideTool = t.api_endpoint === "internal://cinematch-app-guide";
        const toolName = t.tool_name || (isGuideTool
          ? "get_cinematch_app_guide"
          : "get_live_movie_data");
        const toolQuery = t.query || t.movie_name || (isGuideTool
          ? "CineMatch uygulama rehberi"
          : "-");
        return `<tr>
          <td>${formatDate(t.timestamp)}</td>
          <td>${escapeHtml(toolName)}</td>
          <td>${escapeHtml(toolQuery)}</td>
          <td>${formatMs(t.duration_ms)}</td>
          <td class="${ok ? "result-ok" : "result-fail"}">${ok ? "Başarılı" : "Başarısız"}</td>
        </tr>`;
      }).join("");
    } else {
      els.sessionToolsEmpty.classList.remove("hidden");
      els.sessionToolsTable.innerHTML = "";
    }

    renderEvaluations(evaluations);
  } catch (error) {
    els.transcriptList.innerHTML = `<p class="message error">${escapeHtml(error.message)}</p>`;
  }
}

function renderEvaluations(evaluations) {
  els.evaluationsTable.innerHTML = evaluations.length
    ? evaluations.map((e) => `
        <tr>
          <td>${formatDate(e.created_at)}</td>
          <td>${"★".repeat(e.rating)}${"☆".repeat(5 - e.rating)}</td>
          <td>${escapeHtml(e.note || "-")}</td>
          <td>${escapeHtml(e.evaluator || "-")}</td>
        </tr>
      `).join("")
    : '<tr><td colspan="4">Henüz değerlendirme yok.</td></tr>';
}

els.evaluateForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!activeSessionId) return;

  setMessage(els.evalMessage, "Kaydediliyor...");
  try {
    await botFetch(`/api/admin/sessions/${activeSessionId}/evaluate`, {
      method: "POST",
      body: JSON.stringify({
        rating: Number(els.evalRating.value),
        note: els.evalNote.value.trim(),
        evaluator: els.currentUserLabel.textContent,
      }),
    });
    setMessage(els.evalMessage, "Kaydedildi.", "success");
    els.evalNote.value = "";
    await openSession(activeSessionId); // listeyi + rozetleri tazele
    await loadSessions();
  } catch (error) {
    setMessage(els.evalMessage, error.message, "error");
  }
});

// ---------------------------------------------------------------------
// Tool çağrıları (global liste)
// ---------------------------------------------------------------------

function renderToolCallsPager(total) {
  const page = Math.floor(toolCallsOffset / TOOL_PAGE_SIZE) + 1;
  const totalPages = Math.max(1, Math.ceil(total / TOOL_PAGE_SIZE));
  els.toolCallsPager.innerHTML = `
    <button id="toolPrev" ${toolCallsOffset === 0 ? "disabled" : ""}>‹ Önceki</button>
    <span>${page} / ${totalPages}</span>
    <button id="toolNext" ${toolCallsOffset + TOOL_PAGE_SIZE >= total ? "disabled" : ""}>Sonraki ›</button>
  `;
  document.getElementById("toolPrev")?.addEventListener("click", () => {
    toolCallsOffset = Math.max(0, toolCallsOffset - TOOL_PAGE_SIZE);
    loadToolCalls();
  });
  document.getElementById("toolNext")?.addEventListener("click", () => {
    toolCallsOffset += TOOL_PAGE_SIZE;
    loadToolCalls();
  });
}

async function loadToolCalls() {
  try {
    const params = new URLSearchParams({ limit: TOOL_PAGE_SIZE, offset: toolCallsOffset });
    const { data, pagination } = await botFetch(`/api/admin/tool-calls?${params}`);

    els.toolCallsTable.innerHTML = data.length
      ? data.map((t) => {
          const ok = /"Response":\s*"True"/.test(t.api_response);
          const isGuideTool = t.api_endpoint === "internal://cinematch-app-guide";
          const toolName = t.tool_name || (isGuideTool
            ? "get_cinematch_app_guide"
            : "get_live_movie_data");
          const toolQuery = t.query || t.movie_name || (isGuideTool
            ? "CineMatch uygulama rehberi"
            : "-");
          return `<tr>
            <td>${formatDate(t.timestamp)}</td>
            <td>${escapeHtml(t.username || t.user_id || "-")}</td>
            <td>${escapeHtml(toolName)}</td>
            <td>${escapeHtml(toolQuery)}</td>
            <td>${formatMs(t.duration_ms)}</td>
            <td class="${ok ? "result-ok" : "result-fail"}">${ok ? "Başarılı" : "Başarısız"}</td>
            <td>${t.session_id ? `<button class="link-btn" data-session="${t.session_id}">#${t.session_id}</button>` : "-"}</td>
          </tr>`;
        }).join("")
      : '<tr><td colspan="7">Henüz tool çağrısı yok.</td></tr>';

    els.toolCallsTable.querySelectorAll("[data-session]").forEach((btn) => {
      // Firestore session ID'leri sayısal değildir; Number(...) kullanmak ID'yi
      // NaN'a çevirip oturum detayına geçişi bozuyordu.
      btn.addEventListener("click", () => openSession(btn.dataset.session));
    });

    renderToolCallsPager(pagination.total);
  } catch (error) {
    els.toolCallsTable.innerHTML = `<tr><td colspan="7">${escapeHtml(error.message)}</td></tr>`;
  }
}

// ---------------------------------------------------------------------
// Performans metrikleri (bot_performance_metrics)
// ---------------------------------------------------------------------

const PERF_FIELDS = [
  { key: "telegram_download_ms", label: "Telegram İndirme" },
  { key: "asr_ms", label: "ASR/EOT (Tahmini)" },
  { key: "ai_ms", label: "AI Cevap Üretimi" },
  { key: "ai_ready_ms", label: "AI Hazır (Toplam)" },
  { key: "telegram_text_send_ms", label: "Metin Gönderim" },
  { key: "ttfb_ms", label: "TTFB" },
  { key: "tts_ms", label: "TTS (Metin→Ses)" },
  { key: "tts_ready_ms", label: "TTS Hazır (Toplam)" },
  { key: "telegram_voice_upload_ms", label: "Ses Yükleme" },
  { key: "voice_audio_stream_ms", label: "Ses Oynatma" },
  { key: "tool_total_ms", label: "Tool Toplamı" },
  { key: "ttfs_ms", label: "TTFS" },
  { key: "e2e_ms", label: "E2E Gecikme (İlk Ses)" },
  { key: "full_turn_ms", label: "Tam Sesli Tur Süresi" },
];

let perfOffset = 0;
const PERF_PAGE_SIZE = 25;
let e2eTrendRange = "day";
let e2eTrendPoints = [];

function formatMs(v) {
  return typeof v === "number" ? `${v} ms` : "-";
}

function renderPerfSummaryInto(element, averages) {
  element.innerHTML = PERF_FIELDS.map(({ key, label }) => `
    <div class="kpi-card">
      <span>${label}</span>
      <strong>${averages && averages[key] != null ? averages[key] + " ms" : "–"}</strong>
    </div>
  `).join("");
}

function renderPerfSummary(averages) {
  renderPerfSummaryInto(els.perfSummaryGrid, averages);
}

function renderPerfRowsInto(element, rows, emptyMessage = "Henüz veri yok.") {
  element.innerHTML = rows.length
    ? rows.map((r) => `
        <tr>
          <td>${formatDate(r.created_at)}</td>
          <td>${escapeHtml(r.channel || "-")}</td>
          <td>${formatMs(r.telegram_download_ms)}</td>
          <td>${formatMs(r.asr_ms)}</td>
          <td>${formatMs(r.ai_ms)}</td>
          <td>${formatMs(r.ai_ready_ms)}</td>
          <td>${formatMs(r.telegram_text_send_ms)}</td>
          <td>${formatMs(r.ttfb_ms)}</td>
          <td>${formatMs(r.tts_ms)}</td>
          <td>${formatMs(r.tts_ready_ms)}</td>
          <td>${formatMs(r.telegram_voice_upload_ms)}</td>
          <td>${formatMs(r.voice_audio_stream_ms)}</td>
          <td>${formatMs(r.tool_total_ms)}</td>
          <td>${formatMs(r.ttfs_ms)}</td>
          <td>${formatMs(r.e2e_ms)}</td>
          <td>${formatMs(r.full_turn_ms)}</td>
        </tr>
      `).join("")
    : `<tr><td colspan="16">${escapeHtml(emptyMessage)}</td></tr>`;
}

function renderPerfRows(rows) {
  renderPerfRowsInto(els.perfMetricsTable, rows);
}

function renderPerformanceChart(canvasId, entries, chartKey, colors) {
  renderNativeBarChart(
    canvasId,
    entries,
    colors,
    (value) => `${value} ms (${(value / 1000).toFixed(2)} sn)`
  );
}

function renderPerformanceCharts(averages) {
  const source = averages || {};
  renderPerformanceChart(
    "perfStageChart",
    [
      { label: "Telegram indirme", value: source.telegram_download_ms },
      { label: "ASR", value: source.asr_ms },
      { label: "AI üretimi", value: source.ai_ms },
      { label: "Metin gönderimi", value: source.telegram_text_send_ms },
      { label: "TTS", value: source.tts_ms },
      { label: "Ses yükleme", value: source.telegram_voice_upload_ms },
      { label: "Ses oynatma", value: source.voice_audio_stream_ms },
      { label: "Tool toplamı", value: source.tool_total_ms },
    ],
    "performanceStages",
    ["#2f80ed", "#7b61ff", "#18a63a", "#27ae60", "#c98a1f", "#e67e22"]
  );

  renderPerformanceChart(
    "perfMilestoneChart",
    [
      { label: "AI hazır", value: source.ai_ready_ms },
      { label: "TTFB", value: source.ttfb_ms },
      { label: "TTS hazır", value: source.tts_ready_ms },
      { label: "TTFS", value: source.ttfs_ms },
      { label: "E2E", value: source.e2e_ms },
      { label: "Tam tur", value: source.full_turn_ms },
    ],
    "performanceMilestones",
    ["#18a63a", "#2f80ed", "#c98a1f", "#e67e22", "#d93838"]
  );
}

const E2E_TREND_OPTIONS = {
  hour: {
    durationMs: 60 * 60 * 1000,
    description: "Son 1 saatteki dakika bazlı ortalama E2E süreleri.",
  },
  day: {
    durationMs: 24 * 60 * 60 * 1000,
    description: "Son 24 saatteki saatlik ortalama E2E süreleri.",
  },
  week: {
    durationMs: 7 * 24 * 60 * 60 * 1000,
    description: "Son 7 gündeki günlük ortalama E2E süreleri.",
  },
};

function pad2(value) {
  return String(value).padStart(2, "0");
}

function getE2EBucket(date, range) {
  const year = date.getFullYear();
  const month = pad2(date.getMonth() + 1);
  const day = pad2(date.getDate());
  const hour = pad2(date.getHours());

  if (range === "hour") {
    const minute = pad2(date.getMinutes());
    return {
      key: `${year}-${month}-${day}-${hour}-${minute}`,
      label: `${hour}:${minute}`,
      sortAt: new Date(year, date.getMonth(), date.getDate(), date.getHours(), date.getMinutes()).getTime(),
    };
  }

  if (range === "day") {
    return {
      key: `${year}-${month}-${day}-${hour}`,
      label: `${day}.${month} ${hour}:00`,
      sortAt: new Date(year, date.getMonth(), date.getDate(), date.getHours()).getTime(),
    };
  }

  return {
    key: `${year}-${month}-${day}`,
    label: `${day}.${month}`,
    sortAt: new Date(year, date.getMonth(), date.getDate()).getTime(),
  };
}

function renderE2ETrend() {
  const option = E2E_TREND_OPTIONS[e2eTrendRange];
  const cutoff = Date.now() - option.durationMs;
  const buckets = new Map();

  e2eTrendPoints.forEach((point) => {
    const date = new Date(point.created_at);
    const value = Number(point.e2e_ms);
    if (!Number.isFinite(date.getTime()) || date.getTime() < cutoff || !Number.isFinite(value)) return;

    const bucket = getE2EBucket(date, e2eTrendRange);
    const current = buckets.get(bucket.key) || { ...bucket, total: 0, count: 0 };
    current.total += value;
    current.count += 1;
    buckets.set(bucket.key, current);
  });

  const entries = Array.from(buckets.values())
    .sort((a, b) => a.sortAt - b.sortAt)
    .map((bucket) => ({
      timeLabel: bucket.label,
      count: bucket.count,
      value: Math.round(bucket.total / bucket.count),
    }));

  document.getElementById("e2eTrendDescription").textContent = option.description;
  document.querySelectorAll("[data-e2e-range]").forEach((button) => {
    button.classList.toggle("active", button.dataset.e2eRange === e2eTrendRange);
  });
  renderNativeLineChart("e2eTrendCanvas", entries);
}

document.querySelectorAll("[data-e2e-range]").forEach((button) => {
  button.addEventListener("click", () => {
    e2eTrendRange = button.dataset.e2eRange;
    renderE2ETrend();
  });
});

function renderPerfPager(total) {
  const page = Math.floor(perfOffset / PERF_PAGE_SIZE) + 1;
  const totalPages = Math.max(1, Math.ceil(total / PERF_PAGE_SIZE));
  els.perfPager.innerHTML = `
    <button id="perfPrev" ${perfOffset === 0 ? "disabled" : ""}>‹ Önceki</button>
    <span>${page} / ${totalPages}</span>
    <button id="perfNext" ${perfOffset + PERF_PAGE_SIZE >= total ? "disabled" : ""}>Sonraki ›</button>
  `;
  document.getElementById("perfPrev")?.addEventListener("click", () => {
    perfOffset = Math.max(0, perfOffset - PERF_PAGE_SIZE);
    loadPerformanceMetrics();
  });
  document.getElementById("perfNext")?.addEventListener("click", () => {
    perfOffset += PERF_PAGE_SIZE;
    loadPerformanceMetrics();
  });
}

async function loadPerformanceMetrics() {
  setMessage(els.globalMessage, "Performans verileri yükleniyor...");
  try {
    const params = new URLSearchParams({ limit: PERF_PAGE_SIZE, offset: perfOffset });
    const { data, averages, pagination } = await botFetch(`/api/admin/performance?${params}`);

    renderPerfSummary(averages);
    renderPerformanceCharts(averages);
    // Yeni backend aynı ortalama sorgusundan daha geniş nokta listesini gönderir.
    // Backend henüz deploy edilmediyse, zaten bu yanıtta bulunan tablo satırları
    // kullanılır; iki durumda da ilave bir API/Firestore isteği yapılmaz.
    const averagePoints = Array.isArray(averages?._e2e_points)
      ? averages._e2e_points
      : [];
    e2eTrendPoints = averagePoints.length
      ? averagePoints
      : (data || [])
          .filter((row) => row.created_at && Number.isFinite(Number(row.e2e_ms)))
          .map((row) => ({ created_at: row.created_at, e2e_ms: Number(row.e2e_ms) }));
    renderE2ETrend();
    renderPerfRows(data);
    renderPerfPager(pagination.total);

    setMessage(els.globalMessage, "");
  } catch (error) {
    els.perfMetricsTable.innerHTML = `<tr><td colspan="16">${escapeHtml(error.message)}</td></tr>`;
    setMessage(els.globalMessage, error.message, "error");
  }
}

// ---------------------------------------------------------------------
// Genel yenile / auth akışı
// ---------------------------------------------------------------------

async function loadAll() {
  sessionOffset = 0;
  toolCallsOffset = 0;
  perfOffset = 0;
  await Promise.all([loadOverview(), loadSessions()]);
  if (!els.tabPanels.tools.classList.contains("hidden")) {
    await loadToolCalls();
  }
  if (!els.tabPanels.performance.classList.contains("hidden")) {
    await loadPerformanceMetrics();
  }
  if (!els.tabPanels.monitoring.classList.contains("hidden")) {
    await loadMonitoring();
  }
}

els.refreshButton.addEventListener("click", loadAll);

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

// LOCAL kalıcılık ayarlanmadan auth dinleyicisini başlatmıyoruz. Böylece
// yenilemede geçici bir null kullanıcı durumu arayüze yansıtılmıyor.
authPersistenceReady.then(() => {
  auth.onAuthStateChanged(async (user) => {
    botAccess = null;

    if (!user) {
      showLogin();
      return;
    }

    try {
      // Bot backend erişim anahtarı sekme ömrü boyunca kısa süreliğine
      // önbelleğe alınır; bu sayede bu panele tekrar dönüldüğünde
      // (ör. başka bir admin sayfasına gidip geri gelince) her seferinde
      // yeniden Cloud Function çağrısı yapılmaz.
      botAccess = await CineAdmin.requireRole(user, "botAdmin", async () => {
        const getBotAdminAccess = functions.httpsCallable("getBotAdminAccess");
        const result = await getBotAdminAccess();
        return result.data; // { baseUrl, key }
      });

      showAdmin(user);
      await loadAll();
    } catch (error) {
      if (isPermissionError(error)) {
        await CineAdmin.logout();
        showLogin();
        setMessage(els.loginMessage, "Bu panel için yetkiniz yok.", "error");
        return;
      }

      showAdmin(user);
      setMessage(
        els.globalMessage,
        error.message || "Bot backend erişimi alınamadı. Sayfayı yenileyebilirsiniz.",
        "error"
      );
    }
  });
});
