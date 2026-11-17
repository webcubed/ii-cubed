pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Rows for the authenticator surface (`!`): the service list, a menu per
 * service and the add/rename/delete flows.
 *
 * Nothing here reads Authenticator.codes: upcoming rows carry only an index and
 * SearchItem pulls the live code and countdown from the service in the
 * delegate. Building those rows from the live stream here rebuilt the whole
 * results list every second, which reset the selected row while navigating.
 */
Singleton {
    id: root

    readonly property int maxServices: 12
    readonly property int upcomingRows: 3

    function rows(prefix, raw) {
        const text = String(raw ?? "").trim();
        if (text === "add" || text.startsWith("add "))
            return root._add(prefix, text.slice(3).trim());
        const marker = text.indexOf(">");
        if (marker >= 0)
            return root._detail(prefix, text.slice(0, marker).trim(), text.slice(marker + 1).trim());
        return root._list(prefix, text);
    }

    // -------------------------------- List --------------------------------
    function _list(prefix, query) {
        if (!Authenticator.authEnabled) {
            return [LauncherMenu.noteRow(
                Translation.tr("Authenticator"),
                Translation.tr("Authenticator codes are disabled in the config"),
                "key_off"
            )];
        }

        if (Authenticator.services.length === 0) {
            return [{
                "type": Translation.tr("Authenticator"),
                "name": Translation.tr("No services yet — add one"),
                "icon": "add",
                "verb": Translation.tr("Add"),
                "drill": `${prefix} add `
            }, LauncherMenu.noteRow(
                Translation.tr("Authenticator"),
                Translation.tr("Format: Label:account SECRET"),
                "info"
            )];
        }

        const matches = Authenticator.search(query).slice(0, root.maxServices);
        const rows = matches.map(service => ({
            "type": Translation.tr("Authenticator"),
            "name": Authenticator.labelOf(service),
            "icon": "key",
            "verb": Translation.tr("More"),
            "liveAuthenticatorId": service.id,
            "drill": `${prefix} ${Authenticator.labelOf(service)} >`,
            "execute": () => Authenticator.copyCode(service.id),
            "actions": [{ "name": Translation.tr("Copy code"), "icon": "content_copy", "execute": () => Authenticator.copyCode(service.id) }]
        }));

        if (query.length === 0)
            rows.push({
                "type": Translation.tr("Authenticator"),
                "name": Translation.tr("Add a service…"),
                "icon": "add",
                "verb": Translation.tr("Add"),
                "drill": `${prefix} add `
            });

        if (matches.length === 0)
            rows.push(LauncherMenu.noteRow(
                Translation.tr("Authenticator"),
                Translation.tr("No service matches \"%1\"").arg(query),
                "search_off"
            ));
        return rows;
    }

    // ------------------------------- Detail -------------------------------
    function _detail(prefix, selector, action) {
        const service = root._find(selector);
        if (!service) {
            return [LauncherMenu.noteRow(
                Translation.tr("Authenticator"),
                Translation.tr("No service matches \"%1\"").arg(selector),
                "search_off"
            ), LauncherMenu.backRow(`${prefix} `, Translation.tr("Back to services"))];
        }

        const label = Authenticator.labelOf(service);
        const step = String(action ?? "").trim();

        if (step === "rename" || step.startsWith("rename "))
            return root._rename(prefix, service, step.slice(6).trim());
        if (step === "secret" || step.startsWith("secret "))
            return root._changeSecret(prefix, service, step.slice(6).trim());
        if (step === "delete")
            return root._delete(prefix, service);

        const settings = `${String(service.algorithm ?? "SHA1").toUpperCase()} · ${service.digits} digits · ${service.period}s`;
        const rows = [{
            "type": `${label} · ${settings}`,
            "name": Translation.tr("Copy code"),
            "icon": "content_copy",
            "verb": Translation.tr("Copy"),
            "liveAuthenticatorId": service.id,
            "execute": () => Authenticator.copyCode(service.id),
            "actions": [{
                "name": Translation.tr("Copy code"),
                "icon": "content_copy",
                "execute": () => Authenticator.copyCode(service.id)
            }]
        }];

        // Live in the delegate: the row text is filled from Authenticator there.
        for (let index = 0; index < root.upcomingRows; index++) {
            rows.push({
                "type": Translation.tr("Upcoming"),
                "name": "",
                "icon": "schedule",
                "fontType": "monospace",
                "verb": Translation.tr("Copy"),
                "liveAuthenticatorId": service.id,
                "liveUpcomingIndex": index,
                "execute": () => root._copyUpcoming(service.id, index)
            });
        }

        rows.push({
            "type": Translation.tr("Secret"),
            "name": Translation.tr("Copy secret"),
            "icon": "password",
            "verb": Translation.tr("Copy"),
            "execute": () => LauncherMenu.copy(service.secret)
        });
        rows.push({
            "type": Translation.tr("Settings"),
            "name": settings,
            "icon": "tune",
            "verb": Translation.tr("More"),
            "actions": [{
                "name": Translation.tr("Copy otpauth URI"),
                "icon": "link",
                "execute": () => LauncherMenu.copy(Authenticator.otpauthUri(service))
            }]
        });
        rows.push({
            "type": Translation.tr("Edit"),
            "name": Translation.tr("Rename \"%1\"…").arg(label),
            "icon": "edit",
            "verb": Translation.tr("Edit"),
            "drill": `${prefix} ${label} > rename `
        });
        rows.push({
            "type": Translation.tr("Edit"),
            "name": Translation.tr("Change the secret…"),
            "icon": "key",
            "verb": Translation.tr("Edit"),
            "drill": `${prefix} ${label} > secret `
        });
        rows.push({
            "type": Translation.tr("Edit"),
            "name": Translation.tr("Delete \"%1\"…").arg(label),
            "icon": "delete",
            "verb": Translation.tr("Delete"),
            "drill": `${prefix} ${label} > delete`
        });
        rows.push(LauncherMenu.backRow(`${prefix} `, Translation.tr("Back to services")));
        return rows;
    }

    function _rename(prefix, service, value) {
        const label = Authenticator.labelOf(service);
        if (value.length === 0) {
            return [LauncherMenu.noteRow(
                Translation.tr("Rename"),
                Translation.tr("Keep typing the new label for \"%1\"").arg(label),
                "edit"
            ), LauncherMenu.backRow(`${prefix} ${label} >`, Translation.tr("Back"))];
        }
        return [{
            "type": Translation.tr("Rename"),
            "name": Translation.tr("Rename to \"%1\"").arg(value),
            "icon": "edit",
            "verb": Translation.tr("Rename"),
            "execute": () => Authenticator.handleCommand(`rename ${label} ${value}`)
        }, LauncherMenu.backRow(`${prefix} ${label} >`, Translation.tr("Back"))];
    }

    function _changeSecret(prefix, service, value) {
        const label = Authenticator.labelOf(service);
        if (value.length === 0) {
            return [LauncherMenu.noteRow(
                Translation.tr("New secret"),
                Translation.tr("Keep typing the base32 secret for \"%1\"").arg(label),
                "password"
            ), LauncherMenu.backRow(`${prefix} ${label} >`, Translation.tr("Back"))];
        }
        const secret = value.replace(/\s+/g, "").toUpperCase();
        const valid = /^[A-Z2-7]+=*$/.test(secret) && secret.length >= 16;
        return [{
            "type": Translation.tr("New secret"),
            "name": valid
                ? Translation.tr("Set the new secret for \"%1\"").arg(label)
                : Translation.tr("That secret isn't base32"),
            "icon": valid ? "key" : "error",
            "verb": valid ? Translation.tr("Save") : "",
            "execute": valid ? () => Authenticator.handleCommand(`secret ${label} ${secret}`) : () => {}
        }, LauncherMenu.backRow(`${prefix} ${label} >`, Translation.tr("Back"))];
    }

    function _delete(prefix, service) {
        const label = Authenticator.labelOf(service);
        return [{
            "type": Translation.tr("Delete"),
            "name": Translation.tr("Delete \"%1\"").arg(label),
            "icon": "delete",
            "verb": Translation.tr("Delete"),
            "execute": () => Authenticator.handleCommand(`remove ${label}`)
        }, LauncherMenu.backRow(`${prefix} ${label} >`, Translation.tr("Cancel"))];
    }

    // -------------------------------- Add ---------------------------------
    function _add(prefix, args) {
        const text = String(args ?? "").trim();
        const tokens = text.split(/\s+/).filter(token => token.length > 0);
        const rows = [LauncherMenu.noteRow(
            Translation.tr("Add a service"),
            Translation.tr("Label:account SECRET — e.g. GitHub:you JBSWY3DP…"),
            "key"
        )];
        if (tokens.length < 2)
            return rows.concat([LauncherMenu.backRow(`${prefix} `, Translation.tr("Back to services"))]);

        const secret = tokens[tokens.length - 1].replace(/\s+/g, "").toUpperCase();
        const label = tokens.slice(0, -1).join(" ");
        const valid = /^[A-Z2-7]+=*$/.test(secret) && secret.length >= 16;
        rows.push({
            "type": Translation.tr("Add a service"),
            "name": valid ? Translation.tr("Add \"%1\"").arg(label) : Translation.tr("That secret isn't base32"),
            "icon": valid ? "add" : "error",
            "verb": valid ? Translation.tr("Add") : "",
            "execute": valid ? () => Authenticator.handleCommand(`add ${label} ${secret}`) : () => {}
        });
        rows.push(LauncherMenu.backRow(`${prefix} `, Translation.tr("Back to services")));
        return rows;
    }

    // ------------------------- Command palette rows ------------------------
    readonly property var subcommands: [
        { "name": "add", "usage": "add <Issuer:account> <secret>", "icon": "add", "description": Translation.tr("Add a service from a base32 secret") },
        { "name": "remove", "usage": "remove <label>", "icon": "delete", "description": Translation.tr("Delete a service") },
        { "name": "rename", "usage": "rename <label> <new label>", "icon": "edit", "description": Translation.tr("Rename a service") },
        { "name": "secret", "usage": "secret <label> <new secret>", "icon": "password", "description": Translation.tr("Replace a service's secret") },
        { "name": "set", "usage": "set <label> name= issuer= digits= period= algorithm=", "icon": "tune", "description": Translation.tr("Change service options") },
        { "name": "import", "usage": "import [file]", "icon": "download", "description": Translation.tr("Import services (no file = clipboard)") },
        { "name": "export", "usage": "export [json|uri] [file]", "icon": "upload", "description": Translation.tr("Export services") },
        { "name": "list", "usage": "list", "icon": "list", "description": Translation.tr("Show every service") }
    ]

    function commands(actionPrefix, args, authPrefix) {
        const text = String(args ?? "").trim();
        if (text.length === 0) {
            return [{
                "type": "/auth",
                "name": Translation.tr("Browse services"),
                "icon": "key",
                "verb": Translation.tr("Open"),
                "drill": `${authPrefix}`
            }].concat(root.subcommands.map(command => ({
                "type": "/auth",
                "name": command.usage,
                "icon": command.icon,
                "verb": Translation.tr("More"),
                "drill": `${actionPrefix}auth ${command.name} `
            })));
        }

        const parts = text.split(/\s+/).filter(part => part.length > 0);
        const subcommand = parts[0].toLowerCase();
        const rest = parts.slice(1);
        let description = Translation.tr("Run /auth %1").arg(text);
        if (subcommand === "add" && rest.length >= 2)
            description = Translation.tr("Add \"%1\"").arg(rest.slice(0, -1).join(" "));
        else if ((subcommand === "remove" || subcommand === "delete") && rest.length > 0)
            description = Translation.tr("Delete \"%1\"").arg(rest.join(" "));
        else if (subcommand === "rename" && rest.length >= 2)
            description = Translation.tr("Rename \"%1\" to \"%2\"").arg(rest[0]).arg(rest.slice(1).join(" "));
        else if (subcommand === "secret" && rest.length >= 2)
            description = Translation.tr("Change the secret for \"%1\"").arg(rest[0]);
        else if (subcommand === "export")
            description = Translation.tr("Export services");

        const rows = [{
            "type": "/auth",
            "name": description,
            "icon": "key",
            "verb": Translation.tr("Run"),
            "execute": () => Authenticator.handleCommand(text)
        }];
        const match = root.subcommands.find(command => command.name === subcommand);
        if (match)
            rows.push(LauncherMenu.noteRow(match.usage, match.description, match.icon));
        rows.push({
            "type": "/auth",
            "name": Translation.tr("Browse services"),
            "icon": "list",
            "verb": Translation.tr("Open"),
            "drill": `${authPrefix}`
        });
        return rows;
    }

    // ------------------------------ Helpers ------------------------------
    function _find(selector) {
        const needle = String(selector ?? "").trim().toLowerCase();
        if (needle.length === 0)
            return null;
        return Authenticator.services.find(service => service.id === selector)
            ?? Authenticator.services.find(service => Authenticator.labelOf(service).toLowerCase() === needle)
            ?? Authenticator.services.find(service => Authenticator.labelOf(service).toLowerCase().startsWith(needle))
            ?? null;
    }

    function _copyUpcoming(id, index) {
        const upcoming = Authenticator.upcomingFor(id);
        const code = upcoming[index]?.code ?? "";
        if (code.length > 0)
            LauncherMenu.copy(code);
        else
            Authenticator.copyCode(id);
    }
}
