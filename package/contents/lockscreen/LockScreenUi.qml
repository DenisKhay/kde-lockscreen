import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    BackgroundLayer {
        anchors.fill: parent
        source: "file://" + Qt.resolvedUrl("fallback.jpg").toString().replace("file://", "")
        blurRadius: 24
        dimAlpha: 0.35
    }

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 48
        text: "Denis Lockscreen — bg"
    }
}
