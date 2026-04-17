import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    ImageRegistry { id: registry }

    BackgroundLayer {
        anchors.fill: parent
        source: registry.pickForScreen(0)
        blurRadius: 24
        dimAlpha: 0.35
    }

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 48
        text: "Denis Lockscreen — registry"
    }
}
