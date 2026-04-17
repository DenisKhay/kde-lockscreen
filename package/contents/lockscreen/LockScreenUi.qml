import QtQuick 2.15
import QtQuick.Window 2.15

Item {
    id: root
    anchors.fill: parent

    ImageRegistry { id: registry }

    Repeater {
        model: Qt.application.screens.length || 1
        delegate: BackgroundLayer {
            x: Qt.application.screens[index] ? Qt.application.screens[index].virtualX : 0
            y: Qt.application.screens[index] ? Qt.application.screens[index].virtualY : 0
            width: Qt.application.screens[index] ? Qt.application.screens[index].width : root.width
            height: Qt.application.screens[index] ? Qt.application.screens[index].height : root.height
            source: registry.pickForScreen(index)
            blurRadius: 24
            dimAlpha: 0.35
        }
    }

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 48
        text: "Denis Lockscreen — multi-monitor"
    }
}
