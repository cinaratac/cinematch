/**
 * CineBot AI - web sohbet widget'ı
 * -----------------------------------------------------------------------
 * cinematchbotai (Flask/Python) backend'indeki POST /api/chat uç noktasını
 * kullanan, bağımsız (framework'süz) bir sohbet balonu widget'ı.
 *
 * Kurulum: Bu dosyayı ve cinebot-widget.css'i, widget'ın görünmesini
 * istediğin her HTML sayfasına ekle:
 *
 *   <link rel="stylesheet" href="css/cinebot-widget.css">
 *   ...
 *   <script src="js/cinebot-widget.js" defer></script>
 *
 * ÖNEMLİ: Aşağıdaki API_BASE_URL sabitini kendi backend adresinle
 * (Flutter tarafında ai_chat_service.dart'a yazdığın Render URL'i ile
 * AYNI adres) değiştirmen gerekiyor.
 */
(function () {
  'use strict';

  // --- AYARLAR: KENDİ BACKEND ADRESİNLE DEĞİŞTİR ---
  var API_BASE_URL = 'https://cinematchbotai.onrender.com';
  var CHAT_ENDPOINT = API_BASE_URL + '/api/chat';
  var RATE_ENDPOINT_BASE = API_BASE_URL + '/api/sessions/'; 

  // TMDB'de arama yapmak için (film kartlarını tıklanabilir yapmak amacıyla,
  // site ayrı bir film detay sayfasına sahip olmadığı için TMDB'ye linkliyoruz).
  var TMDB_SEARCH_URL = 'https://www.themoviedb.org/search?query=';

  var STORAGE_KEY = 'cinebot_visitor_id';

  // -----------------------------------------------------------------------
  // Ziyaretçi kimliği (backend'in konuşma geçmişini kişiye özel tutması için)
  // -----------------------------------------------------------------------
  function getVisitorId() {
    try {
      var id = localStorage.getItem(STORAGE_KEY);
      if (!id) {
        id = 'web_' + (window.crypto && crypto.randomUUID
          ? crypto.randomUUID()
          : Date.now() + '_' + Math.random().toString(16).slice(2));
        localStorage.setItem(STORAGE_KEY, id);
      }
      return id;
    } catch (e) {
      // localStorage kapalıysa (gizli sekme vb.) oturum boyunca sabit kalan bir id üret.
      return 'web_' + Date.now();
    }
  }

  function escapeHtml(str) {
    var div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  }

  // -----------------------------------------------------------------------
  // Widget DOM'unu oluştur
  // -----------------------------------------------------------------------
  function buildWidget() {
    var launcher = document.createElement('button');
    launcher.id = 'cinebot-launcher';
    launcher.setAttribute('aria-label', 'CineBot ile konuş');
    launcher.innerHTML =
      '<svg viewBox="0 0 24 24"><path d="M12 2a5 5 0 0 0-5 5v1H6a3 3 0 0 0-3 3v6a3 3 0 0 0 3 3h1v-2H6a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-1v2h1a3 3 0 0 0 3-3v-6a3 3 0 0 0-3-3h-1V7a5 5 0 0 0-5-5Zm-2 7a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Zm4 0a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM9 15h6a3 3 0 0 1-6 0Z"/></svg>' +
      '<span class="cinebot-dot" id="cinebot-unread-dot" style="display:none"></span>';

    var panel = document.createElement('div');
    panel.id = 'cinebot-panel';
    panel.innerHTML =
      '<div id="cinebot-header">' +
      '  <div class="cinebot-avatar"><svg viewBox="0 0 24 24"><path d="M12 2a5 5 0 0 0-5 5v1H6a3 3 0 0 0-3 3v6a3 3 0 0 0 3 3h1v-2H6a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-1v2h1a3 3 0 0 0 3-3v-6a3 3 0 0 0-3-3h-1V7a5 5 0 0 0-5-5Zm-2 7a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Zm4 0a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM9 15h6a3 3 0 0 1-6 0Z"/></svg></div>' +
      '  <div>' +
      '    <div class="cinebot-title">CineBot</div>' +
      '    <div class="cinebot-subtitle">Bir film tarif et; birlikte bakalım.</div>' +
      '  </div>' +
      '  <div id="cinebot-header-actions">' +
      '    <button id="cinebot-voice-toggle" title="Cevapları sesli oku" aria-label="Sesli okumayı aç/kapat">' +
      '      <svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3Zm13.5 3a4.5 4.5 0 0 0-2.5-4.03v8.06A4.5 4.5 0 0 0 16.5 12Z"/></svg>' +
      '    </button>' +
      '    <button id="cinebot-close-btn" title="Kapat" aria-label="Sohbeti kapat">' +
      '      <svg viewBox="0 0 24 24"><path d="M18.3 5.71 12 12l6.3 6.29-1.41 1.42L10.59 13.4l-6.29 6.3-1.42-1.41L9.17 12 2.88 5.71 4.3 4.29l6.29 6.3 6.29-6.3z"/></svg>' +
      '    </button>' +
      '  </div>' +
      '</div>' +
      '<div id="cinebot-messages"></div>' +
      '<div id="cinebot-inputbar">' +
      '  <button id="cinebot-mic-btn" title="Sesli mesaj" aria-label="Mikrofonla konuş">' +
      '    <svg viewBox="0 0 24 24"><path d="M12 14a3 3 0 0 0 3-3V6a3 3 0 0 0-6 0v5a3 3 0 0 0 3 3Zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-3.08A7 7 0 0 0 19 11h-2Z"/></svg>' +
      '  </button>' +
      '  <input id="cinebot-input" type="text" placeholder="Aklındaki filmi tarif et..." autocomplete="off" />' +
      '  <button id="cinebot-send-btn" title="Gönder" aria-label="Gönder">' +
      '    <svg viewBox="0 0 24 24"><path d="M2 21 23 12 2 3v7l15 2-15 2z"/></svg>' +
      '  </button>' +
      '</div>';

    document.body.appendChild(launcher);
    document.body.appendChild(panel);
    return { launcher: launcher, panel: panel };
  }

  // -----------------------------------------------------------------------
  // Ana widget mantığı
  // -----------------------------------------------------------------------
  function initCinebot() {
    var dom = buildWidget();
    var launcher = dom.launcher;
    var panel = dom.panel;
    var messagesEl = panel.querySelector('#cinebot-messages');
    var inputEl = panel.querySelector('#cinebot-input');
    var sendBtn = panel.querySelector('#cinebot-send-btn');
    var micBtn = panel.querySelector('#cinebot-mic-btn');
    var closeBtn = panel.querySelector('#cinebot-close-btn');
    var voiceToggleBtn = panel.querySelector('#cinebot-voice-toggle');
    var unreadDot = launcher.querySelector('#cinebot-unread-dot');

    var visitorId = getVisitorId();
    var isOpen = false;
    var isSending = false;
    var hasGreeted = false;
    var voiceReplyEnabled = false;

    var currentSessionId = null;
    var hasConversation = false;
    var hasRated = false;
    // --- Web Speech API desteği (mikrofon girişi + sesli okuma) ---
    var SpeechRecognitionCtor = window.SpeechRecognition || window.webkitSpeechRecognition;
    var recognition = null;
    var isRecording = false;
    if (SpeechRecognitionCtor) {
      recognition = new SpeechRecognitionCtor();
      recognition.lang = 'tr-TR';
      recognition.interimResults = false;
      recognition.maxAlternatives = 1;
    } else {
      micBtn.style.display = 'none'; // Tarayıcı desteklemiyorsa mikrofon butonunu gizle
    }

    var synth = window.speechSynthesis || null;
    if (!synth) voiceToggleBtn.style.display = 'none';

    function speak(text) {
      if (!synth || !voiceReplyEnabled || !text) return;
      try {
        synth.cancel(); // önceki okumayı kes
        var utter = new SpeechSynthesisUtterance(text);
        utter.lang = 'tr-TR';
        synth.speak(utter);
      } catch (e) {}
    }

    // --- Mesaj render yardımcıları ---
    function scrollToBottom() {
      messagesEl.scrollTop = messagesEl.scrollHeight;
    }

    function addMessage(text, isMine) {
      var row = document.createElement('div');
      row.className = 'cinebot-row' + (isMine ? ' cinebot-mine' : '');

      var html = '';
      if (!isMine) {
        html +=
          '<div class="cinebot-mini-avatar"><svg viewBox="0 0 24 24"><path d="M12 2a5 5 0 0 0-5 5v1H6a3 3 0 0 0-3 3v6a3 3 0 0 0 3 3h1v-2H6a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-1v2h1a3 3 0 0 0 3-3v-6a3 3 0 0 0-3-3h-1V7a5 5 0 0 0-5-5Zm-2 7a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Zm4 0a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM9 15h6a3 3 0 0 1-6 0Z"/></svg></div>';
      }
      html += '<div class="cinebot-bubble">' + escapeHtml(text) + '</div>';
      row.innerHTML = html;
      messagesEl.appendChild(row);
      scrollToBottom();
      return row;
    }

    function addMovieChips(titles) {
      if (!titles || !titles.length) return;
      var wrap = document.createElement('div');
      wrap.className = 'cinebot-movies';
      titles.forEach(function (title) {
        var a = document.createElement('a');
        a.className = 'cinebot-movie-chip';
        a.href = TMDB_SEARCH_URL + encodeURIComponent(title);
        a.target = '_blank';
        a.rel = 'noopener';
        a.textContent = '🎬 ' + title;
        wrap.appendChild(a);
      });
      messagesEl.appendChild(wrap);
      scrollToBottom();
    }

    function addTypingIndicator() {
      var row = document.createElement('div');
      row.className = 'cinebot-row';
      row.id = 'cinebot-typing-row';
      row.innerHTML =
        '<div class="cinebot-mini-avatar"><svg viewBox="0 0 24 24"><path d="M12 2a5 5 0 0 0-5 5v1H6a3 3 0 0 0-3 3v6a3 3 0 0 0 3 3h1v-2H6a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-1v2h1a3 3 0 0 0 3-3v-6a3 3 0 0 0-3-3h-1V7a5 5 0 0 0-5-5Zm-2 7a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3Zm4 0a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3ZM9 15h6a3 3 0 0 1-6 0Z"/></svg></div>' +
        '<div class="cinebot-bubble"><div class="cinebot-typing"><span></span><span></span><span></span></div></div>';
      messagesEl.appendChild(row);
      scrollToBottom();
    }

    function removeTypingIndicator() {
      var row = document.getElementById('cinebot-typing-row');
      if (row) row.remove();
    }

    // --- Backend çağrısı ---
    function sendMessage(rawText) {
      var text = (rawText || '').trim();
      if (!text || isSending) return;

      inputEl.value = '';
      addMessage(text, true);
      isSending = true;
      sendBtn.disabled = true;
      addTypingIndicator();

      fetch(CHAT_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: text,
          user_id: visitorId,
          username: 'Web Ziyaretçisi',
        }),
      })
        .then(function (res) {
          if (!res.ok) throw new Error('HTTP ' + res.status);
          return res.json();
        })
        .then(function (data) {
          removeTypingIndicator();
          var answer = data.bot_response || 'Üzgünüm, boş bir cevap geldi.';
          addMessage(answer, false);
          addMovieChips(data.recommended_movies);
          speak(answer);
          if (data.session_id) currentSessionId = data.session_id;
          hasConversation = true;
        })
        .catch(function () {
          removeTypingIndicator();
          addMessage(
            'Üzgünüm, şu anda asistana ulaşamıyorum. Birazdan tekrar dener misin?',
            false
          );
        })
        .finally(function () {
          isSending = false;
          sendBtn.disabled = false;
        });
    }
    // --- Değerlendirme (rating) ---
