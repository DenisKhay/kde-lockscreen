import QtQuick 2.15
import QtQuick.Window 2.15

Row {
    id: root
    property int pinLength: 6
    property int filled: 0
    property real dotSizeMm: 4.0
    spacing: _dotSize * 0.6

    readonly property real _dotSize: dotSizeMm * Screen.pixelDensity

    Repeater {
        model: root.pinLength
        delegate: Rectangle {
            width: root._dotSize
            height: root._dotSize
            radius: width / 2
            color: index < root.filled ? "white" : "transparent"
            border.color: "white"
            border.width: 2
            opacity: index < root.filled ? 1.0 : 0.5
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }
}
