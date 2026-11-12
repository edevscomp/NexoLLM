// Shared Aurora/Glass Desktop UI for Windows 10/11 & Linux (Tauri v2 + nexollm-core).
// Includes 6 active languages (EN, IT, ES, FR, DE, PT), soft pastel stacked histogram with
// fade-in/fade-out tooltip, clean Web Lookup behavior, universal audio notice, and wrapping 9-slide Tour.

type LangCode = "en" | "it" | "es" | "fr" | "de" | "pt";
type TopGroup = "home" | "engine" | "mind" | "input" | "apps" | "about";

interface LanguageMeta {
  iso: LangCode;
  code: string;
  flag: string;
  label: string;
}

const LANGUAGES: LanguageMeta[] = [
  { iso: "en", code: "EN", flag: "🇬🇧", label: "English" },
  { iso: "it", code: "IT", flag: "🇮🇹", label: "Italiano" },
  { iso: "es", code: "ES", flag: "🇪🇸", label: "Español" },
  { iso: "fr", code: "FR", flag: "🇫🇷", label: "Français" },
  { iso: "de", code: "DE", flag: "🇩🇪", label: "Deutsch" },
  { iso: "pt", code: "PT", flag: "🇵🇹", label: "Português" },
];

const UI_STRINGS: Record<LangCode, Record<string, string>> = {
  en: {
    home: "Home", engine: "Engine", mind: "Mind", input: "Input", apps: "Apps", about: "About",
    overview: "Overview", insights: "Insights", behavior: "Behavior", models: "Models", power: "Power",
    awareness: "Awareness", memory: "Memory & Style",
    tour: "Tour", restart: "Restart", ready: "Ready",
    wordsWritten: "words written", last7Days: "Last 7 Days", byDay: "By Day", activity: "Activity", wordsByApp: "Words by App",
    webLookup: "Web Lookup", webLookupDetail: "Look up selected text or questions with ⌃⌥L using Wikipedia, Wiktionary and news headlines.",
    sysPred: "System inline predictions", sysAuto: "System autocorrect",
    earlyTitle: "Early-stage release",
    earlyBody: "NexoLLM is in active development. It is designed for reliable everyday writing, but occasional rough edges or imprecise suggestions may still occur. Your feedback helps refine every update.",
    assistantTagline: "On-device AI writing assistant.",
    audioConsentTitle: "Audio Context — Privacy & Responsibility",
    audioResp: "Capturing or transcribing other people's voices may be subject to privacy and consent rules. Use this feature only for your own voice, for public content, when participants are informed and consent, or when you have appropriate authorization. Never use it to capture private conversations covertly.",
    skip: "Skip", back: "Back", next: "Next", finish: "Start Using NexoLLM",
    contributors: "Contributors: EdevS · Claude · Gemini",
    madeBy: "Made by EdevS. Free and open source (GNU GPL v3).",
    reportBug: "Report a Bug", cancel: "Cancel", copyReport: "Copy Report",
  },
  it: {
    home: "Home", engine: "Motore", mind: "Mente", input: "Input", apps: "App", about: "Info",
    overview: "Panoramica", insights: "Statistiche", behavior: "Comportamento", models: "Modelli", power: "Energia",
    awareness: "Contesto", memory: "Memoria e stile",
    tour: "Tour", restart: "Riavvia", ready: "Pronto",
    wordsWritten: "parole scritte", last7Days: "Ultimi 7 giorni", byDay: "Per giorno", activity: "Attività", wordsByApp: "Parole per app",
    webLookup: "Ricerca Web", webLookupDetail: "Cerca il testo selezionato o rispondi a domande con ⌃⌥L usando Wikipedia, Wikizionario e notizie.",
    sysPred: "Predizioni in linea di sistema", sysAuto: "Correzione automatica di sistema",
    earlyTitle: "Progetto nelle fasi iniziali",
    earlyBody: "NexoLLM è in attivo sviluppo. È progettato per la scrittura quotidiana, ma potrebbero ancora presentarsi piccole imperfezioni o suggerimenti imprecisi. I tuoi feedback aiutano a perfezionare ogni aggiornamento.",
    assistantTagline: "Assistente di scrittura IA sul dispositivo.",
    audioConsentTitle: "Contesto audio — Privacy e responsabilità",
    audioResp: "Acquisire o trascrivere la voce di altre persone può essere soggetto a regole su privacy e consenso. Usa questa funzione solo per la tua voce, per contenuti pubblici, quando i partecipanti sono informati e acconsentono, o con autorizzazione adeguata. Non usarla mai di nascosto.",
    skip: "Salta", back: "Indietro", next: "Avanti", finish: "Inizia a usare NexoLLM",
    contributors: "Contributors: EdevS · Claude · Gemini",
    madeBy: "Creato da EdevS. Gratuito e open source (GNU GPL v3).",
    reportBug: "Segnala un bug", cancel: "Annulla", copyReport: "Copia resoconto",
  },
  es: {
    home: "Inicio", engine: "Motor", mind: "Mente", input: "Entrada", apps: "Apps", about: "Acerca de",
    overview: "Resumen", insights: "Estadísticas", behavior: "Comportamiento", models: "Modelos", power: "Energía",
    awareness: "Contexto", memory: "Memoria y estilo",
    tour: "Tour", restart: "Reiniciar", ready: "Listo",
    wordsWritten: "palabras escritas", last7Days: "Últimos 7 días", byDay: "Por día", activity: "Actividad", wordsByApp: "Palabras por aplicación",
    webLookup: "Búsqueda web", webLookupDetail: "Consulta texto seleccionado o preguntas con ⌃⌥L usando Wikipedia, Wikcionario y titulares.",
    sysPred: "Predicciones en línea del sistema", sysAuto: "Autocorrección del sistema",
    earlyTitle: "Versión en fase inicial",
    earlyBody: "NexoLLM está en desarrollo activo. Está diseñado para la escritura diaria, aunque aún pueden aparecer pequeños detalles por pulir o sugerencias imprecisas. Tus comentarios ayudan a mejorar cada actualización.",
    assistantTagline: "Asistente de escritura con IA en el dispositivo.",
    audioConsentTitle: "Contexto de audio — Privacidad y responsabilidad",
    audioResp: "Capturar o transcribir la voz de otras personas puede estar sujeto a normas de privacidad y consentimiento. Usa esta función solo para tu propia voz, contenido público o cuando los participantes estén informados y den su consentimiento. Nunca la uses en secreto.",
    skip: "Omitir", back: "Atrás", next: "Siguiente", finish: "Empezar a usar NexoLLM",
    contributors: "Colaboradores: EdevS · Claude · Gemini",
    madeBy: "Creado por EdevS. Gratuito y de código abierto (GNU GPL v3).",
    reportBug: "Informar de un error", cancel: "Cancelar", copyReport: "Copiar informe",
  },
  fr: {
    home: "Accueil", engine: "Moteur", mind: "Esprit", input: "Saisie", apps: "Apps", about: "À propos",
    overview: "Aperçu", insights: "Statistiques", behavior: "Comportement", models: "Modèles", power: "Énergie",
    awareness: "Contexte", memory: "Mémoire et style",
    tour: "Visite", restart: "Redémarrer", ready: "Prêt",
    wordsWritten: "mots écrits", last7Days: "7 derniers jours", byDay: "Par jour", activity: "Activité", wordsByApp: "Mots par application",
    webLookup: "Recherche Web", webLookupDetail: "Recherchez le texte sélectionné ou posez une question avec ⌃⌥L via Wikipédia, Wiktionnaire et les actualités.",
    sysPred: "Prédictions en ligne du système", sysAuto: "Correction automatique du système",
    earlyTitle: "Version en phase initiale",
    earlyBody: "NexoLLM est en développement actif. Conçu pour une écriture quotidienne fiable, il peut encore présenter quelques imperfections ponctuelles. Vos retours aident à affiner chaque mise à jour.",
    assistantTagline: "Assistant d'écriture IA sur l'appareil.",
    audioConsentTitle: "Contexte audio — Confidentialité et responsabilité",
    audioResp: "La capture ou la transcription de la voix d'autrui peut être soumise à des règles de confidentialité et de consentement. Utilisez cette fonction uniquement pour votre voix, des contenus publics ou avec l'accord des participants.",
    skip: "Passer", back: "Retour", next: "Suivant", finish: "Commencer avec NexoLLM",
    contributors: "Contributeurs : EdevS · Claude · Gemini",
    madeBy: "Créé par EdevS. Gratuit et open source (GNU GPL v3).",
    reportBug: "Signaler un bug", cancel: "Annuler", copyReport: "Copier le rapport",
  },
  de: {
    home: "Start", engine: "Engine", mind: "Kontext", input: "Eingabe", apps: "Apps", about: "Über",
    overview: "Übersicht", insights: "Statistiken", behavior: "Verhalten", models: "Modelle", power: "Energie",
    awareness: "Wahrnehmung", memory: "Gedächtnis & Stil",
    tour: "Tour", restart: "Neustart", ready: "Bereit",
    wordsWritten: "Wörter geschrieben", last7Days: "Letzte 7 Tage", byDay: "Pro Tag", activity: "Aktivität", wordsByApp: "Wörter nach App",
    webLookup: "Web-Suche", webLookupDetail: "Markierten Text oder Fragen mit ⌃⌥L über Wikipedia, Wiktionary und Schlagzeilen nachschlagen.",
    sysPred: "Inline-Textvorschläge des Systems", sysAuto: "Autokorrektur des Systems",
    earlyTitle: "Frühe Entwicklungsphase",
    earlyBody: "NexoLLM wird aktiv weiterentwickelt. Es ist für zuverlässiges tägliches Schreiben konzipiert, gelegentliche Ungenauigkeiten können jedoch noch auftreten. Dein Feedback verbessert jedes Update.",
    assistantTagline: "Lokaler KI-Schreibassistent auf dem Gerät.",
    audioConsentTitle: "Audio-Kontext — Datenschutz & Verantwortung",
    audioResp: "Das Erfassen oder Transkribieren fremder Stimmen kann Datenschutz- und Einwilligungsregeln unterliegen. Nutze diese Funktion nur für deine eigene Stimme, öffentliche Inhalte oder mit informierter Zustimmung der Beteiligten.",
    skip: "Überspringen", back: "Zurück", next: "Weiter", finish: "NexoLLM starten",
    contributors: "Mitwirkende: EdevS · Claude · Gemini",
    madeBy: "Entwickelt von EdevS. Kostenlos und Open Source (GNU GPL v3).",
    reportBug: "Fehler melden", cancel: "Abbrechen", copyReport: "Bericht kopieren",
  },
  pt: {
    home: "Início", engine: "Motor", mind: "Mente", input: "Entrada", apps: "Apps", about: "Sobre",
    overview: "Visão geral", insights: "Estadísticas", behavior: "Comportamento", models: "Modelos", power: "Energia",
    awareness: "Contexto", memory: "Memória e estilo",
    tour: "Tour", restart: "Reiniciar", ready: "Pronto",
    wordsWritten: "palavras escritas", last7Days: "Últimos 7 dias", byDay: "Por dia", activity: "Atividade", wordsByApp: "Palavras por aplicação",
    webLookup: "Pesquisa Web", webLookupDetail: "Pesquise texto selecionado ou perguntas com ⌃⌥L usando Wikipédia, Wikcionário e notícias.",
    sysPred: "Previsões em linha do sistema", sysAuto: "Correção automática do sistema",
    earlyTitle: "Versão em fase inicial",
    earlyBody: "O NexoLLM está em desenvolvimento ativo. Foi concebido para a escrita diária fiável, mas pequenas imperfeições ocasionais ainda podem ocorrer. O seu feedback ajuda a aperfeiçoar cada atualização.",
    assistantTagline: "Assistente de escrita IA no dispositivo.",
    audioConsentTitle: "Contexto de áudio — Privacidade e responsabilidade",
    audioResp: "Captar ou transcrever a voz de outras pessoas pode estar sujeito a regras de privacidade e consentimento. Utilize esta funcionalidade apenas para a sua própria voz, conteúdos públicos ou com o consentimento informado dos participantes.",
    skip: "Ignorar", back: "Voltar", next: "Seguinte", finish: "Começar a usar o NexoLLM",
    contributors: "Colaboradores: EdevS · Claude · Gemini",
    madeBy: "Criado por EdevS. Gratuito e de código aberto (GNU GPL v3).",
    reportBug: " Comunicar um erro", cancel: "Cancelar", copyReport: "Copiar relatório",
  },
};

