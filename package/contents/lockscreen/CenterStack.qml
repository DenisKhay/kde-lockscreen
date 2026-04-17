import QtQuick 2.15

// Absolute-positioned stack: clock, username, dots.
// States drive one coordinated animation (no Column reflow jumping).
Item {
    id: root
    property int pinLength: 6
    property int pinFilled: 0
    property real dotSizeMm: 4.0
    property string username: "user"
    property bool active: false

    signal shake()

    width: 600
    height: 360

    Clock {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        transformOrigin: Item.Top
    }

    Text {
        id: usernameLabel
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        font.family: "Noto Sans"
        font.pixelSize: 18
        text: root.username
    }

    PinDots {
        id: dotsRow
        anchors.horizontalCenter: parent.horizontalCenter
        pinLength: root.pinLength
        filled: root.pinFilled
        dotSizeMm: root.dotSizeMm
    }

    // Two states: idle (only big clock, centered) vs active (shrunk clock at
    // top, date visible as part of Clock, username + dots fading in below).
    state: root.active ? "active" : "idle"
    states: [
        State {
            name: "idle"
            PropertyChanges { target: clock; y: (root.height - clock.implicitHeight) / 2 - 40; scale: 1.5; dateOpacity: 0 }
            PropertyChanges { target: usernameLabel; y: root.height / 2 + 100; opacity: 0 }
            PropertyChanges { target: dotsRow; y: root.height / 2 + 140; opacity: 0 }
        },
        State {
            name: "active"
            PropertyChanges { target: clock; y: 40; scale: 1.0; dateOpacity: 1.0 }
            PropertyChanges { target: usernameLabel; y: 40 + clock.implicitHeight + 40; opacity: 0.9 }
            PropertyChanges { target: dotsRow; y: 40 + clock.implicitHeight + 40 + usernameLabel.implicitHeight + 24; opacity: 1.0 }
        }
    ]
    transitions: [
        Transition {
            NumberAnimation {
                properties: "y,scale,opacity,dateOpacity"
                duration: 450
                easing.type: Easing.OutCubic
            }
        }
    ]

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "x"; to: root.x - 20; duration: 50 }
        NumberAnimation { target: root; property: "x"; to: root.x + 20; duration: 50 }
        NumberAnimation { target: root; property: "x"; to: root.x - 12; duration: 50 }
        NumberAnimation { target: root; property: "x"; to: root.x; duration: 50 }
    }
    onShake: shakeAnim.start()
}
