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

    signal picked(var element)

    readonly property bool empty: element.type === "empty"

    function categoryColor(type) {
        switch (type) {
        case "metal": return Appearance.colors.colPrimary;
        case "nonmetal": return Appearance.colors.colSecondary;
        case "noblegas": return Appearance.colors.colTertiary;
        case "lanthanum": return Appearance.colors.colError;
        case "actinium": return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colTertiary, 0.45);
        default: return Appearance.colors.colSubtext;
        }
    }

    readonly property color category: root.categoryColor(root.element.type)
    readonly property color tileBackground: ColorUtils.transparentize(root.category, root.isSelected ? 0.72 : 0.86)

    opacity: root.empty ? 0 : (root.dimmed ? 0.25 : 1)
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    implicitHeight: 70
    implicitWidth: 70
    colBackground: root.empty ? Appearance.colors.colLayer2 : root.tileBackground
    colBackgroundHover: ColorUtils.transparentize(root.category, 0.72)
    colBackgroundActive: ColorUtils.transparentize(root.category, 0.6)
    buttonRadius: Appearance.rounding.small
    enabled: !root.empty
    onClicked: root.picked(root.element)

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: "transparent"
        border.width: 2
        border.color: root.category
        visible: root.isSelected
    }

    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            topMargin: 4
            leftMargin: 4
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer2)
        radius: Appearance.rounding.full
        implicitWidth: Math.max(20, elementNumber.implicitWidth)
        implicitHeight: Math.max(20, elementNumber.implicitHeight)
        width: height

        StyledText {
            id: elementNumber
            anchors.left: parent.left
            color: Appearance.colors.colOnLayer2
            text: root.element.number
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    Rectangle {
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 4
            rightMargin: 4
        }
        color: ColorUtils.transparentize(Appearance.colors.colLayer2)
        radius: Appearance.rounding.full
        implicitWidth: Math.max(20, elementWeight.implicitWidth)
        implicitHeight: Math.max(20, elementWeight.implicitHeight)
        width: height

        StyledText {
            id: elementWeight
            anchors.right: parent.right
            color: Appearance.colors.colOnLayer2
            text: root.element.weight
            font.pixelSize: Appearance.font.pixelSize.smallest
        }
    }

    StyledText {
        id: elementSymbol
        anchors.centerIn: parent
        color: root.category
        font.pixelSize: Appearance.font.pixelSize.huge
        text: root.element.symbol
    }

    StyledText {
        id: elementName
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 4
        }
        width: parent.width - 8
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colOnLayer2
        text: root.element.name
    }
}
