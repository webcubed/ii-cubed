pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * Rows for the action palette (`/`): every command with its description, and
 * the subcommands/arguments of the ones that take them.
 */
Singleton {
    id: root

    function rows(actionPrefix, text, actions, authPrefix) {
        const trimmed = String(text ?? "").trim();
        const space = trimmed.indexOf(" ");
        const name = (space < 0 ? trimmed : trimmed.slice(0, space)).toLowerCase();
        const args = space < 0 ? "" : trimmed.slice(space + 1).trim();

        if (name === "auth")
            return AuthMenu.commands(actionPrefix, args, authPrefix);

        const matches = actions.filter(action => action.action.toLowerCase().startsWith(name));
        if (matches.length === 0)
            return actions.map(action => root._commandRow(action, ""));
        return matches.map(action => root._commandRow(action, args));
    }

    function _commandRow(action, args) {
        return {
            "type": action.description ?? action.action,
            "name": args.length > 0 ? `${action.action} ${args}` : action.action,
            "icon": action.icon ?? "settings_suggest",
            "verb": Translation.tr("Run"),
            "execute": () => action.execute(args)
        };
    }
}
