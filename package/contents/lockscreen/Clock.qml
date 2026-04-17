import QtQuick 2.15

Item {
    id: root
    property bool compact: false
    property alias dateOpacity: dateText.opacity
    // Time text opacity while idle (compact). 1.0 when active.
    property real idleTimeOpacity: 0.55
    property var _now: new Date()

    // Fixed natural height for smoother animations
    implicitWidth: timeText.implicitWidth
    implicitHeight: timeText.implicitHeight + dateText.implicitHeight + 8

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._now = new Date()
    }

    Text {
        id: timeText
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        color: "white"
        font.family: "DejaVu Sans"
        font.pixelSize: 104
        font.weight: Font.Light
        font.letterSpacing: 1
        text: Qt.formatTime(root._now, "HH:mm")
        transformOrigin: Item.Center
        opacity: root.compact ? root.idleTimeOpacity : 1.0
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    }

    Text {
        id: dateText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: timeText.bottom
        anchors.topMargin: 6
        color: "white"
        font.family: "DejaVu Sans"
        font.pixelSize: 20
        font.weight: Font.Medium
        font.letterSpacing: 0.5
        text: Qt.formatDate(root._now, "dddd, d MMMM yyyy")
    }
}