interface DayBucket {
  label: string;
  period: string;
  segments: { app: string; words: number; cssVar: string }[];
}

const SAMPLE_APPS = [
  { app: "Notes", cssVar: "var(--pastel-0)" },
  { app: "Mail", cssVar: "var(--pastel-1)" },
  { app: "Browser", cssVar: "var(--pastel-2)" },
  { app: "Editor", cssVar: "var(--pastel-3)" },
];

const SAMPLE_BUCKETS: DayBucket[] = [
  { label: "Mon", period: "Monday", segments: [{ app: "Notes", words: 95, cssVar: "var(--pastel-0)" }, { app: "Mail", words: 64, cssVar: "var(--pastel-1)" }, { app: "Browser", words: 38, cssVar: "var(--pastel-2)" }] },
  { label: "Tue", period: "Tuesday", segments: [{ app: "Notes", words: 84, cssVar: "var(--pastel-0)" }, { app: "Mail", words: 122, cssVar: "var(--pastel-1)" }, { app: "Editor", words: 45, cssVar: "var(--pastel-3)" }] },
  { label: "Wed", period: "Wednesday", segments: [{ app: "Notes", words: 148, cssVar: "var(--pastel-0)" }, { app: "Mail", words: 52, cssVar: "var(--pastel-1)" }, { app: "Browser", words: 76, cssVar: "var(--pastel-2)" }] },
  { label: "Thu", period: "Thursday", segments: [{ app: "Notes", words: 68, cssVar: "var(--pastel-0)" }, { app: "Mail", words: 90, cssVar: "var(--pastel-1)" }] },
  { label: "Fri", period: "Friday", segments: [{ app: "Notes", words: 164, cssVar: "var(--pastel-0)" }, { app: "Mail", words: 112, cssVar: "var(--pastel-1)" }, { app: "Browser", words: 58, cssVar: "var(--pastel-2)" }, { app: "Editor", words: 29, cssVar: "var(--pastel-3)" }] },
  { label: "Sat", period: "Saturday", segments: [{ app: "Notes", words: 92, cssVar: "var(--pastel-0)" }, { app: "Mail", words: 136, cssVar: "var(--pastel-1)" }] },
  { label: "Sun", period: "Sunday", segments: [{ app: "Notes", words: 118, cssVar: "var(--pastel-0)" }, { app: "Mail", words: 74, cssVar: "var(--pastel-1)" }, { app: "Browser", words: 49, cssVar: "var(--pastel-2)" }] },
];

