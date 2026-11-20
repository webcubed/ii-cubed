import "palette.js" as Mac
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: root
    required property var element

    // Search state pushed down by CheatsheetPeriodicTable; it owns the ranking,
    // so a tile only needs to know whether it should fade out.
    property bool isSelected: false
    property bool dimmed: false

    // Sized by the page so the whole table fits next to the detail card.
    property real tileSize: 70

    // The page maps the active layer (category, electronegativity, block, …)
    // to a colour and a bottom-of-tile label.
    property color accent: root.categoryColor(root.element.type)
    property string bottomLabel: root.element.name

    // How much of `accent` tints the tile. The page raises this for the block
    // and phase layers so neighbouring blocks and phases read differently.
    property real fillStrength: 0.86
    // Block and phase layers keep a thin accent ring and an accent label on
    // every tile, so the table stays readable at a glance.
    property bool emphasised: false

    signal picked(var element)

    readonly property bool empty: element.type === "empty"

    // Catppuccin Macchiato, matching the page. The page normally passes the
    // accent in; this default is only used when a tile stands on its own.
    function categoryColor(type) {
        switch (type) {
        case "metal": return Mac.colors.blue;
        case "nonmetal": return Mac.colors.green;
        case "noblegas": return Mac.colors.mauve;
        case "lanthanum": return Mac.colors.peach;
        case "actinium": return Mac.colors.pink;
        default: return Mac.colors.subtext0;
        }
    }

    /// How much of `accent` is painted into the tile, 0..1. The page's
    /// fillStrength is a transparency (0.86 = 14% accent), so invert it.
    readonly property real tint: Math.max(0, Math.min(1, 1 - root.fillStrength))

    /// The fill blended onto the cheat sheet's own background (colLayer0) — the
    /// colour the glyphs are actually painted on. Keeping it opaque means the
    /// text contrast below is measured, not guessed from the raw hue.
    readonly property color tileBackground: ColorUtils.mix(
        root.accent, Appearance.colors.colLayer0, root.isSelected ? Math.min(1, root.tint + 0.14) : root.tint)

    // WCAG relative luminance and contrast ratio, used to pick the glyph colour.
    function channelLuminance(channel) {
        return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
    }
    function luminance(color) {
        const c = Qt.color(color);
        return 0.2126 * root.channelLuminance(c.r) + 0.7152 * root.channelLuminance(c.g) + 0.0722 * root.channelLuminance(c.b);
    }
    function contrastRatio(a, b) {
        const la = root.luminance(a);
        const lb = root.luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    /// Accent or Macchiato crust, whichever reads better on the painted fill:
    /// pale tiles (the white gases) get dark glyphs, saturated ones keep their hue.
    readonly property color symbolColor: {
        const dark = root.contrastRatio(Mac.colors.crust, root.tileBackground);
        const hue = root.contrastRatio(root.accent, root.tileBackground);
        return dark > hue ? Mac.colors.crust : root.accent;
    }
    readonly property int badgeSize: Math.max(16, Math.round(root.tileSize * 0.27))

    opacity: root.empty ? 0 : (root.dimmed ? 0.25 : 1)
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    implicitHeight: root.tileSize
    implicitWidth: root.tileSize
    colBackground: root.empty ? Appearance.colors.colLayer2 : root.tileBackground
    colBackgroundHover: ColorUtils.mix(root.accent, Appearance.colors.colLayer0, Math.min(1, root.tint + 0.16))
    colBackgroundActive: ColorUtils.mix(root.accent, Appearance.colors.colLayer0, Math.min(1, root.tint + 0.28))
    buttonRadius: Appearance.rounding.small
    // The page keeps keyboard focus so arrow keys walk the table; a clicked
    // tile must not steal it.
    focusPolicy: Qt.NoFocus
    enabled: !root.empty
    onClicked: root.picked(root.element)

    // The selection ring. On the block and phase layers a thin ring stays on
    // every tile: the tint alone is too soft to separate neighbours at a
    // glance, the full-strength edge is not.
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: "transparent"
        border.width: root.isSelected ? 2 : 1
        border.color: root.isSelected ? root.symbolColor : ColorUtils.transparentize(root.symbolColor, 0.4)
        visible: root.isSelected || root.emphasised
    }

    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            topMargin: 3
            leftMargin: 3
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer2)
        radius: Appearance.rounding.full
        implicitWidth: Math.max(root.badgeSize, elementNumber.implicitWidth + 4)
        implicitHeight: root.badgeSize
        width: Math.max(root.badgeSize, elementNumber.implicitWidth + 4)
        height: root.badgeSize

        StyledText {
            id: elementNumber
            anchors.centerIn: parent
            color: Appearance.colors.colOnLayer2
            text: root.element.number
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    Rectangle {
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 3
            rightMargin: 3
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer2)
        radius: Appearance.rounding.full
        implicitWidth: Math.max(root.badgeSize, elementWeight.implicitWidth + 4)
        implicitHeight: root.badgeSize
        width: Math.max(root.badgeSize, elementWeight.implicitWidth + 4)
        height: root.badgeSize

        StyledText {
            id: elementWeight
            anchors.centerIn: parent
            color: Appearance.colors.colOnLayer2
            text: root.element.weight
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    StyledText {
        id: elementSymbol
        anchors.centerIn: parent
        color: root.symbolColor
        font.pixelSize: Math.round(root.tileSize * 0.40)
        text: root.element.symbol
    }

    StyledText {
        id: elementName
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 3
        }
        width: parent.width - 6
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: root.emphasised ? root.symbolColor : Appearance.colors.colOnLayer2
        text: root.bottomLabel
    }
}
