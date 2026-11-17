pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

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
    // xdg-open resolves the URL through the mimeapps default browser, so focus has to read the
    // same source or the two drift: resolve the desktop entry behind x-scheme-handler/https to
    // its window class (StartupWMClass, else the entry name).
    property string browserClass: ""
    Process {
        id: defaultBrowserProc
        command: ["sh", "-c",
            'entry=$(xdg-mime query default x-scheme-handler/https 2>/dev/null '
            + '|| xdg-settings get default-web-browser 2>/dev/null); '
            + '[ -n "$entry" ] || exit 0; '
            + 'for f in "$HOME/.local/share/applications/$entry" "/usr/share/applications/$entry"; do '
            + '    [ -f "$f" ] || continue; '
            + '    cls=$(sed -n "s/^StartupWMClass=//p" "$f" | head -1); '
            + '    echo "${cls:-${entry%.desktop}}"; exit 0; '
            + 'done; '
            + 'echo "${entry%.desktop}"']
        stdout: StdioCollector {
            onStreamFinished: root.browserClass = text.trim()
        }
    }
    // This singleton is created on first use, so the probe may still be running when the first
    // search fires: settleRaise() waits for it there (see onBrowserClassChanged).
    Component.onCompleted: defaultBrowserProc.running = true
    onBrowserClassChanged: root.settleRaise()

    function runningBrowser() {
        if (root.browserClass === "") return null;
        const wins = (HyprlandData.windowList ?? []).filter(w => String(w.class ?? "") === root.browserClass);
        // Tiled first: a zen oauth/extension dialog shares the class, and raising a popup would
        // leave the real window exactly where it was.
        return wins.find(w => !w.floating) ?? wins[0] ?? null;
    }

    // The launcher hands focus back to whatever had it when it closes, undoing the raise above.
    // Hook the close rather than guessing a delay.
    property bool raisePending: false
    readonly property bool launcherVisible: GlobalStates.overviewOpen || GlobalStates.appLauncherOpen || GlobalStates.searchOpen
    function settleRaise() {
        if (!root.raisePending || root.launcherVisible) return;
        root.raisePending = false;
        root.focusBrowser();
    }
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() { root.settleRaise(); }
        function onAppLauncherOpenChanged() { root.settleRaise(); }
        function onSearchOpenChanged() { root.settleRaise(); }
    }

    function openUrl(url) {
        const target = String(url ?? "");
        if (target.length === 0) return;
        // Raise now, and again when the launcher closes if it was up — on the very first search
        // the class probe may still be pending, which raisePending also covers.
        root.raisePending = root.launcherVisible || root.browserClass === "";
        root.focusBrowser();
        Quickshell.execDetached(["xdg-open", target]);
    }

    function focusBrowser() {
        if (root.browserClass === "") {
            if (!defaultBrowserProc.running) defaultBrowserProc.running = true;
            return false;
        }
        const browser = root.runningBrowser();
        if (!browser) return false;
        Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ window = "address:${browser.address}" })`]);
        return true;
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