let currentLang: LangCode = "en";
let currentGroup: TopGroup = "home";
let currentSubtab = "insights";
let webLookupEnabled = true;
let sttLanguage = "auto";
let showTour = false;
let tourStep = 0;
let showAudioConsent = false;
let showBugReport = false;
let bugReportDetails = "";

function t(key: string): string {
  return UI_STRINGS[currentLang][key] ?? UI_STRINGS.en[key] ?? key;
}

function render(): void {
  const root = document.getElementById("app");
  if (!root) return;

  root.innerHTML = `
    <header class="topbar">
      <div class="brand">
        <span class="brand-badge">I=</span>
        <span>NexoLLM</span>
      </div>
      <div class="top-actions">
        <select id="lang-select" class="btn" aria-label="Language">
          ${LANGUAGES.map((l) => `<option value="${l.iso}" ${l.iso === currentLang ? "selected" : ""}>${l.flag} ${l.code} · ${l.label}</option>`).join("")}
        </select>
        <button id="open-tour" class="btn">✦ ${t("tour")}</button>
        <button class="btn">↻ ${t("restart")}</button>
        <span class="btn">● ${t("ready")}</span>
      </div>
    </header>

    <nav class="nav-pills">
      ${(["home", "engine", "mind", "about"] as TopGroup[])
        .map((g) => `<button class="nav-pill ${currentGroup === g ? "active" : ""}" data-group="${g}">${t(g)}</button>`)
        .join("")}
    </nav>

    ${renderSubtabs()}
    <main class="page">${renderPane()}</main>
    ${showTour ? renderTourModal() : ""}
    ${showAudioConsent ? renderAudioConsentModal() : ""}
    ${showBugReport ? renderBugReportModal() : ""}
  `;

  bindEvents();
}

