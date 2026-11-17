pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Urban Dictionary lookups for the launcher (`u <term>`).
 *
 * Uses Urban Dictionary's public JSON endpoint through curl; there is no key.
 * Entries are normalised so the launcher can render definitions, examples or
 * links without knowing the endpoint's shape.
 */
Singleton {
    id: root

    property string term: ""
    property bool loading: false
    property string error: ""
    property var entries: []

    property var _cache: ({})
    property string _pendingTerm: ""
    property int _serial: 0

    readonly property string apiBase: "https://api.urbandictionary.com/v0/define?term="

    function lookup(text) {
        const needle = String(text ?? "").trim();
        root._serial += 1;
        fetchProc.running = false;
        debounce.stop();

        if (needle.length === 0) {
            root.term = "";
            root.entries = [];
            root.error = "";
            root.loading = false;
            return;
        }
        const key = needle.toLowerCase();
        if (root._cache[key] !== undefined) {
            root.term = needle;
            root.entries = root._cache[key];
            root.error = root.entries.length === 0 ? Translation.tr("No slang for \"%1\"").arg(needle) : "";
            root.loading = false;
            return;
        }

        root.term = needle;
        root.entries = [];
        root.error = "";
        root.loading = true;
        root._pendingTerm = needle;
        debounce.restart();
    }

    function clean(text) {
        return String(text ?? "")
            .replace(/\[|\]/g, "")
            .replace(/\r/g, "")
            .trim();
    }

    function summary(text) {
        const cleaned = root.clean(text);
        const firstLine = cleaned.split("\n").find(line => line.trim().length > 0) ?? "";
        return firstLine.length > 220 ? firstLine.slice(0, 217).replace(/\s+$/, "") + "…" : firstLine;
    }

    function retry() {
        if (root.error.length > 0 && root.term.length > 0)
            root.lookup(root.term);
    }

    Timer {
        id: debounce
        interval: 220
        onTriggered: {
            if (root._pendingTerm.length === 0)
                return;
            fetchProc.serial = root._serial;
            fetchProc.command = ["curl", "-sS", "-L", "--max-time", "10", "-A",
                Config.options?.networking?.userAgent ?? "Mozilla/5.0",
                root.apiBase + encodeURIComponent(root._pendingTerm)];
            fetchProc.running = true;
        }
    }

    Process {
        id: fetchProc
        property int serial: 0
        stdout: StdioCollector {
            onStreamFinished: {
                if (fetchProc.serial !== root._serial)
                    return;
                root.loading = false;
                root._handle(this.text);
            }
        }
        stderr: SplitParser {
            onRead: line => console.log("[UrbanDictionary]", line)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && fetchProc.serial === root._serial) {
                root.loading = false;
                if (root.error.length === 0)
                    root.error = Translation.tr("Urban Dictionary lookup failed");
            }
        }
    }

    function _handle(text) {
        let data = null;
        try {
            data = JSON.parse(String(text ?? ""));
        } catch (parseError) {
            root.error = Translation.tr("Urban Dictionary lookup failed");
            return;
        }

        const list = (data && data.list) ? data.list : [];
        const entries = list.map(item => ({
            "word": root.clean(item.word),
            "definition": root.clean(item.definition),
            "example": root.clean(item.example),
            "author": String(item.author ?? ""),
            "thumbsUp": Number(item.thumbs_up ?? 0),
            "thumbsDown": Number(item.thumbs_down ?? 0),
            "permalink": String(item.permalink ?? ""),
            "writtenOn": String(item.written_on ?? "")
        })).filter(entry => entry.definition.length > 0);

        root._cache[root.term.toLowerCase()] = entries;
        root.entries = entries;
        root.error = entries.length === 0 ? Translation.tr("No slang for \"%1\"").arg(root.term) : "";
    }
}
