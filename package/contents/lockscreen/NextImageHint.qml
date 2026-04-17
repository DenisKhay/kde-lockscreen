import QtQuick 2.15

Rectangle {
    id: root
    signal clicked()
    width: 36; height: 36; radius: 18
    color: "#80000000"
    border.color: "white"; border.width: 1
    opacity: hover.containsMouse ? 1.0 : 0.5
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Text {
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: "white"
        font.pixelSize: 18
        font.bold: true
        text: "×"
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