function renderSubtabs(): string {
  const map: Record<TopGroup, string[]> = {
    home: ["overview", "insights"],
    engine: ["behavior", "models", "power"],
    mind: ["awareness", "memory"],
    input: [],
    apps: [],
    about: [],
  };
  const tabs = map[currentGroup];
  if (!tabs.length) return "";
  return `<div class="subtabs">${tabs
    .map((id) => `<button class="subtab ${currentSubtab === id ? "active" : ""}" data-subtab="${id}">${t(id)}</button>`)
    .join("")}</div>`;
}

function renderPane(): string {
  if (currentGroup === "about") {
    return `
      <div style="text-align:center; margin: 18px 0 22px;">
        <div class="brand-badge" style="width:64px;height:64px;border-radius:16px;font-size:26px;margin:0 auto 12px;">I=</div>
        <h1 style="margin-bottom:6px;">NexoLLM</h1>
        <div class="metric-detail">Version 0.9.1</div>
        <p class="tagline" style="margin-top:8px;">${t("assistantTagline")}</p>
      </div>
      <div class="glass-card" style="margin-bottom:16px;">
        <div class="row-title">🌿 ${t("earlyTitle")}</div>
        <div class="row-detail" style="margin-top:6px;line-height:1.45;">${t("earlyBody")}</div>
      </div>
      <div class="glass-card">
        <div class="row">
          <div>
            <div class="row-title">Updates</div>
            <div class="row-detail">Ed25519 offline signature verification · Version 0.9.1</div>
          </div>
          <button class="btn">Check for Updates</button>
        </div>
      </div>
      <div style="display:flex;justify-content:center;gap:10px;margin-top:16px;flex-wrap:wrap;">
        <button id="open-bug-report" class="btn">🐞 ${t("reportBug")}</button>
        <a href="https://github.com/edevscomp/NexoLLM" target="_blank" rel="noreferrer" class="btn" style="text-decoration:none;">GitHub</a>
        <a href="https://buymeacoffee.com/edevs" target="_blank" rel="noreferrer" class="btn" style="text-decoration:none;">☕ Buy Me a Coffee</a>
      </div>
      <div style="text-align:center;margin-top:16px;font-size:12px;color:var(--text-secondary);line-height:1.6;">
        <div>${t("madeBy")}</div>
        <div>${t("contributors")}</div>
      </div>
    `;
  }

  if (currentGroup === "engine" && currentSubtab === "behavior") {
    return `
      <h1>${t("behavior")}</h1>
      <div class="section-label">${t("webLookup")}</div>
      <div class="glass-card">
        <div class="row">
          <div>
            <div class="row-title">${t("webLookup")}</div>
            <div class="row-detail">${t("webLookupDetail")}</div>
          </div>
          <input type="checkbox" id="toggle-weblookup" ${webLookupEnabled ? "checked" : ""} />
        </div>
      </div>
    `;
  }

  if (currentGroup === "engine" && currentSubtab === "models") {
    return `
      <h1>${t("models")}</h1>
      <div class="glass-card">
        <div class="row">
          <div>
            <div class="row-title">Gemma 4 E4B (Q4_K_M)</div>
            <div class="row-detail">5.3 GB · SHA-256 verified · On-device GPU</div>
          </div>
          <button class="btn">Show Models Folder</button>
        </div>
      </div>
    `;
  }

  if (currentGroup === "mind") {
    return `
      <h1>${t("awareness")}</h1>
      <div class="section-label">Audio Context (Whisper · On-Device)</div>
      <div class="glass-card">
        <div class="row">
          <div>
            <div class="row-title">Speech recognition language</div>
            <div class="row-detail">Transcribed locally on this computer with automatic RAM zeroization</div>
          </div>
          <select id="stt-lang" class="btn">
            <option value="auto" ${sttLanguage === "auto" ? "selected" : ""}>🌐 Automatic (Multilingual)</option>
            ${LANGUAGES.map((l) => `<option value="${l.iso}" ${sttLanguage === l.iso ? "selected" : ""}>${l.flag} ${l.label}</option>`).join("")}
          </select>
        </div>
        <div class="row">
          <div class="row-title">Audio Context Legal &amp; Privacy Notice</div>
          <button id="open-audio-consent" class="btn">Review Notice</button>
        </div>
      </div>
    `;
  }

  if (currentGroup === "home" && currentSubtab === "overview") {
    return `
      <h1>${t("overview")}</h1>
      <div class="section-label">Recommended</div>
      <div class="glass-card">
        <div class="row">
          <div class="row-title">${t("sysPred")}</div>
          <button class="btn">Turn Off</button>
        </div>
        <div class="row">
          <div class="row-title">${t("sysAuto")}</div>
          <button class="btn">Turn Off</button>
        </div>
      </div>
    `;
  }

  // Default: Insights with Soft Pastel Stacked Histogram + Fade Tooltip + Words by App (no progress bars)
  const totalWords = SAMPLE_BUCKETS.reduce((acc, b) => acc + b.segments.reduce((s, x) => s + x.words, 0), 0);
  const maxCol = Math.max(...SAMPLE_BUCKETS.map((b) => b.segments.reduce((s, x) => s + x.words, 0)), 1);
  const appSums = SAMPLE_APPS.map((a) => ({
    ...a,
    words: SAMPLE_BUCKETS.reduce((acc, b) => acc + (b.segments.find((s) => s.app === a.app)?.words ?? 0), 0),
  })).sort((a, b) => b.words - a.words);

  return `
    <h1>${t("insights")}</h1>

    <div class="section-label">${t("activity")}</div>
    <div class="glass-card">
      <div class="hist-header">
        <div class="hist-controls">
          <span class="btn">${t("last7Days")} ⌄</span>
          <span class="btn">${t("byDay")} ⌄</span>
        </div>
        <div class="hist-words-written">
          <strong>${totalWords.toLocaleString()}</strong>
          <span>${t("wordsWritten")}</span>
        </div>
      </div>
      <div class="histogram-wrap" id="hist-wrap">
        <div class="hist-tooltip" id="hist-tooltip"></div>
        <div class="histogram-columns" id="hist-cols">
          ${SAMPLE_BUCKETS.map(
            (b) => `
            <div class="hist-col">
              ${b.segments
                .map((seg) => {
                  const pct = Math.max(4, Math.round((seg.words / maxCol) * 100));
                  return `<div class="hist-seg" style="height:${pct}%;background:${seg.cssVar};" data-app="${seg.app}" data-words="${seg.words}" data-period="${b.period}" data-color="${seg.cssVar}"></div>`;
                })
                .join("")}
              <span class="hist-x">${b.label}</span>
            </div>`
          ).join("")}
        </div>
      </div>
    </div>

    <div class="section-label">${t("wordsByApp")}</div>
    <div class="glass-card">
      ${appSums
        .map((row) => {
          const share = Math.round((row.words / totalWords) * 100);
          return `
            <div class="app-words-row">
              <span class="pastel-dot" style="background:${row.cssVar};"></span>
              <span style="font-weight:500;">${row.app}</span>
              <span style="margin-left:auto;font-size:12.5px;">${row.words.toLocaleString()} words</span>
              <span style="width:42px;text-align:right;color:var(--text-tertiary);font-size:12px;">${share}%</span>
            </div>`;
        })
        .join("")}
    </div>
  `;
}

