pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Rows for `d <word>`: definitions, synonyms, examples and links, with a
 * detail page per definition. See LauncherMenu for the descriptor shape.
 */
Singleton {
    id: root

    readonly property int maxDefinitions: 6
    readonly property int maxSynonyms: 8

    function rows(prefix, raw) {
        const parsed = LauncherMenu.parseWordQuery(raw);
        const word = parsed.word;
        if (word.length === 0) {
            return [LauncherMenu.noteRow(
                Translation.tr("Dictionary"),
                Translation.tr("Type a word — word!d definitions, !s synonyms, !e examples, ! links"),
                "menu_book"
            )];
        }

        // Detail page: "word > meaningIndex.definitionIndex"
        if (word.includes(">"))
            return root._detail(prefix, word.slice(0, word.indexOf(">")).trim(), word.slice(word.indexOf(">") + 1).trim());

        if (Dictionary.loading && Dictionary.word === word.toLowerCase())
            return [LauncherMenu.noteRow(Translation.tr("Dictionary"), Translation.tr("Looking up \"%1\"…").arg(word), "hourglass")];

        if (Dictionary.error.length > 0 && Dictionary.word === word.toLowerCase()) {
            return [{
                "type": Translation.tr("Dictionary"),
                "name": Dictionary.error,
                "icon": "search_off",
                "execute": () => Dictionary.retry()
            }, LauncherMenu.backRow(`${prefix} `, Translation.tr("Back to search"))];
        }

        const entry = Dictionary.entry;
        if (!entry || entry.word.toLowerCase() !== word.toLowerCase())
            return [];

        const rows = [{
            "type": `${Translation.tr("Dictionary")}${entry.phonetic ? " · " + entry.phonetic : ""}`,
            "name": entry.word,
            "verb": Translation.tr("More"),
            "icon": "menu_book",
            "drill": `${prefix} ${word} > 0.0`,
            "execute": () => LauncherMenu.copy(entry.word),
            "actions": [{ "name": Translation.tr("Copy word"), "icon": "content_copy", "execute": () => LauncherMenu.copy(entry.word) }]
        }];

        if (parsed.mode === "synonyms") {
            const synonyms = Dictionary.synonymsOf(entry);
            const antonyms = Dictionary.antonymsOf(entry);
            for (const synonym of synonyms.slice(0, root.maxSynonyms))
                rows.push(root._wordRow(prefix, synonym, Translation.tr("Synonym"), "sync_alt"));
            for (const antonym of antonyms.slice(0, root.maxSynonyms))
                rows.push(root._wordRow(prefix, antonym, Translation.tr("Antonym"), "swap_horiz"));
            if (synonyms.length === 0 && antonyms.length === 0)
                rows.push(LauncherMenu.noteRow(Translation.tr("Dictionary"), Translation.tr("No synonyms listed"), "search_off"));
            rows.push(LauncherMenu.backRow(`${prefix} ${word}!d`, Translation.tr("Back to definitions")));
            return rows;
        }

        if (parsed.mode === "examples") {
            const examples = Dictionary.examplesOf(entry);
            for (const example of examples.slice(0, 2 * root.maxDefinitions)) {
                rows.push({
                    "type": Translation.tr("Example"),
                    "name": example,
                    "maxLines": 2,
                    "verb": Translation.tr("Copy"),
                    "icon": "format_quote",
                    "execute": () => LauncherMenu.copy(example),
                    "actions": [{ "name": Translation.tr("Copy"), "icon": "content_copy", "execute": () => LauncherMenu.copy(example) }]
                });
            }
            if (examples.length === 0)
                rows.push(LauncherMenu.noteRow(Translation.tr("Dictionary"), Translation.tr("No example sentences"), "search_off"));
            rows.push(LauncherMenu.backRow(`${prefix} ${word}!d`, Translation.tr("Back to definitions")));
            return rows;
        }

        if (parsed.mode === "links") {
            for (const link of Dictionary.linksOf(entry)) {
                rows.push({
                    "type": Translation.tr("Open"),
                    "name": link.name,
                    "icon": link.icon,
                    "verb": Translation.tr("Open"),
                    "execute": () => LauncherMenu.openUrl(link.url),
                    "actions": [{ "name": Translation.tr("Copy link"), "icon": "link", "execute": () => LauncherMenu.copy(link.url) }]
                });
            }
            rows.push(LauncherMenu.backRow(`${prefix} ${word}!d`, Translation.tr("Back to definitions")));
            return rows;
        }

        const definitions = Dictionary.flatDefinitions(entry);
        for (const definition of definitions.slice(0, root.maxDefinitions)) {
            rows.push({
                "type": `${definition.partOfSpeech} · ${definition.index + 1}`,
                "name": definition.definition,
                "maxLines": 3,
                "verb": Translation.tr("More"),
                "icon": LauncherMenu.partOfSpeechIcon(definition.partOfSpeech),
                "drill": `${prefix} ${word} > ${definition.meaningIndex}.${definition.index}`,
                "execute": () => LauncherMenu.copy(definition.definition),
                "actions": [{ "name": Translation.tr("Copy definition"), "icon": "content_copy", "execute": () => LauncherMenu.copy(definition.definition) }]
            });
        }
        return rows;
    }

    function _wordRow(prefix, word, type, icon) {
        return {
            "type": type,
            "name": word,
            "icon": icon,
            "verb": Translation.tr("Look up"),
            "drill": `${prefix} ${word}`,
            "execute": () => LauncherMenu.copy(word),
            "actions": [{ "name": Translation.tr("Copy"), "icon": "content_copy", "execute": () => LauncherMenu.copy(word) }]
        };
    }

    function _detail(prefix, word, target) {
        const entry = Dictionary.entry;
        if (!entry || entry.word.toLowerCase() !== word.toLowerCase()) {
            Dictionary.lookup(word);
            return [LauncherMenu.noteRow(Translation.tr("Dictionary"), Translation.tr("Looking up \"%1\"…").arg(word), "hourglass")];
        }

        const parsed = String(target ?? "").split(".");
        const definitions = Dictionary.flatDefinitions(entry);
        const definition = definitions.find(item => item.meaningIndex === Number(parsed[0]) && item.index === Number(parsed[1]))
            ?? definitions[0];
        if (!definition)
            return [LauncherMenu.backRow(`${prefix} ${word}`, Translation.tr("Back to definitions"))];

        const rows = [{
            "type": `${word}${entry.phonetic ? " · " + entry.phonetic : ""} · ${definition.partOfSpeech}`,
            "name": definition.definition,
            "maxLines": 4,
            "icon": LauncherMenu.partOfSpeechIcon(definition.partOfSpeech),
            "verb": Translation.tr("Copy"),
            "execute": () => LauncherMenu.copy(definition.definition),
            "actions": [{ "name": Translation.tr("Copy definition"), "icon": "content_copy", "execute": () => LauncherMenu.copy(definition.definition) }]
        }];

        rows.push({
            "type": Translation.tr("Definition"),
            "name": Translation.tr("Copy definition"),
            "icon": "content_copy",
            "verb": Translation.tr("Copy"),
            "execute": () => LauncherMenu.copy(definition.definition)
        });
        rows.push({
            "type": Translation.tr("Word"),
            "name": word,
            "icon": "text_fields",
            "verb": Translation.tr("Copy"),
            "execute": () => LauncherMenu.copy(word)
        });

        if (definition.example && definition.example.length > 0) {
            rows.push({
                "type": Translation.tr("Example"),
                "name": definition.example,
                "maxLines": 3,
                "icon": "format_quote",
                "verb": Translation.tr("Copy"),
                "execute": () => LauncherMenu.copy(definition.example),
                "actions": [{ "name": Translation.tr("Copy"), "icon": "content_copy", "execute": () => LauncherMenu.copy(definition.example) }]
            });
        }

        const synonyms = (definition.synonyms.length > 0 ? definition.synonyms : Dictionary.synonymsOf(entry)).slice(0, root.maxSynonyms);
        for (const synonym of synonyms)
            rows.push(root._wordRow(prefix, synonym, Translation.tr("Synonym"), "sync_alt"));

        for (const link of Dictionary.linksOf(entry).slice(0, 2)) {
            rows.push({
                "type": Translation.tr("Open"),
                "name": link.name,
                "icon": link.icon,
                "verb": Translation.tr("Open"),
                "execute": () => LauncherMenu.openUrl(link.url)
            });
        }

        rows.push(LauncherMenu.backRow(`${prefix} ${word}!d`, Translation.tr("Back to definitions")));
        return rows;
    }
}
