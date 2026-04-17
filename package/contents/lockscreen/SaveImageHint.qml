import QtQuick 2.15

Item {
    id: root
    signal clicked()
    property bool saved: false
    implicitWidth: hintRow.implicitWidth
    implicitHeight: hintRow.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Row {
        id: hintRow
        spacing: 6
        opacity: hover.containsMouse ? 1.0 : 0.55
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Rectangle {
            id: btn
            width: 22; height: 22; radius: 3
            border.color: "white"; border.width: 1
            color: "transparent"
            transformOrigin: Item.Center
            Text {
                anchors.centerIn: parent
                color: "white"
                text: "↓"
                font.pixelSize: 13
                font.family: "DejaVu Sans"
            }
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.pixelSize: 13
            font.family: "DejaVu Sans"
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

    // Toast: floats above the hint. Sized and colored to actually catch the
    // eye — earlier version was too subtle to notice.
    Rectangle {
        id: toast
        anchors.right: root.right
        anchors.bottom: root.top
        anchors.bottomMargin: 10
        color: "#f2000000"
        border.color: "#55ffffff"
        border.width: 1
        radius: 8
        visible: opacity > 0
        opacity: 0
        width: toastText.implicitWidth + 32
        height: toastText.implicitHeight + 18

        Text {
            id: toastText
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 15
            font.family: "DejaVu Sans"
            font.weight: Font.Medium
            text: ""
        }

        SequentialAnimation on opacity {
            id: toastAnim
            running: false
            NumberAnimation { from: 0.0; to: 1.0; duration: 180 }
            PauseAnimation { duration: 1800 }
            NumberAnimation { from: 1.0; to: 0.0; duration: 400; easing.type: Easing.InQuad }
        }
    }

    // Small "press pulse" on the button itself — instant feedback the click
    // registered, even if the toast hasn't shown yet.
    SequentialAnimation {
        id: pulseAnim
        running: false
        NumberAnimation { target: btn; property: "scale"; from: 1.0; to: 1.15; duration: 80 }
        NumberAnimation { target: btn; property: "scale"; from: 1.15; to: 1.0; duration: 140; easing.type: Easing.OutBack }
    }

    function showToast(msg) {
        toastText.text = msg
        toastAnim.restart()
        pulseAnim.restart()
    }
}
