import QtQuick 2.15

Item {
    id: root
    signal clicked()
    implicitWidth: hintRow.implicitWidth
    implicitHeight: hintRow.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // Translucent dark pill for readability on any photo
    Rectangle {
        anchors.fill: hintRow
        anchors.margins: -8
        anchors.leftMargin: -10
        anchors.rightMargin: -10
        color: "#60000000"
        radius: 14
        opacity: hintRow.opacity
    }

    Row {
        id: hintRow
        spacing: 6
        opacity: hover.containsMouse ? 1.0 : 0.9
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Rectangle {
            width: 22; height: 22; radius: 3
            border.color: "white"; border.width: 1
            color: "transparent"
            Text {
                anchors.centerIn: parent
                color: "white"
                text: "→"
                font.pixelSize: 13
                font.family: "DejaVu Sans"
                font.weight: Font.Medium
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: 13
            font.family: "DejaVu Sans"
            font.weight: Font.Medium
            text: "Next"
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
