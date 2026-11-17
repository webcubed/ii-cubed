pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Translation for the launcher (`t <text>`).
 *
 * MyMemory does the translation (free, no key, same API the AI translations
 * use). Pinyin comes from zhconvert's Pinyin converter, which answers in
 * numbered tones ("ni3 hao3"); they are turned into tone marks here because
 * that is what you actually want to read.
 *
 * Languages:
 *   t <text>              English → 中文, anything else → English
 *   t <from>><to> <text>  explicit pair, e.g. "t en>fr hello", "t >ja hello"
 *   t <text> >            detail page
 * The source may be omitted ("Autodetect"); a trailing ">" opens the detail page.
 */
Singleton {
    id: root

    property string text: ""
    property string sourceLang: "auto"
    property string targetLang: "zh-CN"
    property string detectedSource: ""
    property string translation: ""
    property string pinyin: ""
    property string pinyinOf: "" // "source" | "translation"
    property bool loading: false
    property bool pinyinLoading: false
    property string error: ""
    property string lastQuery: "" // raw query the properties above belong to

    property var _cache: ({})
    property string _pendingText: ""
    property string _pendingSource: "auto"
    property string _pendingTarget: "zh-CN"
    property int _serial: 0

    readonly property int maxChars: 480
    readonly property string translateApi: "https://api.mymemory.translated.net/get"
    readonly property string pinyinApi: "https://api.zhconvert.org/convert?converter=Pinyin&text="

    readonly property var languageNames: ({
        "auto": "Auto",
        "en": "English",
        "zh-CN": "中文",
        "zh-TW": "繁體中文",
        "ja": "日本語",
        "ko": "한국어",
        "es": "Spanish",
        "fr": "French",
        "de": "German",
        "it": "Italian",
        "pt": "Portuguese",
        "ru": "Russian",
        "ar": "Arabic",
        "hi": "Hindi",
        "nl": "Dutch",
        "pl": "Polish",
        "tr": "Turkish",
        "sv": "Swedish",
        "uk": "Ukrainian",
        "vi": "Vietnamese",
        "th": "Thai",
        "id": "Indonesian",
        "cs": "Czech",
        "da": "Danish",
        "fi": "Finnish",
        "el": "Greek",
        "he": "Hebrew",
        "hu": "Hungarian",
        "no": "Norwegian",
        "ro": "Romanian",
        "sk": "Slovak",
        "fa": "Persian"
    })

    function languageName(code) {
        return root.languageNames[String(code ?? "")] ?? String(code ?? "");
    }

    function normaliseLanguage(code) {
        const value = String(code ?? "").trim().toLowerCase();
        if (value.length === 0 || value === "auto" || value === "detect")
            return "auto";
        const aliases = {
            "zh": "zh-CN", "cn": "zh-CN", "chinese": "zh-CN", "zh-hans": "zh-CN", "zh-sg": "zh-CN",
            "zh-tw": "zh-TW", "zh-hant": "zh-TW", "traditional": "zh-TW",
            "jp": "ja", "japanese": "ja", "kr": "ko", "korean": "ko",
            "english": "en", "spanish": "es", "french": "fr", "german": "de",
            "italian": "it", "portuguese": "pt", "russian": "ru", "arabic": "ar",
            "hindi": "hi", "dutch": "nl", "polish": "pl", "turkish": "tr",
            "swedish": "sv", "ukrainian": "uk", "vietnamese": "vi", "thai": "th",
            "indonesian": "id"
        };
        return aliases[value] ?? value;
    }

    function isKnownLanguage(code) {
        return root.languageNames[String(code ?? "")] !== undefined;
    }

    /// Splits "en>fr hello >" into languages, text and whether the page is the
    /// detail view. A lone ">" with no language codes is the detail marker.
    function parse(raw) {
        let text = String(raw ?? "").trim();
        let detail = false;
        if (text.endsWith(">")) {
            detail = true;
            text = text.slice(0, -1).trim();
        }
        const spec = /^([A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?)?\s*>\s*([A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?)(?:\s+|$)([\s\S]*)$/.exec(text);
        if (spec) {
            const target = root.normaliseLanguage(spec[2]);
            if (root.isKnownLanguage(target)) {
                return {
                    "detail": detail,
                    "source": root.normaliseLanguage(spec[1] ?? "auto"),
                    "target": target,
                    "text": String(spec[3] ?? "").trim()
                };
            }
        }
        return { "detail": detail, "source": "auto", "target": "", "text": text };
    }

    function hasHan(value) {
        return /[\u3400-\u4dbf\u4e00-\u9fff]/.test(String(value ?? ""));
    }

    function looksEnglish(value) {
        const text = String(value ?? "");
        if (root.hasHan(text))
            return false;
        if (/[\u3040-\u30ff\uac00-\ud7af]/.test(text)) // kana, hangul
            return false;
        if (/[À-ÿĀ-ž]/i.test(text)) // accented Latin: probably not English
            return false;
        return true;
    }

    /// Default direction: English goes to Chinese, everything else to English.
    function guessTarget(value) {
        return root.looksEnglish(value) ? "zh-CN" : "en";
    }

    function isChineseTarget() {
        return root.targetLang.indexOf("zh") === 0;
    }

    function directionLabel() {
        const from = root.sourceLang === "auto" ? Translation.tr("Auto") : root.languageName(root.sourceLang);
        return `${from} → ${root.languageName(root.targetLang)}`;
    }

    // ----------------------------- Tone marks ----------------------------
    function toneMark(syllable, tone) {
        const vowelMarks = {
            "a": ["ā", "á", "ǎ", "à"],
            "e": ["ē", "é", "ě", "è"],
            "i": ["ī", "í", "ǐ", "ì"],
            "o": ["ō", "ó", "ǒ", "ò"],
            "u": ["ū", "ú", "ǔ", "ù"],
            "ü": ["ǖ", "ǘ", "ǚ", "ǜ"]
        };
        const source = String(syllable ?? "");
        const lower = source.toLowerCase();
        let index = -1;
        if (lower.includes("a")) index = lower.indexOf("a");
        else if (lower.includes("o")) index = lower.indexOf("o");
        else if (lower.includes("e")) index = lower.indexOf("e");
        else if (lower.includes("iu")) index = lower.indexOf("iu") + 1;
        else if (lower.includes("i")) index = lower.indexOf("i");
        else if (lower.includes("u")) index = lower.indexOf("u");
        else if (lower.includes("ü")) index = lower.indexOf("ü");
        if (index < 0)
            return source;
        const marked = vowelMarks[lower[index]]?.[Math.max(0, Math.min(3, tone - 1))];
        if (!marked)
            return source;
        const result = source.slice(0, index) + marked + source.slice(index + 1);
        return source[0] === source[0].toUpperCase() && source[0] !== source[0].toLowerCase()
            ? result[0].toUpperCase() + result.slice(1)
            : result;
    }

    function numberedToToneMarks(value) {
        const converted = String(value ?? "").replace(/([A-Za-züÜvV]+)([1-5])/g, (match, syllable, tone) => {
            const fixed = syllable.replace(/[vV]/g, character => character === "V" ? "Ü" : "ü");
            return Number(tone) === 5 ? fixed : root.toneMark(fixed, Number(tone));
        });
        // zhconvert keeps a space in front of Chinese punctuation
        return converted.replace(/\s+([，。！？；：、）】》])/g, "$1").replace(/([（【《])\s+/g, "$1").trim();
    }

    function decodeEntities(value) {
        return String(value ?? "")
            .replace(/&#(\d+);/g, (match, code) => String.fromCharCode(Number(code)))
            .replace(/&quot;/g, "\"")
            .replace(/&#39;/g, "'")
            .replace(/&apos;/g, "'")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&amp;/g, "&");
    }

    // ------------------------------ Lookup -------------------------------
    function translate(raw) {
        const parsed = root.parse(raw);
        const text = parsed.text;
        root._serial += 1;
        translateProc.running = false;
        pinyinProc.running = false;
        debounce.stop();

        root.text = text;
        root.lastQuery = String(raw ?? "").trim();
        if (text.length === 0) {
            root.translation = "";
            root.pinyin = "";
            root.pinyinOf = "";
            root.error = "";
            root.loading = false;
            root.pinyinLoading = false;
            return;
        }
        if (text.length > root.maxChars) {
            root.translation = "";
            root.pinyin = "";
            root.pinyinOf = "";
            root.error = Translation.tr("Too long — %1 characters max").arg(root.maxChars);
            root.loading = false;
            root.pinyinLoading = false;
            return;
        }

        const target = parsed.target.length > 0 ? parsed.target : root.guessTarget(text);
        const source = parsed.source;
        root.sourceLang = source;
        root.targetLang = target;
        root.pinyinOf = target.indexOf("zh") === 0 ? "translation" : (root.hasHan(text) ? "source" : "");

        const cached = root._cache[`${source}|${target}|${text}`];
        if (cached !== undefined) {
            root.translation = cached.translation;
            root.pinyin = cached.pinyin;
            root.detectedSource = cached.detectedSource ?? "";
            root.error = "";
            root.loading = false;
            root.pinyinLoading = false;
            return;
        }

        root.translation = "";
        root.pinyin = "";
        root.detectedSource = "";
        root.error = "";
        root.loading = true;
        root.pinyinLoading = false;
        root._pendingText = text;
        root._pendingSource = source;
        root._pendingTarget = target;
        debounce.restart();
    }

    function retry() {
        if (root.lastQuery.length > 0)
            root.translate(root.lastQuery);
    }

    Timer {
        id: debounce
        interval: 260
        onTriggered: {
            if (root._pendingText.length === 0)
                return;
            const pair = `${root._pendingSource === "auto" ? "Autodetect" : root._pendingSource}|${root._pendingTarget}`;
            translateProc.serial = root._serial;
            translateProc.command = [
                "curl", "-sS", "-L", "--max-time", "12", "-A",
                Config.options?.networking?.userAgent ?? "Mozilla/5.0",
                `${root.translateApi}?q=${encodeURIComponent(root._pendingText)}&langpair=${encodeURIComponent(pair)}`
            ];
            translateProc.running = true;
        }
    }

    Process {
        id: translateProc
        property int serial: 0
        stdout: StdioCollector {
            onStreamFinished: {
                if (translateProc.serial !== root._serial)
                    return;
                root.loading = false;
                root._handleTranslation(this.text);
            }
        }
        stderr: SplitParser {
            onRead: line => console.log("[TranslationService]", line)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && translateProc.serial === root._serial) {
                root.loading = false;
                if (root.translation.length === 0 && root.error.length === 0)
                    root.error = Translation.tr("Translation failed");
            }
        }
    }

    function _handleTranslation(raw) {
        let data = null;
        try {
            data = JSON.parse(String(raw ?? ""));
        } catch (parseError) {
            root.error = Translation.tr("Translation failed");
            return;
        }

        const status = Number(data?.responseStatus ?? 0);
        if (status !== 200) {
            const details = String(data?.responseDetails ?? "");
            if (details.toUpperCase().includes("DISTINCT LANGUAGES")) {
                // Detected source already matches the target: nothing to do.
                root.translation = root._pendingText;
                root.error = "";
                root._queuePinyin();
                return;
            }
            root.error = details.length > 0 ? details : Translation.tr("Translation failed");
            return;
        }

        const detected = String(data?.matches?.[0]?.source ?? "");
        root.detectedSource = detected.length > 0 ? root.normaliseLanguage(detected) : "";
        const translated = root.decodeEntities(String(data?.responseData?.translatedText ?? ""));
        if (translated.length === 0) {
            root.error = Translation.tr("Translation failed");
            return;
        }
        root.translation = translated;
        root.error = "";
        root._queuePinyin();
    }

    function _queuePinyin() {
        if (root.pinyinOf.length === 0)
            return;
        const chinese = root.pinyinOf === "translation" ? root.translation : root._pendingText;
        if (!root.hasHan(chinese))
            return;
        root.pinyinLoading = true;
        pinyinProc.serial = root._serial;
        pinyinProc.command = [
            "curl", "-sS", "-L", "--max-time", "12", "-A",
            Config.options?.networking?.userAgent ?? "Mozilla/5.0",
            root.pinyinApi + encodeURIComponent(chinese)
        ];
        pinyinProc.running = true;
    }

    Process {
        id: pinyinProc
        property int serial: 0
        stdout: StdioCollector {
            onStreamFinished: {
                if (pinyinProc.serial !== root._serial)
                    return;
                root.pinyinLoading = false;
                let data = null;
                try {
                    data = JSON.parse(this.text);
                } catch (parseError) {
                    return;
                }
                const converted = String(data?.data?.text ?? "");
                if (converted.length === 0)
                    return;
                root.pinyin = root.numberedToToneMarks(converted);
                root._cache[`${root._pendingSource}|${root._pendingTarget}|${root._pendingText}`] = {
                    "translation": root.translation,
                    "pinyin": root.pinyin,
                    "detectedSource": root.detectedSource
                };
            }
        }
        stderr: SplitParser {
            onRead: line => console.log("[TranslationService] pinyin:", line)
        }
        onExited: (exitCode, exitStatus) => {
            if (pinyinProc.serial === root._serial)
                root.pinyinLoading = false;
        }
    }
}
