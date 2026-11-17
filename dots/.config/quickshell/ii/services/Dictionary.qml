pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Dictionary lookups for the launcher (`d <word>`).
 *
 * QML can't fetch JSON with requests of its own, so curl does the talking:
 * https://dictionaryapi.dev is free and needs no key. One word is cached for
 * the session, and results are presentation-neutral (the launcher decides
 * whether to show definitions, synonyms, examples or links).
 *
 * Suffix modifiers follow the Flow.Launcher.Dictionary conventions:
 *   word!d  definitions     word!s  synonyms/antonyms
 *   word!e  examples        word!   links to the word online
 */
Singleton {
    id: root

    property string word: ""
    property bool loading: false
    property string error: ""
    property var entry: null

    property var _cache: ({})
    property string _pendingWord: ""
    property int _serial: 0

    readonly property string apiBase: "https://api.dictionaryapi.dev/api/v2/entries/en/"

    function isWord(text) {
        return /^[a-zA-Z][a-zA-Z'’-]*$/.test(String(text ?? "").trim());
    }

    function lookup(text) {
        const needle = String(text ?? "").trim().toLowerCase();
        root._serial += 1;
        fetchProc.running = false;
        debounce.stop();

        if (needle.length === 0) {
            root.word = "";
            root.entry = null;
            root.error = "";
            root.loading = false;
            return;
        }
        if (!root.isWord(needle)) {
            root.word = needle;
            root.entry = null;
            root.error = Translation.tr("Look up a single word");
            root.loading = false;
            return;
        }
        if (root._cache[needle] !== undefined) {
            root.word = needle;
            root.entry = root._cache[needle];
            root.error = "";
            root.loading = false;
            return;
        }

        root.word = needle;
        root.entry = null;
        root.error = "";
        root.loading = true;
        root._pendingWord = needle;
        debounce.restart();
    }

    function retry() {
        if (root.error.length > 0 && root.word.length > 0)
            root.lookup(root.word);
    }

    // ----------------------------- Shaping ------------------------------
    function flatDefinitions(value) {
        const result = [];
        if (!value)
            return result;
        for (let meaningIndex = 0; meaningIndex < value.meanings.length; meaningIndex++) {
            const meaning = value.meanings[meaningIndex];
            for (let index = 0; index < meaning.definitions.length; index++) {
                result.push({
                    "partOfSpeech": meaning.partOfSpeech,
                    "index": index,
                    "meaningIndex": meaningIndex,
                    "definition": meaning.definitions[index].definition,
                    "example": meaning.definitions[index].example,
                    "synonyms": meaning.definitions[index].synonyms,
                    "antonyms": meaning.definitions[index].antonyms
                });
            }
        }
        return result;
    }

    function synonymsOf(value) {
        if (!value)
            return [];
        const seen = new Set();
        for (const meaning of value.meanings) {
            for (const synonym of meaning.synonyms)
                seen.add(synonym);
            for (const definition of meaning.definitions) {
                for (const synonym of definition.synonyms)
                    seen.add(synonym);
            }
        }
        return Array.from(seen);
    }

    function antonymsOf(value) {
        if (!value)
            return [];
        const seen = new Set();
        for (const meaning of value.meanings) {
            for (const antonym of meaning.antonyms)
                seen.add(antonym);
            for (const definition of meaning.definitions) {
                for (const antonym of definition.antonyms)
                    seen.add(antonym);
            }
        }
        return Array.from(seen);
    }

    function examplesOf(value) {
        if (!value)
            return [];
        const result = [];
        for (const definition of root.flatDefinitions(value)) {
            if (definition.example && definition.example.length > 0)
                result.push(definition.example);
        }
        return result;
    }

    function linksOf(value) {
        const links = [];
        const word = String(value?.word ?? root.word);
        for (const url of (value?.sourceUrls ?? []))
            links.push({ "name": word, "url": url, "icon": "menu_book" });
        links.push({
            "name": word,
            "url": `https://www.merriam-webster.com/dictionary/${encodeURIComponent(word)}`,
            "icon": "travel_explore"
        });
        links.push({
            "name": word,
            "url": `https://www.etymonline.com/word/${encodeURIComponent(word)}`,
            "icon": "history_edu"
        });
        return links;
    }

    // ----------------------------- Fetching -----------------------------
    Timer {
        id: debounce
        interval: 220
        onTriggered: {
            if (root._pendingWord.length === 0)
                return;
            fetchProc.serial = root._serial;
            fetchProc.command = ["curl", "-sS", "-L", "--max-time", "10", "-A",
                Config.options?.networking?.userAgent ?? "Mozilla/5.0",
                root.apiBase + encodeURIComponent(root._pendingWord)];
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
            onRead: line => console.log("[Dictionary]", line)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && fetchProc.serial === root._serial) {
                root.loading = false;
                if (root.entry === null && root.error.length === 0)
                    root.error = Translation.tr("Dictionary lookup failed");
            }
        }
    }

    function _handle(text) {
        let data = null;
        try {
            data = JSON.parse(String(text ?? ""));
        } catch (parseError) {
            root.error = Translation.tr("Dictionary lookup failed");
            return;
        }
        if (!Array.isArray(data) || data.length === 0) {
            let message = Translation.tr("No definitions for \"%1\"").arg(root.word);
            if (data && data.title && data.title !== "No Definitions Found")
                message = String(data.title);
            root.error = message;
            root.entry = null;
            return;
        }

        const first = data[0] ?? {};
        const meanings = [];
        for (const raw of data) {
            for (const meaning of (raw.meanings ?? [])) {
                const definitions = (meaning.definitions ?? [])
                    .map(definition => ({
                        "definition": String(definition.definition ?? ""),
                        "example": String(definition.example ?? ""),
                        "synonyms": definition.synonyms ?? [],
                        "antonyms": definition.antonyms ?? []
                    }))
                    .filter(definition => definition.definition.length > 0);
                if (definitions.length > 0)
                    meanings.push({
                        "partOfSpeech": String(meaning.partOfSpeech ?? ""),
                        "synonyms": meaning.synonyms ?? [],
                        "antonyms": meaning.antonyms ?? [],
                        "definitions": definitions
                    });
            }
        }

        const phonetics = (first.phonetics ?? []).filter(item => item.text || item.audio);
        const entry = {
            "word": String(first.word ?? root.word),
            "phonetic": String(first.phonetic || phonetics.find(item => item.text)?.text || ""),
            "audio": String(phonetics.find(item => item.audio)?.audio || ""),
            "origin": String(first.origin ?? ""),
            "sourceUrls": first.sourceUrls ?? [],
            "meanings": meanings
        };

        if (meanings.length === 0) {
            root.error = Translation.tr("No definitions for \"%1\"").arg(root.word);
            root.entry = null;
            return;
        }

        root._cache[root.word] = entry;
        root.entry = entry;
        root.error = "";
    }
}
