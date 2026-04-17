import QtQuick 2.15

Column {
    id: root
    spacing: 40
    property int pinLength: 6
    property int pinFilled: 0
    property real dotSizeMm: 4.0
    property string username: "user"

    signal shake()

    Clock {
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        font.pixelSize: 24
        text: root.username
    }

    PinDots {
        id: dots
        anchors.horizontalCenter: parent.horizontalCenter
        pinLength: root.pinLength
        filled: root.pinFilled
        dotSizeMm: root.dotSizeMm
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
