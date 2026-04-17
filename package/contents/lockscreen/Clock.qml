import QtQuick 2.15

Item {
    id: root
    property bool compact: false
    property alias dateOpacity: dateText.opacity
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
        font.family: "Noto Sans"
        font.pixelSize: 96
        font.weight: Font.Thin
        font.letterSpacing: -2
        text: Qt.formatTime(root._now, "HH:mm")
        transformOrigin: Item.Center
    }

    Text {
        id: dateText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: timeText.bottom
        anchors.topMargin: 4
        color: "white"
        font.family: "Noto Sans"
        font.pixelSize: 18
        font.weight: Font.Normal
        text: Qt.formatDate(root._now, "dddd, d MMMM yyyy")
    }
}
