import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// The condition icon doubles as the card's refresh button: clicking it re-runs the
// fetch. It gets its own file rather than an inline `component`, because inline
// components do not resolve inside these widget roots ("WeatherIcon is not a type").
MaterialShapeWrappedMaterialSymbol {
    id: root

    signal refreshRequested()

    shape: MaterialShape.Shape.Cookie12Sided
    color: Appearance.colors.colPrimary
    colSymbol: Appearance.colors.colOnPrimary
    fill: 1

    // Pointer cursor plus a press dip: the card has no room for a labelled refresh
    // control, so this is the whole affordance.
    scale: area.pressed ? 0.9 : 1
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.refreshRequested()
    }
}