function renderTourModal(): string {
  const tools = ["⇧1 Improve Writing", "⇧2 Make Formal", "⇧3 Make Shorter", "⇧4 Translate"];
  return `
    <div class="modal-backdrop">
      <div class="modal-card">
        <div class="modal-scroll">
          <div class="row-title" style="font-size:18px;">NexoLLM Interactive Tour (${tourStep + 1} / 9)</div>
          <div class="row-detail">Adaptive wrapping layout across all 6 languages (${currentLang.toUpperCase()}).</div>
          <div class="flow-wrap">
            ${tools.map((label) => `<button class="btn">${label}</button>`).join("")}
          </div>
        </div>
        <div class="tour-footer">
          <div style="min-width:110px;">
            ${tourStep > 0 && tourStep < 8 ? `<button id="tour-skip" class="btn">${t("skip")}</button>` : ""}
          </div>
          <div class="tour-dots">
            ${Array.from({ length: 9 }, (_, i) => `<span class="tour-dot ${i === tourStep ? "active" : ""}"></span>`).join("")}
          </div>
          <div class="flow-wrap" style="justify-content:flex-end;min-width:160px;">
            ${tourStep > 0 && tourStep < 8 ? `<button id="tour-back" class="btn">‹ ${t("back")}</button>` : ""}
            <button id="tour-next" class="btn primary">${tourStep === 8 ? t("finish") : `${t("next")} ›`}</button>
          </div>
        </div>
      </div>
    </div>
  `;
}

