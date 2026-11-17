import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "commands"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
Scope { // Scope
    id: root

    // Load the panel once (on first open) and keep it alive, toggling visibility
    // instead of destroying it — avoids re-creation rendering bugs with async
    // extension pages.
    property bool shown: false
    onShownChanged: if (root.shown) cheatsheetLoader.active = true

    // cheatsheet contribution point: external extension tabs
    property var extensionPages: ExtensionManager.ready ? ExtensionManager.getContributionPoint("cheatsheet") : []
    Connections {
        target: ExtensionManager
        function onRefreshExtensions() { root.extensionPages = ExtensionManager.getContributionPoint("cheatsheet") }
        function onExtensionInstalled() { root.extensionPages = ExtensionManager.getContributionPoint("cheatsheet") }
        function onExtensionRemoved() { root.extensionPages = ExtensionManager.getContributionPoint("cheatsheet") }
        function onExtensionToggled() { root.extensionPages = ExtensionManager.getContributionPoint("cheatsheet") }
    }
    readonly property var extensionTabs: root.extensionPages.map(p => ({
        key: "ext:" + p.extensionId + ":" + p.identifier,
        icon: p.icon || "extension",
        name: p.title || p.identifier,
        identifier: p.identifier,
        component: ExtensionManager.loadExtensionQmlComponent(p.fullPath),
        extensionId: p.extensionId
    }))

    property int _pageLoadTick: 0
    Component {
        id: emptyPlaceholderComponent
        Item {
            implicitWidth: 420
            implicitHeight: 260
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "extension_off"
                    iconSize: 56
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No cheat sheet pages")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 360
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Translation.tr("Enable a cheat sheet extension in Settings → Extensions to add pages here.")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    Component {
        id: cheatsheetCommandsComponent
        CheatsheetCommands {}
    }

    Component {
        id: cheatsheetTimetableComponent
        CheatsheetTimetable {}
    }

    Component {
        id: cheatsheetPeriodicTableComponent
        CheatsheetPeriodicTable {}
    }

    readonly property var builtInTabs: [
        { key: "commands", icon: "terminal", name: Translation.tr("Commands"), component: cheatsheetCommandsComponent },
        { key: "timetable", icon: "calendar_month", name: Translation.tr("Timetable"), component: cheatsheetTimetableComponent },
        { key: "periodicTable", icon: "science", name: Translation.tr("Periodic table"), component: cheatsheetPeriodicTableComponent }
    ]

    // Built-in tabs first, then extension pages. An installed extension can
    // re-supply a page the shell already builds in (ii-eve-cheatsheet-commands
    // next to the built-in Commands tab), so only the first copy is kept —
    // otherwise the tab bar shows that page twice.
    readonly property var visibleTabs: {
        const tabs = root.builtInTabs.slice();
        const keys = tabs.map(tab => root._tabKey(tab.key));
        const names = tabs.map(tab => root._tabKey(tab.name));
        for (const page of root.extensionTabs) {
            const identifier = root._tabKey(page.identifier);
            const duplicate = keys.some(key => root._sameTab(key, root._tabKey(page.key)) || root._sameTab(key, identifier))
                || names.some(name => root._sameTab(name, root._tabKey(page.name)) || root._sameTab(name, identifier));
            if (duplicate)
                continue;
            tabs.push(page);
            keys.push(root._tabKey(page.key));
            names.push(root._tabKey(page.name));
        }
        // Only a tab bar with nothing else in it needs the placeholder.
        if (tabs.length === 0)
            tabs.push({ key: "empty", icon: "extension_off", name: Translation.tr("Cheat sheet"), component: emptyPlaceholderComponent });
        return tabs;
    }

    function _tabKey(value) {
        return String(value ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    /// Same tab under different spellings: "commands" and "ii-eve-cheatsheet-commands".
    function _sameTab(a, b) {
        if (!a || !b)
            return false;
        if (a === b)
            return true;
        const shorter = a.length <= b.length ? a : b;
        const longer = a.length <= b.length ? b : a;
        return shorter.length >= 5 && longer.includes(shorter);
    }

    readonly property var tabButtonList: root.visibleTabs.map(t => ({ icon: t.icon, name: t.name }))

    Loader {
        id: cheatsheetLoader
        active: false

        sourceComponent: PanelWindow { // Window
            id: cheatsheetRoot
            visible: root.shown

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function hide() {
                root.shown = false;
            }
            exclusiveZone: 0
            implicitWidth: cheatsheetBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: cheatsheetBackground.height + Appearance.sizes.elevationMargin * 2
            WlrLayershell.namespace: "quickshell:cheatsheet"
            // OnDemand at map time hangs the surface for ~5s on some compositors.
            // Map with None first, then upgrade to OnDemand after the panel is visible,
            // and only on tabs that actually need text input (Commands).
            property bool _focusReady: false
            WlrLayershell.keyboardFocus: {
                if (!_focusReady) return WlrKeyboardFocus.None;
                return WlrKeyboardFocus.OnDemand;
            }
            Timer {
                id: focusUpgradeTimer
                interval: 80
                repeat: false
                onTriggered: {
                    cheatsheetRoot._focusReady = true;
                    cheatsheetRoot.focusCurrentTab();
                }
            }
            function focusCurrentTab() {
                const loader = swipeView.itemAt(swipeView.currentIndex);
                if (loader && loader.item) loader.item.forceActiveFocus();
            }
            onVisibleChanged: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(cheatsheetRoot);
                    focusUpgradeTimer.start();
                } else {
                    GlobalFocusGrab.removeDismissable(cheatsheetRoot);
                    _focusReady = false;
                }
            }
            color: "transparent"

            mask: Region {
                item: cheatsheetBackground
            }

            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(cheatsheetRoot);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    cheatsheetRoot.hide();
                }
            }

            // Background
            StyledRectangularShadow {
                target: cheatsheetBackground
            }
            Rectangle {
                id: cheatsheetBackground
                anchors.centerIn: parent
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.windowRounding
                property real padding: 20
                implicitWidth: cheatsheetColumnLayout.implicitWidth + padding * 2
                implicitHeight: cheatsheetColumnLayout.implicitHeight + padding * 2

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        cheatsheetRoot.hide();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left) {
                        tabBar.decrementCurrentIndex();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right) {
                        tabBar.incrementCurrentIndex();
                        event.accepted = true;
                    } else if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_PageDown) {
                            tabBar.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            tabBar.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex + 1) % root.tabButtonList.length);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            tabBar.setCurrentIndex((tabBar.currentIndex - 1 + root.tabButtonList.length) % root.tabButtonList.length);
                            event.accepted = true;
                        }
                    }
                }

                RippleButton { // Close button
                    id: closeButton
                    focusPolicy: Qt.NoFocus
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: 20
                        rightMargin: 20
                    }

                    onClicked: {
                        cheatsheetRoot.hide();
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.title
                        text: "close"
                    }
                }

                ColumnLayout { // Real content
                    id: cheatsheetColumnLayout
                    anchors.centerIn: parent
                    spacing: 10

                    Toolbar {
                        Layout.alignment: Qt.AlignHCenter
                        enableShadow: false
                        ToolbarTabBar {
                            id: tabBar
                            tabButtonList: root.tabButtonList

                            Synchronizer on currentIndex {
                                property alias source: swipeView.currentIndex
                            }
                        }
                    }

                    SwipeView { // Content pages
                        id: swipeView
                        Layout.topMargin: 5
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10
                        currentIndex: Persistent.states.cheatsheet.tabIndex
                        onCurrentIndexChanged: {
                            Persistent.states.cheatsheet.tabIndex = currentIndex;
                            if (cheatsheetRoot._focusReady) cheatsheetRoot.focusCurrentTab();
                        }

                        Connections {
                            target: root
                            function onTabButtonListChanged() {
                                if (swipeView.currentIndex >= root.tabButtonList.length) {
                                    swipeView.currentIndex = Math.max(0, root.tabButtonList.length - 1);
                                }
                            }
                        }

                        implicitWidth: {
                            root._pageLoadTick; // re-evaluate when an (async) extension page loads
                            const w = Math.max.apply(null, contentChildren.map(child => child.implicitWidth || 0));
                            return (isFinite(w) && w > 0) ? w : 420;
                        }
                        implicitHeight: {
                            root._pageLoadTick;
                            const h = Math.max.apply(null, contentChildren.map(child => child.implicitHeight || 0));
                            return (isFinite(h) && h > 0) ? h : 260;
                        }

                        clip: true
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: swipeView.width
                                height: swipeView.height
                                radius: Appearance.rounding.small
                            }
                        }

                        Repeater {
                            model: root.visibleTabs
                            delegate: Loader {
                                required property var modelData
                                required property int index
                                sourceComponent: modelData.component
                                onLoaded: {
                                    if (item && "tabIndex" in item)
                                        item.tabIndex = index;
                                    if (item && "keyNavTarget" in item)
                                        item.keyNavTarget = cheatsheetBackground;
                                    if (modelData.extensionId && item) {
                                        if ("extensionId" in item) {
                                            item.extensionId = modelData.extensionId;
                                        } else {
                                            Object.defineProperty(item, "extensionId", {
                                                value: modelData.extensionId,
                                                writable: true,
                                                configurable: true,
                                                enumerable: true
                                            });
                                        }
                                    }
                                    root._pageLoadTick++; // force SwipeView implicit-size recompute
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            root.shown = !root.shown;
        }

        function close(): void {
            root.shown = false;
        }

        function open(): void {
            root.shown = true;
        }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles cheatsheet on press"

        onPressed: {
            root.shown = !root.shown;
        }
    }

    GlobalShortcut {
        name: "cheatsheetOpen"
        description: "Opens cheatsheet on press"

        onPressed: {
            root.shown = true;
        }
    }

    GlobalShortcut {
        name: "cheatsheetClose"
        description: "Closes cheatsheet on press"

        onPressed: {
            root.shown = false;
        }
    }
}