function submitRating(rating) {
  if (!currentSessionId) return;
  fetch(RATE_ENDPOINT_BASE + currentSessionId + '/rate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ rating: rating }),
  }).catch(function () {});
  hasRated = true;
}

function showRatingPrompt(onDone) {
  var overlay = document.createElement('div');
  overlay.className = 'cinebot-rating-overlay';
  overlay.innerHTML =
    '<div class="cinebot-rating-card">' +
    '  <p>Bu konuşma nasıldı?</p>' +
    '  <div class="cinebot-stars">' +
      [5, 4, 3, 2, 1]
      .map(function (n) {
        return '<button class="cinebot-star" data-rating="' + n + '" aria-label="' + n + ' yıldız">★</button>';
    })
  .join('') +
    '  </div>' +
    '  <button class="cinebot-rating-skip">Geç</button>' +
    '</div>';

  panel.appendChild(overlay);

  overlay.querySelectorAll('.cinebot-star').forEach(function (btn) {
    btn.addEventListener('click', function () {
      submitRating(parseInt(btn.getAttribute('data-rating'), 10));
      overlay.remove();
      onDone();
    });
  });
  overlay.querySelector('.cinebot-rating-skip').addEventListener('click', function () {
    overlay.remove();
    onDone();
  });
}

    // --- Panel aç/kapat ---
    function openPanel() {
      isOpen = true;
      panel.classList.add('cinebot-open');
      unreadDot.style.display = 'none';
      if (!hasGreeted) {
        hasGreeted = true;
        addMessage(
          'Merhaba. Aklındaki filmi, bir sahneyi ya da akşamın havasını anlat. CineMatch hesabıyla ilgili sorular da olur.',
          false
        );
      }
      setTimeout(function () { inputEl.focus(); }, 150);
    }
    function closePanel() {
      isOpen = false;
      panel.classList.remove('cinebot-open');
    }

    launcher.addEventListener('click', function () {
      isOpen ? closePanel() : openPanel();
    });
    closeBtn.addEventListener('click', function () {
  if (hasConversation && currentSessionId && !hasRated) {
    showRatingPrompt(function () {
      closePanel();
      // Bir sonraki sohbet için sıfırla
      hasConversation = false;
      hasRated = false;
      currentSessionId = null;
    });
  } else {
    closePanel();
  }
});

    sendBtn.addEventListener('click', function () {
      sendMessage(inputEl.value);
    });
    inputEl.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') sendMessage(inputEl.value);
    });

    // --- Sesli okuma aç/kapat ---
    voiceToggleBtn.addEventListener('click', function () {
      voiceReplyEnabled = !voiceReplyEnabled;
      voiceToggleBtn.classList.toggle('cinebot-active', voiceReplyEnabled);
      if (!voiceReplyEnabled && synth) synth.cancel();
    });

    // --- Mikrofonla giriş ---
    if (recognition) {
      micBtn.addEventListener('click', function () {
        if (isRecording) {
          recognition.stop();
          return;
        }
        try {
          recognition.start();
        } catch (e) {}
      });
      recognition.addEventListener('start', function () {
        isRecording = true;
        micBtn.classList.add('cinebot-recording');
      });
      recognition.addEventListener('end', function () {
        isRecording = false;
        micBtn.classList.remove('cinebot-recording');
      });
      recognition.addEventListener('result', function (event) {
        var transcript = event.results[0][0].transcript;
        if (transcript) sendMessage(transcript);
      });
      recognition.addEventListener('error', function () {
        isRecording = false;
        micBtn.classList.remove('cinebot-recording');
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initCinebot);
  } else {
    initCinebot();
  }
})();
