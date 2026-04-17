import QtQuick 2.15

Item {
    id: root
    signal clicked()
    property bool saved: false
    width: 36; height: 36

    Rectangle {
        id: btn
        anchors.fill: parent
        radius: 18
        color: "#80000000"
        border.color: "white"; border.width: 1
        opacity: hover.containsMouse ? 1.0 : 0.5
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            color: root.saved ? "#ff6070" : "white"
            font.pixelSize: 18
            text: root.saved ? "\u2665" : "\u2193"  // ♥ filled when saved, ↓ otherwise
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }

    // Toast
    Rectangle {
        id: toast
        anchors.right: parent.right
        anchors.bottom: parent.top
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

        NumberAnimation on opacity {
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