function renderAudioConsentModal(): string {
  return `
    <div class="modal-backdrop" id="consent-backdrop">
      <div class="modal-card">
        <div class="modal-scroll">
          <div class="row-title" style="font-size:17px;">${t("audioConsentTitle")}</div>
          <div class="row-detail" style="line-height:1.5;">${t("audioResp")}</div>
        </div>
        <div class="tour-footer" style="justify-content:flex-end;">
          <button id="close-consent" class="btn primary">Close</button>
        </div>
      </div>
    </div>
  `;
}

function renderBugReportModal(): string {
  const isEmpty = bugReportDetails.trim().length === 0;
  return `
    <div class="modal-backdrop" id="bug-backdrop">
      <div class="modal-card">
        <div class="modal-scroll">
          <div class="row-title" style="font-size:17px;">🐞 ${t("reportBug")}</div>
          <textarea id="bug-details-input" rows="5" style="width:100%;margin-top:10px;border-radius:10px;padding:10px;background:var(--surface);color:var(--text);border:1px solid var(--border);user-select:text;">${bugReportDetails}</textarea>
        </div>
        <div class="tour-footer" style="justify-content:space-between;">
          <button id="close-bug-report" class="btn">${t("cancel")}</button>
          <button id="copy-bug-report" class="btn primary" ${isEmpty ? "disabled" : ""}>${t("copyReport")}</button>
        </div>
      </div>
    </div>
  `;
}

