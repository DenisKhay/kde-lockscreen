import QtQuick 2.15
import QtGraphicalEffects 1.15

Item {
    id: root
    property string source: ""
    property real blurRadius: 0
    property real dimAlpha: 0
    property string fitMode: "cover"  // cover | contain | smart

    // Opaque backdrop — prevents the desktop wallpaper from bleeding through
    // during image transitions.
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // Two Image slots that cross-fade on source change.
    Image {
        id: imgA
        anchors.fill: parent
        asynchronous: true
        cache: true
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
        fillMode: _fitForImage(imgA)
    }
    Image {
        id: imgB
        anchors.fill: parent
        asynchronous: true
        cache: true
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
        fillMode: _fitForImage(imgB)
    }

    property bool _useA: true

    function _fitForImage(img) {
        if (root.fitMode === "cover") return Image.PreserveAspectCrop
        if (root.fitMode === "contain") return Image.PreserveAspectFit
        if (!img.sourceSize.width) return Image.PreserveAspectCrop
        var imgAspect = img.sourceSize.width / img.sourceSize.height
        var screenAspect = root.width / root.height
        return (imgAspect < 1 || Math.abs(imgAspect - screenAspect) > 0.5)
            ? Image.PreserveAspectFit
            : Image.PreserveAspectCrop
    }

    onSourceChanged: {
        if (!source) return
        // Load the new image into the inactive slot, then cross-fade.
        if (_useA) {
            imgB.source = source
            imgB.opacity = 1
            imgA.opacity = 0
        } else {
            imgA.source = source
            imgA.opacity = 1
            imgB.opacity = 0
        }
        _useA = !_useA
    }

    Component.onCompleted: {
        if (source) {
            imgA.source = source
            imgA.opacity = 1
        }
    }

    FastBlur {
        anchors.fill: parent
        source: _useA ? imgB : imgA   // blur follows the currently-visible image
        radius: root.blurRadius
        visible: root.blurRadius > 0
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.dimAlpha
    }
}
