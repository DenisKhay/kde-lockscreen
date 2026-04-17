import QtQuick 2.15

Column {
    id: root
    spacing: 8
    property var _now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._now = new Date()
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        font.pixelSize: 80
        font.weight: Font.Light
        text: Qt.formatTime(root._now, "HH:mm")
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        opacity: 0.8
        font.pixelSize: 22
        text: Qt.formatDate(root._now, "dddd, d MMMM yyyy")
    }
}
