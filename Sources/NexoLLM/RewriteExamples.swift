import Foundation

/// Few-shot prompts of the writing tools (Fix Grammar, Make Formal, Make Shorter, Improve Writing), one set per
/// language, so a rewrite always stays in the language of the text.
///
/// The examples are deliberately plain (a file, a meeting, the weather) and contain no people or biographies:
/// small models sometimes echo an example, and `RewriteGuard` rejects any answer that borrows from the prompt.
enum RewriteExamples {
    enum Tool: CaseIterable { case grammar, formal, shorter, improve }

    struct Prompt {
        let intro: String
        let inLabel: String
        let outLabel: String
        let pairs: [(String, String)]
    }

    static let languages = ["en", "it", "es", "fr", "de", "pt"]

    /// The prompt for `tool` in `language` (ISO code); unknown languages use English.
    static func prompt(_ tool: Tool, language: String) -> Prompt {
        switch (language, tool) {
        // MARK: Italian
        case ("it", .grammar):
            return Prompt(intro: "Correggi solo grammatica, ortografia e punteggiatura in italiano, mantenendo tutte le frasi in italiano senza tradurre nulla.",
                          inLabel: "Originale", outLabel: "Corretto", pairs: [
                            ("domani nn posso venire perche ho un impegno, ci sentiamo dopo", "Domani non posso venire perché ho un impegno, ci sentiamo dopo."),
                            ("il file e pronto ma manca l'ultima pagina", "Il file è pronto, ma manca l'ultima pagina."),
                          ])
        case ("it", .formal):
            return Prompt(intro: "Riscrivi il testo in italiano con un tono formale e professionale, mantenendo la lingua italiana.",
                          inLabel: "Originale", outLabel: "Formale", pairs: [
                            ("ti mando il file tra poco ok?", "Le invierò il documento a breve."),
                            ("domani nn ci sono, sentiamoci giovedì", "Domani non sarò disponibile: possiamo sentirci giovedì?"),
                          ])
        case ("it", .shorter):
            return Prompt(intro: "Rendi il testo più breve e conciso in italiano, senza cambiare lingua.",
                          inLabel: "Originale", outLabel: "Breve", pairs: [
                            ("Volevo solo dirti che il file che mi avevi chiesto ieri adesso è finalmente pronto.", "Il file che mi avevi chiesto è pronto."),
                            ("A causa del fatto che pioveva molto forte abbiamo deciso di restare a casa.", "Per via della forte pioggia siamo rimasti a casa."),
                          ])
        case ("it", .improve):
            return Prompt(intro: "Migliora la fluidità e lo stile del testo in italiano, mantenendo tutte le informazioni e scrivendo SOLO in italiano.",
                          inLabel: "Originale", outLabel: "Migliorato", pairs: [
                            ("Il file è pronto. Il file ha tutte le pagine. Te lo mando dopo.", "Il file è pronto e completo: te lo mando più tardi."),
                            ("Questa parte del testo non è tanto chiara da leggere e vorrei sistemarla.", "Questa sezione risulta poco scorrevole e vorrei renderla più chiara."),
                          ])

        // MARK: Spanish
        case ("es", .grammar):
            return Prompt(intro: "Corrige solo la gramática, la ortografía y la puntuación en español, sin traducir nada y manteniendo todo en español.",
                          inLabel: "Original", outLabel: "Corregido", pairs: [
                            ("mañana no puedo ir porque tengo un compromiso, hablamos despues", "Mañana no puedo ir porque tengo un compromiso; hablamos después."),
                            ("el archivo esta listo pero falta la ultima pagina", "El archivo está listo, pero falta la última página."),
                          ])
        case ("es", .formal):
            return Prompt(intro: "Reescribe el texto en español con un tono formal y profesional, sin cambiar de idioma.",
                          inLabel: "Original", outLabel: "Formal", pairs: [
                            ("te paso el archivo en un rato vale?", "Le enviaré el documento en breve."),
                            ("mañana no estoy, hablamos el jueves", "Mañana no estaré disponible. ¿Podríamos hablar el jueves?"),
                          ])
        case ("es", .shorter):
            return Prompt(intro: "Haz el texto más breve y conciso en español, sin cambiar de idioma.",
                          inLabel: "Original", outLabel: "Breve", pairs: [
                            ("Solo quería decirte que el archivo que me pediste ayer por fin ya está listo.", "El archivo que pediste está listo."),
                            ("Debido al hecho de que llovía muchísimo, decidimos quedarnos en casa.", "Por la lluvia, nos quedamos en casa."),
                          ])
        case ("es", .improve):
            return Prompt(intro: "Mejora la claridad y la fluidez del texto en español, conservando toda la información y escribiendo SOLO en español.",
                          inLabel: "Original", outLabel: "Mejorado", pairs: [
                            ("El archivo está listo. El archivo tiene todas las páginas. Te lo mando luego.", "El archivo está listo y completo; te lo envío más tarde."),
                            ("Esta parte del texto no se entiende muy bien y quiero arreglarla.", "Esta sección resulta poco clara y me gustaría mejorarla."),
                          ])

        // MARK: French
        case ("fr", .grammar):
            return Prompt(intro: "Corrige uniquement la grammaire, l'orthographe et la ponctuation en français, sans rien traduire et en gardant tout en français.",
                          inLabel: "Original", outLabel: "Corrigé", pairs: [
                            ("demain je peux pas venir parce que j'ai un rendez vous, on se parle apres", "Demain, je ne peux pas venir parce que j'ai un rendez-vous ; on se parle après."),
                            ("le fichier est pret mais il manque la derniere page", "Le fichier est prêt, mais il manque la dernière page."),
                          ])
        case ("fr", .formal):
            return Prompt(intro: "Réécris le texte en français sur un ton formel et professionnel, sans changer de langue.",
                          inLabel: "Original", outLabel: "Formel", pairs: [
                            ("je t'envoie le fichier tout à l'heure ok ?", "Je vous enverrai le document sous peu."),
                            ("demain je suis pas là, on s'appelle jeudi", "Je ne serai pas disponible demain. Pourrions-nous nous appeler jeudi ?"),
                          ])
        case ("fr", .shorter):
            return Prompt(intro: "Rends le texte plus court et plus concis en français, sans changer de langue.",
                          inLabel: "Original", outLabel: "Court", pairs: [
                            ("Je voulais simplement te dire que le fichier que tu m'avais demandé hier est enfin prêt.", "Le fichier demandé est prêt."),
                            ("En raison du fait qu'il pleuvait très fort, nous avons décidé de rester à la maison.", "À cause de la pluie, nous sommes restés à la maison."),
                          ])
        case ("fr", .improve):
            return Prompt(intro: "Améliore la clarté et la fluidité du texte en français, en gardant toutes les informations et en écrivant UNIQUEMENT en français.",
                          inLabel: "Original", outLabel: "Amélioré", pairs: [
                            ("Le fichier est prêt. Le fichier a toutes les pages. Je te l'envoie après.", "Le fichier est prêt et complet ; je te l'envoie plus tard."),
                            ("Cette partie du texte n'est pas très claire à lire et je voudrais la corriger.", "Cette section manque de clarté et j'aimerais l'améliorer."),
                          ])

        // MARK: German
        case ("de", .grammar):
            return Prompt(intro: "Korrigiere nur Grammatik, Rechtschreibung und Zeichensetzung auf Deutsch, ohne etwas zu übersetzen; alles bleibt auf Deutsch.",
                          inLabel: "Original", outLabel: "Korrigiert", pairs: [
                            ("morgen kann ich nicht kommen weil ich einen termin habe wir sprechen spater", "Morgen kann ich nicht kommen, weil ich einen Termin habe. Wir sprechen später."),
                            ("die datei ist fertig aber die letzte seite fehlt", "Die Datei ist fertig, aber die letzte Seite fehlt."),
                          ])
        case ("de", .formal):
            return Prompt(intro: "Formuliere den Text auf Deutsch in einem höflichen, formellen Ton, ohne die Sprache zu wechseln.",
                          inLabel: "Original", outLabel: "Formell", pairs: [
                            ("ich schick dir die datei gleich ok?", "Ich sende Ihnen das Dokument in Kürze."),
                            ("morgen bin ich nicht da, lass uns donnerstag reden", "Morgen bin ich leider nicht erreichbar. Können wir am Donnerstag sprechen?"),
                          ])
        case ("de", .shorter):
            return Prompt(intro: "Mache den Text auf Deutsch kürzer und prägnanter, ohne die Sprache zu wechseln.",
                          inLabel: "Original", outLabel: "Kurz", pairs: [
                            ("Ich wollte dir nur sagen, dass die Datei, um die du mich gestern gebeten hast, jetzt endlich fertig ist.", "Die gewünschte Datei ist fertig."),
                            ("Aufgrund der Tatsache, dass es sehr stark regnete, haben wir beschlossen, zu Hause zu bleiben.", "Wegen des Regens blieben wir zu Hause."),
                          ])
        case ("de", .improve):
            return Prompt(intro: "Verbessere Klarheit und Lesefluss des Textes auf Deutsch, behalte alle Informationen bei und schreibe NUR auf Deutsch.",
                          inLabel: "Original", outLabel: "Verbessert", pairs: [
                            ("Die Datei ist fertig. Die Datei hat alle Seiten. Ich schicke sie dir später.", "Die Datei ist fertig und vollständig; ich schicke sie dir später."),
                            ("Dieser Teil vom Text ist nicht so gut zu lesen und ich will ihn verbessern.", "Dieser Abschnitt liest sich schwer, daher möchte ich ihn klarer formulieren."),
                          ])

        // MARK: Portuguese
        case ("pt", .grammar):
            return Prompt(intro: "Corrige apenas a gramática, a ortografia e a pontuação em português, sem traduzir nada e mantendo tudo em português.",
                          inLabel: "Original", outLabel: "Corrigido", pairs: [
                            ("amanha nao posso ir porque tenho um compromisso, falamos depois", "Amanhã não posso ir porque tenho um compromisso; falamos depois."),
                            ("o ficheiro esta pronto mas falta a ultima pagina", "O ficheiro está pronto, mas falta a última página."),
                          ])
        case ("pt", .formal):
            return Prompt(intro: "Reescreve o texto em português com um tom formal e profissional, sem mudar de língua.",
                          inLabel: "Original", outLabel: "Formal", pairs: [
                            ("mando-te o ficheiro daqui a pouco ok?", "Enviarei o documento em breve."),
                            ("amanhã não estou, falamos na quinta", "Amanhã não estarei disponível. Podemos falar na quinta-feira?"),
                          ])
        case ("pt", .shorter):
            return Prompt(intro: "Torna o texto mais curto e conciso em português, sem mudar de língua.",
                          inLabel: "Original", outLabel: "Curto", pairs: [
                            ("Só queria dizer-te que o ficheiro que me pediste ontem já está finalmente pronto.", "O ficheiro que pediste está pronto."),
                            ("Devido ao facto de estar a chover muito, decidimos ficar em casa.", "Por causa da chuva, ficámos em casa."),
                          ])
        case ("pt", .improve):
            return Prompt(intro: "Melhora a clareza e a fluidez do texto em português, mantendo toda a informação e escrevendo SÓ em português.",
                          inLabel: "Original", outLabel: "Melhorado", pairs: [
                            ("O ficheiro está pronto. O ficheiro tem todas as páginas. Envio-te depois.", "O ficheiro está pronto e completo; envio-to mais tarde."),
                            ("Esta parte do texto não se lê muito bem e queria corrigi-la.", "Esta secção não está muito clara e gostaria de a melhorar."),
                          ])

        // MARK: English (and fallback)
        case (_, .grammar):
            return Prompt(intro: "Fix only grammar, spelling and punctuation in English, keeping all sentences in English.",
                          inLabel: "Original", outLabel: "Corrected", pairs: [
                            ("i cant come tomorow because i have a appointment", "I can't come tomorrow because I have an appointment."),
                            ("the file are ready but the last page is missing", "The file is ready, but the last page is missing."),
                          ])
        case (_, .formal):
            return Prompt(intro: "Rewrite the text in a polite, formal tone in English.",
                          inLabel: "Original", outLabel: "Formal", pairs: [
                            ("Hey, I'll send you the file in a bit okay?", "I will send you the document shortly."),
                            ("Can we talk tomorrow about the budget?", "Would you be available tomorrow to discuss the budget?"),
                          ])
        case (_, .shorter):
            return Prompt(intro: "Make the text shorter and more concise in English.",
                          inLabel: "Original", outLabel: "Shorter", pairs: [
                            ("Due to the fact that it was raining heavily, we decided to stay at home.", "Because of the heavy rain, we stayed home."),
                            ("I just wanted to let you know that the file you asked me for yesterday is finally ready now.", "The file you asked for is ready."),
                          ])
        case (_, .improve):
            return Prompt(intro: "Improve the clarity and flow of the text in English, keeping all facts and writing ONLY in English.",
                          inLabel: "Original", outLabel: "Improved", pairs: [
                            ("The thing is that this part of the text is not very clear to read.", "This section is difficult to read clearly."),
                            ("The file is ready. The file has all the pages. I will send it later.", "The file is ready and complete; I'll send it later."),
                          ])
        }
    }
}
