// Firebase başlatma, oturum kalıcılığı ve yetki önbelleği admin-shared.js
// içinde ortaklaştırıldı (bkz. js/admin-shared.js).
const { auth, db, functions } = CineAdmin;
const authPersistenceReady = CineAdmin.persistenceReady;

const QUESTION_PAGE_SIZE = 60;
let questionPageSize = QUESTION_PAGE_SIZE;

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
  questionList: document.getElementById("questionList"),
  questionCount: document.getElementById("questionCount"),
  questionSearch: document.getElementById("questionSearch"),
  weekFilter: document.getElementById("weekFilter"),
  activeFilter: document.getElementById("activeFilter"),
  newQuestionButton: document.getElementById("newQuestionButton"),
  currentWeekButton: document.getElementById("currentWeekButton"),
  nextWeekButton: document.getElementById("nextWeekButton"),
  questionForm: document.getElementById("questionForm"),
  questionId: document.getElementById("questionId"),
  weekId: document.getElementById("weekId"),
  difficulty: document.getElementById("difficulty"),
  isActive: document.getElementById("isActive"),
  question: document.getElementById("question"),
  option0: document.getElementById("option0"),
  option1: document.getElementById("option1"),
  option2: document.getElementById("option2"),
  option3: document.getElementById("option3"),
  correctIndex: document.getElementById("correctIndex"),
  imageUrl: document.getElementById("imageUrl"),
  explanation: document.getElementById("explanation"),
  deleteButton: document.getElementById("deleteButton"),
  saveButton: document.getElementById("saveButton"),
  saveMessage: document.getElementById("saveMessage"),
  bulkWeekId: document.getElementById("bulkWeekId"),
  bulkJson: document.getElementById("bulkJson"),
  bulkSaveButton: document.getElementById("bulkSaveButton"),
  bulkMessage: document.getElementById("bulkMessage"),
  loadSampleButton: document.getElementById("loadSampleButton"),
  loadMoreQuestionsButton: document.getElementById("loadMoreQuestionsButton"),
};

let unsubscribeQuestions = null;
let questions = [];

const { setMessage, escapeHtml, isPermissionError } = CineAdmin;

function getWeekIdFor(date) {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.floor(((d - yearStart) / 86400000) / 7) + 1;
  return `${d.getUTCFullYear()}_W${week}`;
}

function currentWeekId() {
  return getWeekIdFor(new Date());
}

