import QtQuick 2.15

Rectangle {
    id: root
    signal clicked()
    width: 36; height: 36; radius: 18
    color: "#80000000"
    border.color: "#aaffffff"; border.width: 1
    opacity: hover.containsMouse ? 1.0 : 0.55
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Image {
        anchors.centerIn: parent
        width: 18; height: 18
        source: Qt.resolvedUrl("icons/skip.svg")
        sourceSize: Qt.size(36, 36)
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
