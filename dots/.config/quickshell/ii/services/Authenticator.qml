pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * TOTP authenticator codes for the launcher search bar.
 *
 * Codes are computed by scripts/authenticator/otp.py (QML has no crypto) which
 * streams one JSON line per second while the launcher is open. The service list
 * lives in ~/.config/illogical-impulse/authenticators.json, so it can be edited
 * by hand; external edits are picked up through FileView.watchChanges.
 *
 * Search-bar commands (action prefix + "auth"):
 *   /auth add <Issuer:account> <secret>
 *   /auth remove <label>
 *   /auth rename <label> <new label>
 *   /auth secret <label> <new secret>
 *   /auth set <label> name=.. issuer=.. secret=.. digits=.. period=.. algorithm=..
 *   /auth import [path]        (no path = import from the clipboard)
 *   /auth export [json|uri] [path]
 *   /auth list
 */
Singleton {
    id: root

    readonly property var _options: Config.ready ? (Config.options?.search?.authenticator ?? null) : null
    readonly property bool authEnabled: root._options?.enable ?? true
    readonly property int defaultDigits: root._options?.digits ?? 6
    readonly property int defaultPeriod: root._options?.period ?? 30
    readonly property string defaultAlgorithm: root._options?.algorithm ?? "SHA1"
    readonly property int clearClipboardAfter: root._options?.clearClipboardAfter ?? 0

    readonly property string storePath: Directories.authenticatorsPath
    readonly property string scriptPath: Directories.authenticatorScriptPath

    property var services: []
    property var codes: ({})
    property string lastError: ""
    property string pendingCopyId: ""
    property int _streamFailures: 0

    // Only tick while the launcher is on screen: one python process, one wake
    // per second, and codes are ready by the time a query is typed.
    readonly property bool streamWanted: root.authEnabled && root.services.length > 0
        && (GlobalStates.overviewOpen || GlobalStates.searchOpen)

    onStreamWantedChanged: root._syncStream()
    onAuthEnabledChanged: root._syncStream()

    function _syncStream() {
        if (root.streamWanted) {
            if (!streamProc.running) {
                root._streamFailures = 0;
                streamProc.running = true;
            }
        } else {
            if (streamProc.running)
                streamProc.running = false;
            if (Object.keys(root.codes).length > 0)
                root.codes = ({});
        }
    }

    function refresh() {
        storeView.reload();
        root.reloadServices();
    }

    function reloadServices() {
        if (!listProc.running)
            listProc.running = true;
    }

    // ------------------------------ Lookups ------------------------------
    function serviceById(id) {
        return root.services.find(service => service.id === id) ?? null;
    }

    function labelOf(service) {
        if (!service)
            return "";
        if (service.issuer && service.name)
            return `${service.issuer}:${service.name}`;
        return service.name || service.issuer || "";
    }

    function codeFor(id) {
        const entry = root.codes[id];
        return entry ? String(entry.code ?? "") : "";
    }

    function remainingFor(id) {
        const entry = root.codes[id];
        return entry ? Number(entry.remaining ?? 0) : 0;
    }

    function groupCode(code) {
        const text = String(code ?? "");
        if (text.length < 6)
            return text;
        const half = Math.ceil(text.length / 2);
        return `${text.slice(0, half)} ${text.slice(half)}`;
    }

    function displayCode(id) {
        const code = root.codeFor(id);
        return code ? root.groupCode(code) : "· · ·  · · ·";
    }

    /// Codes for the next few periods, with how long until each becomes current.
    function upcomingFor(id) {
        const entry = root.codes[id];
        const service = root.serviceById(id);
        if (!entry || !service)
            return [];
        const upcoming = entry.upcoming ?? [];
        return upcoming.map((code, index) => ({
            "code": String(code),
            "startsIn": Number(entry.remaining ?? 0) + (index + 1) * Number(service.period ?? 30)
        }));
    }

    function otpauthUri(service) {
        if (!service)
            return "";
        const issuer = String(service.issuer ?? "");
        const name = String(service.name ?? "");
        const label = issuer.length > 0 && name.length > 0 ? `${issuer}:${name}` : (name || issuer);
        const params = [
            `secret=${encodeURIComponent(String(service.secret ?? ""))}`,
            `digits=${service.digits}`,
            `period=${service.period}`,
            `algorithm=${String(service.algorithm ?? "SHA1").toUpperCase()}`
        ];
        if (issuer.length > 0)
            params.push(`issuer=${encodeURIComponent(issuer)}`);
        return `otpauth://totp/${encodeURIComponent(label)}?${params.join("&")}`;
    }

    function search(query) {
        if (!root.authEnabled || root.services.length === 0)
            return [];
        const raw = String(query ?? "").trim().toLowerCase();
        // "!" alone lists everything so codes are one keystroke + Enter away
        if (raw.length === 0)
            return root.services.slice(0);
        if (["2fa", "otp", "totp", "auth", "authenticator", "codes"].includes(raw))
            return root.services.slice(0);

        const results = [];
        for (const service of root.services) {
            const issuer = String(service.issuer ?? "").toLowerCase();
            const name = String(service.name ?? "").toLowerCase();
            const haystack = `${issuer} ${name}`.trim();
            let score = 0;
            if (issuer.startsWith(raw) || name.startsWith(raw))
                score = 900;
            else if (haystack.startsWith(raw))
                score = 800;
            else if (issuer.includes(raw) || name.includes(raw) || haystack.includes(raw))
                score = 500;
            else if (raw.split(/\s+/).every(token => haystack.includes(token)))
                score = 300;
            if (score > 0)
                results.push({ service, score });
        }
        results.sort((left, right) => right.score - left.score);
        return results.map(result => result.service);
    }

    // ------------------------------- Copy --------------------------------
    function copyCode(id) {
        const service = root.serviceById(id);
        const label = root.labelOf(service);
        const code = root.codeFor(id);
        if (code.length > 0) {
            root._copy(code, label);
            return;
        }
        // Stream not up yet (e.g. launched a heartbeat ago): ask for one code.
        root.pendingCopyId = id;
        codeProc.command = ["python3", root.scriptPath, "--store", root.storePath, "code", String(id)];
        codeProc.running = true;
    }

    function _copy(code, label) {
        Quickshell.clipboardText = code;
        if (root.clearClipboardAfter > 0) {
            clearTimer.code = code;
            clearTimer.restart();
        }
    }

    function notify(summary, body) {
        Quickshell.execDetached(["notify-send", "-a", "Authenticator", String(summary ?? ""), String(body ?? "")]);
    }

    // ----------------------------- Commands ------------------------------
    function commandHelp() {
        return Translation.tr("Usage (search bar):\n"
            + "/auth add <Issuer:account> <secret>\n"
            + "/auth remove <label>   ·   /auth rename <label> <new label>\n"
            + "/auth secret <label> <new secret>\n"
            + "/auth set <label> digits=6 period=30 algorithm=SHA1\n"
            + "/auth import [file]   (no file = clipboard)\n"
            + "/auth export [json|uri] [file]\n"
            + "/auth list\n"
            + "Services stay editable in ~/.config/illogical-impulse/authenticators.json");
    }

    function _timestamp() {
        const now = new Date();
        const pad = value => String(value).padStart(2, "0");
        return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
    }

    function defaultExportPath(format) {
        const extension = format === "uri" ? "txt" : "json";
        return FileUtils.trimFileProtocol(`${Directories.home}/authenticators-${root._timestamp()}.${extension}`);
    }

    function handleCommand(input) {
        const parts = String(input ?? "").trim().split(/\s+/).filter(part => part.length > 0);
        const subcommand = (parts[0] ?? "").toLowerCase();
        const rest = parts.slice(1);

        switch (subcommand) {
        case "":
        case "help":
        case "?":
            root.notify("Authenticator", root.commandHelp());
            return;
        case "list":
        case "ls":
            root.notify("Authenticator", root.services.length > 0
                ? root.services.map(service => `${root.labelOf(service)}   ${root.displayCode(service.id)}`).join("\n")
                : Translation.tr("No authenticator services yet"));
            return;
        case "add":
        case "a":
            if (rest.length < 2) {
                root.notify("Authenticator", Translation.tr("Usage: /auth add <Issuer:account> <secret>"));
                return;
            }
            root._run(["add", rest[rest.length - 1], "--label", rest.slice(0, -1).join(" "),
                "--digits", String(root.defaultDigits), "--period", String(root.defaultPeriod),
                "--algorithm", root.defaultAlgorithm]);
            return;
        case "remove":
        case "rm":
        case "delete":
            if (rest.length === 0) {
                root.notify("Authenticator", Translation.tr("Usage: /auth remove <label>"));
                return;
            }
            root._run(["remove", rest.join(" ")]);
            return;
        case "rename":
        case "mv":
            if (rest.length < 2) {
                root.notify("Authenticator", Translation.tr("Usage: /auth rename <label> <new label>"));
                return;
            }
            root._run(["update", rest[0], "--name", rest.slice(1).join(" ")]);
            return;
        case "secret":
            if (rest.length < 2) {
                root.notify("Authenticator", Translation.tr("Usage: /auth secret <label> <new secret>"));
                return;
            }
            root._run(["update", rest[0], "--secret", rest[1]]);
            return;
        case "set": {
            if (rest.length < 2) {
                root.notify("Authenticator", Translation.tr("Usage: /auth set <label> digits=6 period=30 algorithm=SHA1"));
                return;
            }
            const options = {
                "name": "--name", "issuer": "--issuer", "secret": "--secret",
                "digits": "--digits", "period": "--period", "algorithm": "--algorithm"
            };
            const args = ["update", rest[0]];
            for (const token of rest.slice(1)) {
                const separator = token.indexOf("=");
                if (separator <= 0)
                    continue;
                const option = options[token.slice(0, separator).toLowerCase()];
                const value = token.slice(separator + 1);
                if (option && value.length > 0)
                    args.push(option, value);
            }
            if (args.length < 4) {
                root.notify("Authenticator", Translation.tr("Nothing to change. Try name=, digits= or period="));
                return;
            }
            root._run(args);
            return;
        }
        case "import": {
            const target = rest[0] ?? "";
            if (target.length === 0) {
                root.importFromClipboard();
                return;
            }
            root._run(["import", target]);
            return;
        }
        case "export": {
            let format = "json";
            let path = "";
            for (const token of rest) {
                if (token === "json" || token === "uri")
                    format = token;
                else
                    path = token;
            }
            root._run(["export", "--format", format, "--out",
                path.length > 0 ? path : root.defaultExportPath(format)]);
            return;
        }
        default:
            root.notify("Authenticator", root.commandHelp());
        }
    }

    function _run(args) {
        if (actionProc.running)
            actionProc.running = false;
        actionProc.command = ["python3", root.scriptPath, "--store", root.storePath, ...args];
        actionProc.running = true;
    }

    function _finishAction(text) {
        let data = null;
        try {
            data = JSON.parse(text);
        } catch (error) {
            data = null;
        }
        if (!data) {
            root.notify("Authenticator", Translation.tr("The authenticator script failed. Is python3 installed?"));
            return;
        }
        if (data.error) {
            root.notify("Authenticator", String(data.error));
            return;
        }
        if (data.added !== undefined) {
            root.notify("Authenticator", Translation.tr("Imported %1, skipped %2").arg(data.added).arg(data.skipped));
        } else if (data.path !== undefined) {
            Quickshell.clipboardText = String(data.path);
            root.notify("Authenticator", Translation.tr("Exported %1 service(s) to %2").arg(data.count).arg(data.path));
        }
        root.refresh();
    }

    function importFromClipboard() {
        const payload = Quickshell.clipboardText ?? "";
        if (String(payload).trim().length === 0) {
            root.notify("Authenticator", Translation.tr("Clipboard is empty"));
            return;
        }
        importProc.pendingPayload = payload;
        importProc.stdinEnabled = true;
        importProc.running = true;
    }

    // ------------------------------- State -------------------------------
    FileView {
        id: storeView
        path: root.storePath
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onLoaded: root.reloadServices()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.services = [];
            } else {
                console.log("[Authenticator] Could not read store:", error);
            }
        }
    }

    Timer {
        id: reloadTimer
        interval: 120
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: ["python3", root.scriptPath, "--store", root.storePath, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data = null;
                try {
                    data = JSON.parse(this.text);
                } catch (error) {
                    console.log("[Authenticator] Bad service list output:", error);
                    return;
                }
                if (data.error) {
                    root.lastError = String(data.error);
                    console.log("[Authenticator]", data.error);
                    return;
                }
                root.services = (data.services ?? []).map(service => ({
                    "id": String(service.id ?? ""),
                    "issuer": String(service.issuer ?? ""),
                    "name": String(service.name ?? ""),
                    "secret": String(service.secret ?? ""),
                    "digits": Number(service.digits ?? 6),
                    "period": Number(service.period ?? 30),
                    "algorithm": String(service.algorithm ?? "SHA1")
                })).filter(service => service.id.length > 0);
                root.lastError = "";
            }
        }
    }

    Process {
        id: streamProc
        command: ["python3", root.scriptPath, "--store", root.storePath, "stream"]
        stdout: SplitParser {
            onRead: line => root._handleStreamLine(line)
        }
        stderr: SplitParser {
            onRead: line => console.log("[Authenticator]", line)
        }
        onExited: (exitCode, exitStatus) => {
            if (!root.streamWanted) {
                root.codes = ({});
                return;
            }
            root._streamFailures += 1;
            if (root._streamFailures <= 5)
                retryTimer.restart();
        }
    }

    function _handleStreamLine(line) {
        if (!line || line[0] !== "{")
            return;
        let data = null;
        try {
            data = JSON.parse(line);
        } catch (error) {
            return;
        }
        if (data.type !== "codes")
            return;
        const map = {};
        for (const entry of (data.services ?? []))
            map[entry.id] = entry;
        root._streamFailures = 0;
        root.codes = map;
    }

    Timer {
        id: retryTimer
        interval: 1500
        onTriggered: {
            if (root.streamWanted && !streamProc.running)
                streamProc.running = true;
        }
    }

    Timer { // Watchdog: process died without us noticing a state change
        interval: 10000
        repeat: true
        running: root.streamWanted
        onTriggered: {
            if (!streamProc.running && !retryTimer.running && root._streamFailures <= 5)
                retryTimer.restart();
        }
    }

    Process {
        id: codeProc
        stdout: StdioCollector {
            onStreamFinished: {
                const code = String(this.text ?? "").trim();
                if (code.length === 0) {
                    console.log("[Authenticator] Could not compute that code");
                    return;
                }
                root._copy(code, root.labelOf(root.serviceById(root.pendingCopyId)));
            }
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: root._finishAction(this.text)
        }
    }

    Process {
        id: importProc
        property string pendingPayload: ""
        command: ["python3", root.scriptPath, "--store", root.storePath, "import"]
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: root._finishAction(this.text)
        }
        onRunningChanged: {
            if (importProc.running) {
                importProc.write(importProc.pendingPayload);
                importProc.stdinEnabled = false;
                importProc.pendingPayload = "";
            }
        }
    }

    Timer {
        id: clearTimer
        property string code: ""
        interval: Math.max(1, root.clearClipboardAfter) * 1000
        onTriggered: {
            if (Quickshell.clipboardText === clearTimer.code)
                Quickshell.clipboardText = "";
        }
    }
}