function nextWeekId() {
  const date = new Date();
  date.setDate(date.getDate() + 7);
  return getWeekIdFor(date);
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

function updateWeekButtons() {
  const current = currentWeekId();
  const next = nextWeekId();
  els.currentWeekButton.textContent = `Bu Hafta: ${current}`;
  els.nextWeekButton.textContent = `Gelecek Hafta: ${next}`;
  if (!els.bulkWeekId.value) els.bulkWeekId.value = current;
}

function resetForm() {
  els.questionForm.reset();
  els.questionId.value = "";
  els.weekId.value = currentWeekId();
  els.bulkWeekId.value = els.bulkWeekId.value || currentWeekId();
  els.difficulty.value = "orta";
  els.correctIndex.value = "0";
  els.isActive.checked = true;
  els.deleteButton.disabled = true;
  setMessage(els.saveMessage, "");
  markActiveQuestion("");
}

function fillForm(question) {
  const options = Array.isArray(question.options) ? question.options : [];
  els.questionId.value = question.id;
  els.weekId.value = question.weekId || currentWeekId();
  els.difficulty.value = question.difficulty || "orta";
  els.isActive.checked = question.isActive !== false;
  els.question.value = question.question || "";
  els.option0.value = options[0] || "";
  els.option1.value = options[1] || "";
  els.option2.value = options[2] || "";
  els.option3.value = options[3] || "";
  els.correctIndex.value = String(question.correctIndex ?? 0);
  els.imageUrl.value = question.imageUrl || "";
  els.explanation.value = question.explanation || "";
  els.deleteButton.disabled = false;
  setMessage(els.saveMessage, "");
  markActiveQuestion(question.id);
}

function collectForm() {
  return {
    id: els.questionId.value.trim(),
    weekId: els.weekId.value.trim(),
    difficulty: els.difficulty.value,
    isActive: els.isActive.checked,
    question: els.question.value.trim(),
    options: [
      els.option0.value.trim(),
      els.option1.value.trim(),
      els.option2.value.trim(),
      els.option3.value.trim(),
    ],
    correctIndex: Number(els.correctIndex.value),
    imageUrl: els.imageUrl.value.trim(),
    explanation: els.explanation.value.trim(),
  };
}

function markActiveQuestion(id) {
  document.querySelectorAll(".question-item").forEach((button) => {
    button.classList.toggle("active", button.dataset.id === id);
  });
}

function updateWeekFilter() {
  const selected = els.weekFilter.value || "all";
  const weeks = [...new Set(questions.map((item) => item.weekId).filter(Boolean))].sort().reverse();
  const options = ['<option value="all">Tüm haftalar</option>']
    .concat(weeks.map((week) => `<option value="${escapeHtml(week)}">${escapeHtml(week)}</option>`));
  els.weekFilter.innerHTML = options.join("");
  els.weekFilter.value = weeks.includes(selected) ? selected : "all";
}

function renderQuestions() {
  updateWeekFilter();
  const search = (els.questionSearch.value || "").trim().toLocaleLowerCase("tr-TR");
  const weekFilter = els.weekFilter.value;
  const activeFilter = els.activeFilter.value;

  const visible = questions.filter((item) => {
    const weekMatches = weekFilter === "all" || item.weekId === weekFilter;
    const activeMatches =
      activeFilter === "all" ||
      (activeFilter === "active" && item.isActive !== false) ||
      (activeFilter === "inactive" && item.isActive === false);
    const haystack = [
      item.question,
      Array.isArray(item.options) ? item.options.join(" ") : "",
      item.weekId,
      item.difficulty,
    ].join(" ").toLocaleLowerCase("tr-TR");
    return weekMatches && activeMatches && (!search || haystack.includes(search));
  });

  els.questionCount.textContent = `${visible.length} / ${questions.length} soru`;

  if (!questions.length) {
    els.questionList.innerHTML = '<p class="message">Henüz soru yok.</p>';
    return;
  }
  if (!visible.length) {
    els.questionList.innerHTML = '<p class="message">Filtreye uygun soru yok.</p>';
    return;
  }

  els.questionList.innerHTML = "";
  visible.forEach((item) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "question-item";
    button.dataset.id = item.id;
    const state = item.isActive === false ? "Kapalı" : "Yayında";
    const stateClass = item.isActive === false ? "inactive" : "";
    button.innerHTML = `
      <strong>${escapeHtml(item.question || "Başlıksız soru")}</strong>
      <span class="${stateClass}">${escapeHtml(item.weekId || "-")} · ${escapeHtml(item.difficulty || "orta")} · ${state}</span>
    `;
    button.addEventListener("click", () => fillForm(item));
    els.questionList.appendChild(button);
  });
  markActiveQuestion(els.questionId.value);
}

function subscribeQuestions() {
  if (unsubscribeQuestions) unsubscribeQuestions();
  unsubscribeQuestions = db
    .collection("trivia_questions")
    .orderBy("createdAt", "desc")
    .limit(questionPageSize)
    .onSnapshot(
      (snapshot) => {
        questions = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
        renderQuestions();
        if (els.loadMoreQuestionsButton) {
          els.loadMoreQuestionsButton.classList.toggle(
            "hidden",
            snapshot.docs.length < questionPageSize
          );
        }
      },
      (error) => {
        els.questionList.innerHTML = `<p class="message error">${escapeHtml(error.message)}</p>`;
      }
    );
}

