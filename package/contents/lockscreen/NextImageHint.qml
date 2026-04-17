import QtQuick 2.15

Row {
    id: root
    signal clicked()
    spacing: 6
    opacity: hover.containsMouse ? 1.0 : 0.55
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Rectangle {
        width: 22; height: 22; radius: 3
        border.color: "white"; border.width: 1
        color: "transparent"
        Text {
            anchors.centerIn: parent
            color: "white"
            text: "N"
            font.pixelSize: 12
            font.family: "sans-serif"
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        color: "white"
        font.pixelSize: 13
        font.family: "sans-serif"
        text: "Next"
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
