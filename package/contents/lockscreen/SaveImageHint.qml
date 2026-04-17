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
        border.color: "#aaffffff"; border.width: 1
        opacity: hover.containsMouse ? 1.0 : 0.55
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Image {
            anchors.centerIn: parent
            width: 18; height: 18
            source: root.saved
                ? Qt.resolvedUrl("icons/heart-filled.svg")
                : Qt.resolvedUrl("icons/heart-outline.svg")
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
