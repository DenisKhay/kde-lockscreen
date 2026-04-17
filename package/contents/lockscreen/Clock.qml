import QtQuick 2.15

Column {
    id: root
    spacing: 8
    property bool compact: false   // compact=true → big time, date hidden
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
        transformOrigin: Item.Center
        scale: root.compact ? 1.75 : 1.0
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
    }

    Text {
        id: dateLabel
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        font.pixelSize: 22
        text: Qt.formatDate(root._now, "dddd, d MMMM yyyy")
        opacity: root.compact ? 0.0 : 0.8
        height: root.compact ? 0 : implicitHeight
        clip: true
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }
}
