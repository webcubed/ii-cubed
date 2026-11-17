pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Rows for the translation surface (`t <text>`), including the language picker
 * syntax handled by TranslationService.parse().
 *
 * Upcoming authenticator codes are not built here on purpose: their rows only
 * carry an index, and SearchItem reads the live code/countdown from
 * Authenticator so the results list is not rebuilt every second.
 */
Singleton {
    id: root

    readonly property var exampleLanguages: ["en", "zh-CN", "ja", "ko", "es", "fr", "de", "ru"]

    function rows(prefix, raw) {
        const parsed = TranslationService.parse(raw);

        if (parsed.text.length === 0) {
            return [{
                "type": Translation.tr("Translate"),
                "name": Translation.tr("Type text — en>fr for other languages"),
                "icon": "translate",
                "execute": () => {}
            }, {
                "type": root.exampleLanguages.slice(0, 6).map(code => `${code} ${TranslationService.languageName(code)}`).join("  ·  "),
                "name": Translation.tr("`t en>fr text` or `t >ja text`; plain text goes English ⇄ 中文"),
                "icon": "language",
                "execute": () => {}
            }];
        }

        if (parsed.detail)
            return root._detail(prefix, parsed);

        if (TranslationService.lastQuery !== String(raw ?? "").trim())
            return [];

        if (TranslationService.loading) {
            return [LauncherMenu.noteRow(
                `${Translation.tr("Translate")} · ${TranslationService.directionLabel()}`,
                Translation.tr("Translating…"),
                "hourglass"
            )];
        }
        if (TranslationService.error.length > 0) {
            return [{
                "type": Translation.tr("Translate"),
                "name": TranslationService.error,
                "icon": "error",
                "execute": () => TranslationService.retry()
            }, LauncherMenu.backRow(`${prefix} `, Translation.tr("Back to search"))];
        }
        if (TranslationService.translation.length === 0)
            return [];

        const rows = [{
            "type": `${Translation.tr("Translate")} · ${TranslationService.directionLabel()}`,
            "name": TranslationService.translation,
            "maxLines": 4,
            "icon": "translate",
            "verb": Translation.tr("More"),
            "drill": root._drill(prefix, parsed, parsed.text, true),
            "execute": () => LauncherMenu.copy(TranslationService.translation),
            "actions": [{ "name": Translation.tr("Copy translation"), "icon": "content_copy", "execute": () => LauncherMenu.copy(TranslationService.translation) }]
        }];

        if (TranslationService.pinyin.length > 0) {
            rows.push({
                "type": `${Translation.tr("Pinyin")} · ${TranslationService.pinyinOf === "source" ? Translation.tr("source") : Translation.tr("translation")}`,
                "name": TranslationService.pinyin,
                "fontType": "monospace",
                "icon": "record_voice_over",
                "verb": Translation.tr("Copy"),
                "execute": () => LauncherMenu.copy(TranslationService.pinyin),
                "actions": [{ "name": Translation.tr("Copy pinyin"), "icon": "content_copy", "execute": () => LauncherMenu.copy(TranslationService.pinyin) }]
            });
        } else if (TranslationService.pinyinLoading) {
            rows.push(LauncherMenu.noteRow(Translation.tr("Pinyin"), Translation.tr("Working out the tones…"), "hourglass"));
        }
        return rows;
    }

    /// The query that re-opens this lookup, optionally with the detail marker.
    function _drill(prefix, parsed, text, detail) {
        const spec = parsed.target.length > 0
            ? `${parsed.source === "auto" ? "" : parsed.source}>${parsed.target} `
            : "";
        return `${prefix} ${spec}${text}${detail ? " >" : ""}`;
    }

    function _detail(prefix, parsed) {
        if (TranslationService.text !== parsed.text)
            return [LauncherMenu.noteRow(Translation.tr("Translate"), Translation.tr("Translating…"), "hourglass"),
                LauncherMenu.backRow(`${prefix} `, Translation.tr("Back to search"))];

        if (TranslationService.translation.length === 0)
            return [LauncherMenu.noteRow(
                Translation.tr("Translate"),
                TranslationService.loading ? Translation.tr("Translating…") : Translation.tr("Nothing to show for \"%1\"").arg(parsed.text),
                "hourglass"
            ), LauncherMenu.backRow(`${prefix} `, Translation.tr("Back to search"))];

        const rows = [{
            "type": `${Translation.tr("Translate")} · ${TranslationService.directionLabel()}`,
            "name": TranslationService.translation,
            "maxLines": 4,
            "icon": "translate",
            "verb": Translation.tr("Copy"),
            "execute": () => LauncherMenu.copy(TranslationService.translation),
            "actions": [{ "name": Translation.tr("Copy translation"), "icon": "content_copy", "execute": () => LauncherMenu.copy(TranslationService.translation) }]
        }, {
            "type": Translation.tr("Translation"),
            "name": Translation.tr("Copy the translation"),
            "icon": "content_copy",
            "verb": Translation.tr("Copy"),
            "execute": () => LauncherMenu.copy(TranslationService.translation)
        }];

        if (TranslationService.pinyin.length > 0) {
            rows.push({
                "type": `${Translation.tr("Pinyin")} · ${TranslationService.pinyinOf === "source" ? Translation.tr("source") : Translation.tr("translation")}`,
                "name": TranslationService.pinyin,
                "fontType": "monospace",
                "icon": "record_voice_over",
                "verb": Translation.tr("Copy"),
                "execute": () => LauncherMenu.copy(TranslationService.pinyin),
                "actions": [{ "name": Translation.tr("Copy pinyin"), "icon": "content_copy", "execute": () => LauncherMenu.copy(TranslationService.pinyin) }]
            });
        }

        rows.push({
            "type": Translation.tr("Original"),
            "name": parsed.text,
            "maxLines": 3,
            "icon": "notes",
            "verb": Translation.tr("Copy"),
            "execute": () => LauncherMenu.copy(parsed.text)
        });

        const reverseTarget = parsed.source !== "auto"
            ? parsed.source
            : (TranslationService.detectedSource || (TranslationService.hasHan(parsed.text) ? "zh-CN" : "en"));
        rows.push({
            "type": Translation.tr("Translate"),
            "name": Translation.tr("Translate \"%1\" the other way").arg(TranslationService.translation),
            "maxLines": 2,
            "icon": "swap_horiz",
            "verb": Translation.tr("Open"),
            "drill": `${prefix} ${TranslationService.targetLang}>${reverseTarget} ${TranslationService.translation}`
        });

        rows.push({
            "type": Translation.tr("Open"),
            "name": Translation.tr("Open in Google Translate"),
            "icon": "travel_explore",
            "verb": Translation.tr("Open"),
            "execute": () => LauncherMenu.openUrl(`https://translate.google.com/?sl=${TranslationService.sourceLang === "auto" ? "auto" : TranslationService.sourceLang}&tl=${TranslationService.targetLang}&text=${encodeURIComponent(parsed.text)}&op=translate`)
        });

        rows.push(LauncherMenu.backRow(root._drill(prefix, parsed, TranslationService.text, false), Translation.tr("Back")));
        return rows;
    }
}