function sampleQuestions() {
  const weekId = els.bulkWeekId.value.trim() || currentWeekId();
  return [
    {
      weekId,
      question: "Matrix filminde Neo'ya sunulan hapların renkleri hangileridir?",
      options: ["Mor ve turuncu", "Siyah ve beyaz", "Kırmızı ve mavi", "Yeşil ve sarı"],
      correctIndex: 2,
      difficulty: "kolay",
      isActive: true,
      imageUrl: "",
      explanation: "Morpheus, Neo'ya kırmızı ve mavi hap seçeneklerini sunar.",
    },
    {
      weekId,
      question: "Fight Club filminin birinci kuralı nedir?",
      options: ["Asla kaybetme", "Fight Club hakkında konuşma", "Gömleksiz dövüşme", "Herkes sırayla dövüşür"],
      correctIndex: 1,
      difficulty: "kolay",
      isActive: true,
      imageUrl: "",
      explanation: "",
    },
  ];
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
els.newQuestionButton.addEventListener("click", resetForm);
els.questionSearch.addEventListener("input", renderQuestions);
els.weekFilter.addEventListener("change", renderQuestions);
els.activeFilter.addEventListener("change", renderQuestions);
if (els.loadMoreQuestionsButton) {
  els.loadMoreQuestionsButton.addEventListener("click", () => {
    questionPageSize += QUESTION_PAGE_SIZE;
    subscribeQuestions();
  });
}
els.currentWeekButton.addEventListener("click", () => {
  els.weekId.value = currentWeekId();
  els.bulkWeekId.value = currentWeekId();
});
els.nextWeekButton.addEventListener("click", () => {
  els.weekId.value = nextWeekId();
  els.bulkWeekId.value = nextWeekId();
});

els.questionForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  els.saveButton.disabled = true;
  setMessage(els.saveMessage, "Kaydediliyor...");

  try {
    const saveTriviaQuestion = functions.httpsCallable("saveTriviaQuestion");
    const result = await saveTriviaQuestion(collectForm());
    if (result.data && result.data.id) els.questionId.value = result.data.id;
    setMessage(els.saveMessage, "Kaydedildi.", "success");
  } catch (error) {
    setMessage(els.saveMessage, error.message, "error");
  } finally {
    els.saveButton.disabled = false;
  }
});

els.deleteButton.addEventListener("click", async () => {
  const id = els.questionId.value.trim();
  if (!id) return;
  if (!window.confirm("Bu soruyu kalıcı olarak silmek istiyor musunuz?")) return;

  els.deleteButton.disabled = true;
  setMessage(els.saveMessage, "Siliniyor...");

  try {
    const deleteTriviaQuestion = functions.httpsCallable("deleteTriviaQuestion");
    await deleteTriviaQuestion({ id });
    resetForm();
    setMessage(els.saveMessage, "Silindi.", "success");
  } catch (error) {
    els.deleteButton.disabled = false;
    setMessage(els.saveMessage, error.message, "error");
  }
});

els.loadSampleButton.addEventListener("click", () => {
  els.bulkJson.value = JSON.stringify(sampleQuestions(), null, 2);
});

els.bulkSaveButton.addEventListener("click", async () => {
  const weekId = els.bulkWeekId.value.trim();
  let parsed;
  try {
    parsed = JSON.parse(els.bulkJson.value);
  } catch (error) {
    setMessage(els.bulkMessage, "JSON formatı hatalı.", "error");
    return;
  }

  const questionsToSave = (Array.isArray(parsed) ? parsed : []).map((item) => ({
    ...item,
    weekId: item.weekId || weekId,
  }));

  els.bulkSaveButton.disabled = true;
  setMessage(els.bulkMessage, "Yükleniyor...");

  try {
    const bulkSaveTriviaQuestions = functions.httpsCallable("bulkSaveTriviaQuestions");
    const result = await bulkSaveTriviaQuestions({ questions: questionsToSave });
    const count = result.data && result.data.ids ? result.data.ids.length : questionsToSave.length;
    setMessage(els.bulkMessage, `${count} soru yüklendi.`, "success");
  } catch (error) {
    setMessage(els.bulkMessage, error.message, "error");
  } finally {
    els.bulkSaveButton.disabled = false;
  }
});

auth.onAuthStateChanged(async (user) => {
  if (unsubscribeQuestions) {
    unsubscribeQuestions();
    unsubscribeQuestions = null;
  }

  if (!user) {
    showLogin();
    return;
  }

  try {
    await authPersistenceReady;
    await CineAdmin.requireRole(user, "triviaAdmin", () =>
      functions.httpsCallable("isTriviaAdmin")()
    );
    showAdmin(user);
    questionPageSize = QUESTION_PAGE_SIZE;
    updateWeekButtons();
    resetForm();
    subscribeQuestions();
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
