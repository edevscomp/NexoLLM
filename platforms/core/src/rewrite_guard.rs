//! `RewriteGuard` anti-leak validation, 6-language `RewriteExamples` (zero hardcoded biographies),
//! and 6-language `Spelling` language detection and short typo fixes.

use std::collections::HashSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RewriteTool {
    Grammar,
    Formal,
    Shorter,
    Improve,
}

pub struct RewritePrompt {
    pub intro: &'static str,
    pub in_label: &'static str,
    pub out_label: &'static str,
    pub pairs: &'static [(&'static str, &'static str)],
}

pub fn rewrite_examples(tool: RewriteTool, language: &str) -> RewritePrompt {
    match (language, tool) {
        ("it", RewriteTool::Grammar) => RewritePrompt {
            intro: "Correggi solo grammatica, ortografia e punteggiatura in italiano, mantenendo tutte le frasi in italiano senza tradurre nulla.",
            in_label: "Originale",
            out_label: "Corretto",
            pairs: &[
                ("domani nn posso venire perche ho un impegno, ci sentiamo dopo", "Domani non posso venire perché ho un impegno, ci sentiamo dopo."),
                ("il file e pronto ma manca l'ultima pagina", "Il file è pronto, ma manca l'ultima pagina."),
            ],
        },
        ("it", RewriteTool::Formal) => RewritePrompt {
            intro: "Riscrivi il testo in italiano con un tono formale e professionale, mantenendo la lingua italiana.",
            in_label: "Originale",
            out_label: "Formale",
            pairs: &[
                ("ti mando il file tra poco ok?", "Le invierò il documento a breve."),
                ("domani nn ci sono, sentiamoci giovedì", "Domani non sarò disponibile: possiamo sentirci giovedì?"),
            ],
        },
        ("it", RewriteTool::Shorter) => RewritePrompt {
            intro: "Rendi il testo più breve e conciso in italiano, senza cambiare lingua.",
            in_label: "Originale",
            out_label: "Breve",
            pairs: &[
                ("Volevo solo dirti che il file che mi avevi chiesto ieri adesso è finalmente pronto.", "Il file che mi avevi chiesto è pronto."),
            ],
        },
        ("it", RewriteTool::Improve) => RewritePrompt {
            intro: "Migliora la fluidità e lo stile del testo in italiano, mantenendo tutte le informazioni e scrivendo SOLO in italiano.",
            in_label: "Originale",
            out_label: "Migliorato",
            pairs: &[
                ("Il file è pronto. Il file ha tutte le pagine. Te lo mando dopo.", "Il file è pronto e completo: te lo mando più tardi."),
            ],
        },
        ("es", RewriteTool::Grammar) => RewritePrompt {
            intro: "Corrige solo la gramática, la ortografía y la puntuación en español, sin traducir nada y manteniendo todo en español.",
            in_label: "Original",
            out_label: "Corregido",
            pairs: &[
                ("el archivo esta listo pero falta la ultima pagina", "El archivo está listo, pero falta la última página."),
            ],
        },
        ("es", _) => RewritePrompt {
            intro: "Mejora o adapta el texto en español conservando el significado y sin cambiar de idioma.",
            in_label: "Original",
            out_label: "Reescrito",
            pairs: &[
                ("El archivo está listo. El archivo tiene todas las páginas. Te lo mando luego.", "El archivo está listo y completo; te lo envío más tarde."),
            ],
        },
        ("fr", RewriteTool::Grammar) => RewritePrompt {
            intro: "Corrige uniquement la grammaire, l'orthographe et la ponctuation en français, sans rien traduire.",
            in_label: "Original",
            out_label: "Corrigé",
            pairs: &[
                ("le fichier est pret mais il manque la derniere page", "Le fichier est prêt, mais il manque la dernière page."),
            ],
        },
        ("fr", _) => RewritePrompt {
            intro: "Améliore ou adapte le texte en français en gardant le sens et sans changer de langue.",
            in_label: "Original",
            out_label: "Réécrit",
            pairs: &[
                ("Le fichier est prêt. Le fichier a toutes les pages. Je te l'envoie après.", "Le fichier est prêt et complet ; je te l'envoie plus tard."),
            ],
        },
        ("de", RewriteTool::Grammar) => RewritePrompt {
            intro: "Korrigiere nur Grammatik, Rechtschreibung und Zeichensetzung auf Deutsch, ohne etwas zu übersetzen.",
            in_label: "Original",
            out_label: "Korrigiert",
            pairs: &[
                ("die datei ist fertig aber die letzte seite fehlt", "Die Datei ist fertig, aber die letzte Seite fehlt."),
            ],
        },
        ("de", _) => RewritePrompt {
            intro: "Verbessere oder passe den Text auf Deutsch an, ohne die Bedeutung oder die Sprache zu ändern.",
            in_label: "Original",
            out_label: "Überarbeitet",
            pairs: &[
                ("Die Datei ist fertig. Die Datei hat alle Seiten. Ich schicke sie später.", "Die Datei ist vollständig und fertig; ich sende sie später."),
            ],
        },
        ("pt", RewriteTool::Grammar) => RewritePrompt {
            intro: "Corrige apenas a gramática, a ortografia e a pontuação em português, sem traduzir nada.",
            in_label: "Original",
            out_label: "Corrigido",
            pairs: &[
                ("o ficheiro esta pronto mas falta a ultima pagina", "O ficheiro está pronto, mas falta a última página."),
            ],
        },
        ("pt", _) => RewritePrompt {
            intro: "Melhora ou adapta o texto em português mantendo o significado e sem mudar de idioma.",
            in_label: "Original",
            out_label: "Reescrito",
            pairs: &[
                ("O ficheiro está pronto. O ficheiro tem todas as páginas. Envio-to mais tarde.", "O ficheiro está pronto e completo; envio-to mais tarde."),
            ],
        },
        (_, RewriteTool::Grammar) => RewritePrompt {
            intro: "Fix only grammar, spelling and punctuation in English, keeping the exact meaning.",
            in_label: "Original",
            out_label: "Corrected",
            pairs: &[
                ("the file is ready but the last page is missing", "The file is ready, but the last page is missing."),
            ],
        },
        _ => RewritePrompt {
            intro: "Improve clarity and flow in English while keeping the exact meaning.",
            in_label: "Original",
            out_label: "Improved",
            pairs: &[
                ("The file is ready. The file has all the pages. I will send it later.", "The file is ready and complete; I'll send it later."),
            ],
        },
    }
}

