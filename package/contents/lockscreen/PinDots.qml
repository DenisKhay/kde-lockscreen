import QtQuick 2.15
import QtQuick.Window 2.15

Row {
    id: root
    property int pinLength: 6
    property int filled: 0
    property real dotSizeMm: 4.0
    spacing: _dotSize * 0.6

    readonly property real _dotSize: dotSizeMm * Screen.pixelDensity
    // Grow the dot row past pinLength so the user sees feedback when typing a
    // password longer than their configured PIN length.
    readonly property int _visible: Math.max(pinLength, filled)

    Repeater {
        model: root._visible
        delegate: Rectangle {
            width: root._dotSize
            height: root._dotSize
            radius: width / 2
            // Within pinLength: white when filled. Past pinLength: pink tint
            // so user sees they've gone past the auto-submit threshold.
            color: index < root.filled
                ? (index >= root.pinLength ? "#ffb0b0" : "white")
                : "transparent"
            border.color: "white"
            border.width: 2
            opacity: index < root.filled ? 1.0 : 0.5
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }
}
