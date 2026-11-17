pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
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

    // A URL handed to an already-running browser lands as a tab in its window, but the
    // window never raises itself, so a launcher web search looked like it went nowhere.
    // Focus the browser first (focuswindow also follows it to its workspace).
    readonly property var browserClasses: /^(zen|firefox|chromium|google-chrome|google-chrome-stable|brave-browser|microsoft-edge|librewolf|vivaldi|opera)$/i
    function runningBrowser() {
        // Tiled windows first: a zen oauth/extension dialog is also class `zen`, and raising
        // a popup would leave the real window exactly where it was.
        const browsers = (HyprlandData.windowList ?? []).filter(w => root.browserClasses.test(String(w.class ?? "")));
        return browsers.find(w => !w.floating) ?? browsers[0];
    }

    function openUrl(url) {
        const target = String(url ?? "");
        if (target.length === 0) return;
        if (root.focusBrowser())
            refocusTimer.restart();
        // xdg-open rather than Qt.openUrlExternally so the delivery path is the same one
        // that can be reproduced from a terminal (mimeapps default browser).
        Quickshell.execDetached(["xdg-open", target]);
    }

    function focusBrowser() {
        const browser = root.runningBrowser();
        if (!browser) return false;
        Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ window = "address:${browser.address}" })`]);
        return true;
    }

    // Closing the launcher hands focus back to whatever was focused before it opened, undoing
    // the raise above. Re-assert once it is gone, still before the tab finishes loading.
    Timer {
        id: refocusTimer
        interval: 250
        repeat: false
        onTriggered: root.focusBrowser()
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
