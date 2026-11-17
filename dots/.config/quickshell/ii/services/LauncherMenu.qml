pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Shared helpers for the launcher menu modules (AuthMenu, DictionaryMenu,
 * UrbanMenu, TranslationMenu, CommandPalette).
 *
 * Rows are plain descriptors so these modules stay free of launcher widgets:
 *   { type, name, verb, icon, iconType, fontType, maxLines,
 *     liveAuthenticatorId, liveUpcomingIndex, drill, execute, actions }
 *
 * `drill` is the full query a row navigates to when activated (Flow Launcher
 * style), which is how submenus and back links work.
 */
Singleton {
    id: root

    function copy(text) {
        Quickshell.clipboardText = String(text ?? "");
    }

    function openUrl(url) {
        if (String(url ?? "").length > 0)
            Qt.openUrlExternally(url);
    }

    function backRow(drill, label) {
        return {
            "type": Translation.tr("Back"),
            "name": label,
            "icon": "arrow_back",
            "verb": Translation.tr("Back"),
            "drill": drill
        };
    }

    function noteRow(type, name, icon) {
        return {
            "type": type,
            "name": name,
            "icon": icon,
            "execute": () => {}
        };
    }

    function partOfSpeechIcon(partOfSpeech) {
        switch (String(partOfSpeech ?? "").toLowerCase()) {
        case "noun": return "category";
        case "verb": return "bolt";
        case "adjective": return "palette";
        case "adverb": return "speed";
        case "pronoun": return "person";
        case "preposition": return "link";
        case "conjunction": return "join_inner";
        case "interjection": return "campaign";
        default: return "label";
        }
    }

    /// Splits "word!s" into the word and the mode it asks for.
    function parseWordQuery(raw) {
        let text = String(raw ?? "").trim();
        let mode = "definitions";
        const match = /!([dste]?)$/.exec(text);
        if (match) {
            text = text.slice(0, match.index).trim();
            mode = ({ "d": "definitions", "s": "synonyms", "e": "examples", "t": "definitions", "": "links" })[match[1]] ?? "definitions";
        }
        return { "word": text, "mode": mode };
    }
}