function bindEvents(): void {
  document.getElementById("lang-select")?.addEventListener("change", (e) => {
    currentLang = (e.target as HTMLSelectElement).value as LangCode;
    render();
  });

  document.querySelectorAll<HTMLButtonElement>(".nav-pill").forEach((btn) => {
    btn.addEventListener("click", () => {
      currentGroup = btn.dataset.group as TopGroup;
      currentSubtab = currentGroup === "home" ? "insights" : currentGroup === "engine" ? "behavior" : "awareness";
      render();
    });
  });

  document.querySelectorAll<HTMLButtonElement>(".subtab").forEach((btn) => {
    btn.addEventListener("click", () => {
      currentSubtab = btn.dataset.subtab ?? "";
      render();
    });
  });

  document.getElementById("toggle-weblookup")?.addEventListener("change", (e) => {
    webLookupEnabled = (e.target as HTMLInputElement).checked;
  });

  document.getElementById("stt-lang")?.addEventListener("change", (e) => {
    sttLanguage = (e.target as HTMLSelectElement).value;
  });

  document.getElementById("open-tour")?.addEventListener("click", () => {
    showTour = true;
    tourStep = 0;
    render();
  });
  document.getElementById("tour-skip")?.addEventListener("click", () => {
    showTour = false;
    render();
  });
  document.getElementById("tour-back")?.addEventListener("click", () => {
    tourStep = Math.max(0, tourStep - 1);
    render();
  });
  document.getElementById("tour-next")?.addEventListener("click", () => {
    if (tourStep >= 8) showTour = false;
    else tourStep += 1;
    render();
  });

  document.getElementById("open-audio-consent")?.addEventListener("click", () => {
    showAudioConsent = true;
    render();
  });
  document.getElementById("close-consent")?.addEventListener("click", () => {
    showAudioConsent = false;
    render();
  });

  document.getElementById("open-bug-report")?.addEventListener("click", () => {
    showBugReport = true;
    render();
  });
  document.getElementById("close-bug-report")?.addEventListener("click", () => {
    showBugReport = false;
    render();
  });
  document.getElementById("bug-details-input")?.addEventListener("input", (e) => {
    bugReportDetails = (e.target as HTMLTextAreaElement).value;
    const copyBtn = document.getElementById("copy-bug-report") as HTMLButtonElement | null;
    if (copyBtn) copyBtn.disabled = bugReportDetails.trim().length === 0;
  });

  // Smooth fade-in / fade-out hover tooltip on stacked pastel histogram blocks
  const cols = document.getElementById("hist-cols");
  const wrap = document.getElementById("hist-wrap");
  const tooltip = document.getElementById("hist-tooltip");
  let clearTimer: number | undefined;
  if (cols && wrap && tooltip) {
    cols.querySelectorAll<HTMLElement>(".hist-seg").forEach((seg) => {
      seg.addEventListener("mouseenter", () => {
        if (clearTimer) window.clearTimeout(clearTimer);
        cols.classList.add("has-hover");
        cols.querySelectorAll(".hist-seg.is-hovered").forEach((el) => el.classList.remove("is-hovered"));
        seg.classList.add("is-hovered");
        const wrapRect = wrap.getBoundingClientRect();
        const segRect = seg.getBoundingClientRect();
        tooltip.innerHTML = `
          <div style="display:flex;align-items:center;gap:6px;font-weight:600;font-size:12px;">
            <span class="pastel-dot" style="background:${seg.dataset.color};"></span>
            <span>${seg.dataset.app}</span>
          </div>
          <div style="font-size:11px;color:var(--text-secondary);margin-top:2px;">
            ${seg.dataset.words} words · ${seg.dataset.period}
          </div>`;
        const left = Math.min(Math.max(segRect.left - wrapRect.left + segRect.width / 2, 84), wrapRect.width - 84);
        const top = Math.max(8, segRect.top - wrapRect.top - 52);
        tooltip.style.left = `${left}px`;
        tooltip.style.top = `${top}px`;
        tooltip.classList.add("visible");
      });
      seg.addEventListener("mouseleave", () => {
        seg.classList.remove("is-hovered");
        clearTimer = window.setTimeout(() => {
          cols.classList.remove("has-hover");
          tooltip.classList.remove("visible");
        }, 60);
      });
    });
  }
}

render();
