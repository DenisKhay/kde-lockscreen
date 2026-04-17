import QtQuick 2.15

Column {
    id: root
    spacing: 40
    property int pinLength: 6
    property int pinFilled: 0
    property real dotSizeMm: 4.0
    property string username: "user"
    property bool active: false   // becomes true on first keystroke

    signal shake()

    Clock {
        anchors.horizontalCenter: parent.horizontalCenter
        compact: !root.active
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        font.pixelSize: 24
        text: root.username
        opacity: root.active ? 1.0 : 0.0
        height: root.active ? implicitHeight : 0
        clip: true
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }

    PinDots {
        id: dots
        anchors.horizontalCenter: parent.horizontalCenter
        pinLength: root.pinLength
        filled: root.pinFilled
        dotSizeMm: root.dotSizeMm
        opacity: root.active ? 1.0 : 0.0
        height: root.active ? _dotSize : 0
        clip: true
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "x"; to: root.x - 20; duration: 50 }
        NumberAnimation { target: root; property: "x"; to: root.x + 20; duration: 50 }
        NumberAnimation { target: root; property: "x"; to: root.x - 12; duration: 50 }
        NumberAnimation { target: root; property: "x"; to: root.x; duration: 50 }
    }

    onShake: shakeAnim.start()
}
