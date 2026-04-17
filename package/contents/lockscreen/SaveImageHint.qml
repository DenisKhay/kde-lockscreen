import QtQuick 2.15

Item {
    id: root
    signal clicked()
    property bool saved: false
    width: label.x + label.width
    height: 22

    Row {
        id: hintRow
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
                text: "S"
                font.pixelSize: 12
                font.family: "sans-serif"
            }
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: 13
            font.family: "sans-serif"
            text: root.saved ? "Saved ✓" : "Save"
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    // Toast: floats above the hint
    Rectangle {
        id: toast
        anchors.right: root.right
        anchors.bottom: root.top
        anchors.bottomMargin: 8
        color: "#cc000000"
        radius: 6
        visible: opacity > 0
        opacity: 0
        width: toastText.implicitWidth + 24
        height: toastText.implicitHeight + 12

        Text {
            id: toastText
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 13
            text: ""
        }

        NumberAnimation on toast.opacity {
            id: toastAnim
            duration: 2000
            from: 1.0; to: 0.0
            running: false
        }
    }

    function showToast(msg) {
        toastText.text = msg
        toast.opacity = 1.0
        toastAnim.restart()
    }
}
