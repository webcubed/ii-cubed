pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Rows for `ud <term>`: Urban Dictionary definitions, examples and links, with
 * an entry page per definition. See LauncherMenu for the descriptor shape.
 */
Singleton {
    id: root

    readonly property int maxDefinitions: 6

    function rows(prefix, raw) {
        const parsed = LauncherMenu.parseWordQuery(raw);
        const term = parsed.word;
        if (term.length === 0) {
            return [LauncherMenu.noteRow(
                Translation.tr("Urban Dictionary"),
                Translation.tr("Type a term — !d definitions, !e examples, ! links"),
                "local_fire_department"
            )];
        }

        if (term.includes(">"))
            return root._detail(prefix, term.slice(0, term.indexOf(">")).trim(), Number(term.slice(term.indexOf(">") + 1).trim()));

        if (UrbanDictionary.loading && UrbanDictionary.term.toLowerCase() === term.toLowerCase())
            return [LauncherMenu.noteRow(Translation.tr("Urban Dictionary"), Translation.tr("Looking up \"%1\"…").arg(term), "hourglass")];

        if (UrbanDictionary.error.length > 0 && UrbanDictionary.term.toLowerCase() === term.toLowerCase()) {
            return [{
                "type": Translation.tr("Urban Dictionary"),
                "name": UrbanDictionary.error,
                "icon": "search_off",
                "execute": () => UrbanDictionary.retry()
            }, LauncherMenu.backRow(`${prefix} `, Translation.tr("Back to search"))];
        }

        const entries = UrbanDictionary.entries;
        if (entries.length === 0)
            return [];

        const totalUp = entries.reduce((sum, entry) => sum + entry.thumbsUp, 0);
        const rows = [{
            "type": `${Translation.tr("Urban Dictionary")} · ${totalUp} up`,
            "name": entries[0].word || term,
            "icon": "local_fire_department",
            "verb": Translation.tr("More"),
            "drill": `${prefix} ${term} > 0`,
            "execute": () => LauncherMenu.copy(entries[0].word || term),
            "actions": [{ "name": Translation.tr("Copy"), "icon": "content_copy", "execute": () => LauncherMenu.copy(entries[0].word || term) }]
        }];

        if (parsed.mode === "examples") {
            for (const entry of entries.slice(0, root.maxDefinitions)) {
                if (entry.example.length === 0)
                    continue;
                rows.push({
                    "type": Translation.tr("Example"),
                    "name": entry.example,
                    "maxLines": 3,
                    "icon": "format_quote",
                    "verb": Translation.tr("Copy"),
                    "execute": () => LauncherMenu.copy(entry.example),
                    "actions": [{ "name": Translation.tr("Copy"), "icon": "content_copy", "execute": () => LauncherMenu.copy(entry.example) }]
                });
            }
            rows.push(LauncherMenu.backRow(`${prefix} ${term}!d`, Translation.tr("Back to definitions")));
            return rows;
        }

        if (parsed.mode === "links") {
            for (const entry of entries.slice(0, 3)) {
                rows.push({
                    "type": Translation.tr("Open"),
                    "name": entry.word || term,
                    "icon": "travel_explore",
                    "verb": Translation.tr("Open"),
                    "execute": () => LauncherMenu.openUrl(entry.permalink)
                });
            }
            rows.push({
                "type": Translation.tr("Open"),
                "name": Translation.tr("Search Google for \"%1\"").arg(term),
                "icon": "search",
                "verb": Translation.tr("Open"),
                "execute": () => LauncherMenu.openUrl(`https://www.google.com/search?q=${encodeURIComponent(term)}`)
            });
            rows.push(LauncherMenu.backRow(`${prefix} ${term}!d`, Translation.tr("Back to definitions")));
            return rows;
        }

        for (let index = 0; index < Math.min(entries.length, root.maxDefinitions); index++) {
            const entry = entries[index];
            rows.push({
                "type": `${Translation.tr("Urban")} · ${entry.thumbsUp} up · ${entry.thumbsDown} down`,
                "name": UrbanDictionary.summary(entry.definition),
                "maxLines": 3,
                "verb": Translation.tr("More"),
                "icon": "format_quote",
                "drill": `${prefix} ${term} > ${index}`,
                "execute": () => LauncherMenu.copy(entry.definition),
                "actions": [{ "name": Translation.tr("Copy definition"), "icon": "content_copy", "execute": () => LauncherMenu.copy(entry.definition) }]
            });
        }
        return rows;
    }

    function _detail(prefix, term, index) {
        const entries = UrbanDictionary.entries;
        if (entries.length === 0) {
            UrbanDictionary.lookup(term);
            return [LauncherMenu.noteRow(Translation.tr("Urban Dictionary"), Translation.tr("Looking up \"%1\"…").arg(term), "hourglass")];
        }
        const entry = entries[index] ?? entries[0];
        const rows = [{
            "type": `${entry.word || term} · ${entry.thumbsUp} up · ${entry.thumbsDown} down`,
            "name": entry.definition,
            "maxLines": 5,
            "icon": "format_quote",
            "verb": Translation.tr("Copy"),
            "execute": () => LauncherMenu.copy(entry.definition),
            "actions": [{ "name": Translation.tr("Copy definition"), "icon": "content_copy", "execute": () => LauncherMenu.copy(entry.definition) }]
        }];

        rows.push({
            "type": Translation.tr("Definition"),
            "name": Translation.tr("Copy definition"),
            "icon": "content_copy",
            "verb": Translation.tr("Copy"),
            "execute": () => LauncherMenu.copy(entry.definition)
        });

        if (entry.example.length > 0) {
            rows.push({
                "type": Translation.tr("Example"),
                "name": entry.example,
                "maxLines": 3,
                "icon": "format_quote",
                "verb": Translation.tr("Copy"),
                "execute": () => LauncherMenu.copy(entry.example),
                "actions": [{ "name": Translation.tr("Copy"), "icon": "content_copy", "execute": () => LauncherMenu.copy(entry.example) }]
            });
        }

        if (entry.permalink.length > 0) {
            rows.push({
                "type": Translation.tr("Open"),
                "name": Translation.tr("Open in Urban Dictionary"),
                "icon": "travel_explore",
                "verb": Translation.tr("Open"),
                "execute": () => LauncherMenu.openUrl(entry.permalink)
            });
        }
        if (entry.author.length > 0) {
            rows.push({
                "type": Translation.tr("Written by"),
                "name": entry.author,
                "icon": "person",
                "verb": Translation.tr("Copy"),
                "execute": () => LauncherMenu.copy(entry.author)
            });
        }

        rows.push(LauncherMenu.backRow(`${prefix} ${term}!d`, Translation.tr("Back to definitions")));
        return rows;
    }
}
