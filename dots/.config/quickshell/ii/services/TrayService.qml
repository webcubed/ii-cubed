pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    id: root

    property bool smartTray: Config.options.tray.filterPassive

    /**
     * Quickshell keeps a StatusNotifierItem object for every registration it has
     * seen and never drops the old ones, while fcitx re-registers with each new
     * StatusNotifierWatcher. Every shell reload therefore left another identical
     * "Input Method" keyboard icon in the bar. The watcher only knows the latest
     * registration, so collapse identical items and keep the newest (the one
     * appended last) — its menu and activate() still point at the live item.
     */
    readonly property var uniqueItems: {
        const values = SystemTray.items.values;
        const seen = new Set();
        const result = [];
        for (let index = values.length - 1; index >= 0; index -= 1) {
            const item = values[index];
            if (!item)
                continue;
            const key = `${item.id}\u0000${item.title}\u0000${item.icon}`;
            if (seen.has(key))
                continue;
            seen.add(key);
            result.unshift(item);
        }
        return result;
    }

    property list<var> itemsInUserList: root.uniqueItems.filter(i => (Config.options.tray.pinnedItems.includes(i.id) && (!smartTray || i.status !== Status.Passive)))
    property list<var> itemsNotInUserList: root.uniqueItems.filter(i => (!Config.options.tray.pinnedItems.includes(i.id) && (!smartTray || i.status !== Status.Passive)))

    property bool invertPins: Config.options.tray.invertPinnedItems
    property list<var> pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    property list<var> unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList

    function getTooltipForItem(item) {
        var result = item.tooltipTitle.length > 0 ? item.tooltipTitle
                : (item.title.length > 0 ? item.title : item.id);
        if (item.tooltipDescription.length > 0) result += " • " + item.tooltipDescription;
        if (Config.options.tray.showItemId) result += "\n[" + item.id + "]";
        return result;
    }

    // Pinning
    function pin(itemId) {
        var pins = Config.options.tray.pinnedItems;
        if (pins.includes(itemId)) return;
        Config.options.tray.pinnedItems = [...pins, itemId];
    }
    function unpin(itemId) {
        Config.options.tray.pinnedItems = Config.options.tray.pinnedItems.filter(id => id !== itemId);
    }
    function isPinned(itemId) {
        const inList = Config.options.tray.pinnedItems.includes(itemId);
        return Config.options.tray.invertPinnedItems ? !inList : inList;
    }

    function togglePin(itemId) {
        if (Config.options.tray.pinnedItems.includes(itemId)) {
            unpin(itemId)
        } else {
            pin(itemId)
        }
    }

}