pub fn build_rewrite_prompt(text: &str, tool: RewriteTool, language: &str) -> String {
    let spec = rewrite_examples(tool, language);
    let mut out = String::from(spec.intro);
    out.push_str("\n\n");
    for (inp, res) in spec.pairs {
        out.push_str(&format!("{}:\n\"{}\"\n{}:\n\"{}\"\n\n", spec.in_label, inp, spec.out_label, res));
    }
    out.push_str(&format!("{}:\n\"{}\"\n{}:\n\"", spec.in_label, text, spec.out_label));
    out
}

/// Rejects echoed few-shot prompt text or runaway hallucinations on short inputs.
pub struct RewriteGuard;

impl RewriteGuard {
    pub fn max_words(original: &str, is_shorter: bool) -> usize {
        let count = original.split_whitespace().count();
        if count <= 1 {
            return 6;
        }
        if is_shorter {
            return (count + 2).max(6);
        }
        (count * 2 + 8).max(12)
    }

    pub fn is_too_short_to_rewrite(original: &str, is_translation: bool) -> bool {
        if is_translation {
            return original.trim().is_empty();
        }
        original.split_whitespace().count() <= 2
    }

    pub fn leaks_prompt(output: &str, prompt: &str, original: &str) -> bool {
        let orig_words: HashSet<String> = original
            .to_lowercase()
            .split(|c: char| !c.is_alphabetic())
            .filter(|w| w.len() >= 4)
            .map(String::from)
            .collect();
        let prompt_before_input = prompt.split("\nOriginal:\n\"").next().unwrap_or(prompt).to_lowercase();
        let out_words: Vec<String> = output
            .to_lowercase()
            .split(|c: char| !c.is_alphabetic())
            .filter(|w| w.len() >= 4 && !orig_words.contains(*w))
            .map(String::from)
            .collect();
        if out_words.len() < 3 {
            return false;
        }
        for win in out_words.windows(3) {
            let phrase = win.join(" ");
            if prompt_before_input.contains(&phrase) {
                return true;
            }
        }
        false
    }

    pub fn accepts(output: &str, original: &str, prompt: &str, is_shorter: bool) -> bool {
        let trimmed = output.trim();
        if trimmed.is_empty() {
            return false;
        }
        if trimmed.split_whitespace().count() > Self::max_words(original, is_shorter) {
            return false;
        }
        !Self::leaks_prompt(trimmed, prompt, original)
    }
}

/// Fast 6-language clause detector (`en`, `it`, `es`, `fr`, `de`, `pt`) and short slip fixer.
pub fn detect_language_code(context: &str, fallback: &str) -> &'static str {
    const EN: &[&str] = &["the", "and", "with", "this", "that", "have", "please", "thanks", "project", "morning"];
    const IT: &[&str] = &["ciao", "grazie", "della", "questo", "questa", "riunione", "oggi", "domani", "perché", "documento"];
    const ES: &[&str] = &["hola", "gracias", "mañana", "reunión", "proyecto", "también", "porque", "están", "después"];
    const FR: &[&str] = &["bonjour", "merci", "demain", "réunion", "équipe", "nous", "avons", "avec", "toute", "fichier"];
    const DE: &[&str] = &["hallo", "morgen", "haben", "treffen", "dieses", "projekt", "wichtiges", "nicht", "bitte", "datei"];
    const PT: &[&str] = &["olá", "amanhã", "reunião", "ficheiro", "obrigado", "também", "não", "temos", "projeto"];

    let markers: [(&'static str, &[&str]); 6] = [
        ("en", EN),
        ("it", IT),
        ("es", ES),
        ("fr", FR),
        ("de", DE),
        ("pt", PT),
    ];

    let words: Vec<String> = context
        .to_lowercase()
        .split(|c: char| !c.is_alphabetic())
        .filter(|w| w.len() >= 2)
        .map(String::from)
        .collect();

    let mut best_code: Option<&'static str> = None;
    let mut best_score = 0usize;
    for (code, list) in markers {
        let score = words.iter().filter(|w| list.contains(&w.as_str())).count();
        if score > best_score {
            best_score = score;
            best_code = Some(code);
        }
    }
    best_code.unwrap_or(match fallback {
        "it" => "it",
        "es" => "es",
        "fr" => "fr",
        "de" => "de",
        "pt" => "pt",
        _ => "en",
    })
}

pub fn fix_short_typo(word: &str) -> Option<String> {
    let lower = word.to_lowercase();
    let replacement = match lower.as_str() {
        "cao" => "ciao",
        "teh" => "the",
        "adn" => "and",
        "perche'" => "perché",
        _ => return None,
    };
    if word.chars().next().map(|c| c.is_uppercase()).unwrap_or(false) {
        let mut chars = replacement.chars();
        let first = chars.next().unwrap().to_uppercase().collect::<String>();
        Some(first + chars.as_str())
    } else {
        Some(replacement.to_string())
    }
}
