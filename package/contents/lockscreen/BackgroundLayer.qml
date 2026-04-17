import QtQuick 2.15
import QtGraphicalEffects 1.15

Item {
    id: root
    property string source: ""
    property real blurRadius: 32
    property real dimAlpha: 0.4
    property string fitMode: "smart"  // cover | contain | smart

    Image {
        id: baseImage
        anchors.fill: parent
        source: root.source
        asynchronous: true
        cache: true
        fillMode: {
            if (root.fitMode === "cover") return Image.PreserveAspectCrop
            if (root.fitMode === "contain") return Image.PreserveAspectFit
            if (!baseImage.sourceSize.width) return Image.PreserveAspectCrop
            var imgAspect = baseImage.sourceSize.width / baseImage.sourceSize.height
            var screenAspect = parent.width / parent.height
            return (imgAspect < 1 || Math.abs(imgAspect - screenAspect) > 0.5)
                ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        }
    }

    FastBlur {
        anchors.fill: baseImage
        source: baseImage
        radius: root.blurRadius
        visible: root.blurRadius > 0
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.dimAlpha
    }
}
