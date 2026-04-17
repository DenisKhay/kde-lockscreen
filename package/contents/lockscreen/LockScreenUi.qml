import QtQuick 2.15
import QtQuick.Window 2.15

Item {
    id: root
    anchors.fill: parent
    focus: true

    // From Plasma's lockscreen injection. At --testing time, authenticator may be null.
    property var authenticator: typeof authenticator !== "undefined" ? authenticator : null

    // Config (populated from KConfig in Plasma; defaults here for --testing).
    property int pinLength: 6
    property real dotSizeMm: 4.0
    property real blurRadius: 0        // disabled by default
    property real dimAlpha: 0.0        // disabled by default
    property string fitMode: "cover"
    property bool autoSubmit: true
    property int idleSubmitMs: 10000
    property string username: Qt.application.organizationName || "denisk"

    // Current image path for the primary screen. Multi-monitor split is a v2
    // feature; v1 shows the same image on every monitor which at minimum
    // guarantees the window is always fully covered.
    property string currentImage: ""

    ImageRegistry {
        id: registry
        Component.onCompleted: root.currentImage = pickForScreen(0)
    }

    BackgroundLayer {
        anchors.fill: parent
        source: root.currentImage
        blurRadius: root.blurRadius
        dimAlpha: root.dimAlpha
        fitMode: root.fitMode
    }

    // Save/skip icons, bottom-right of the screen
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 8

        SaveImageHint {
            id: saveHint
            saved: false
            onClicked: {
                var r = registry.saveImage(root.currentImage)
                if (r === "saved") { saveHint.showToast("Saved to Pictures"); saveHint.saved = true }
                else if (r === "exists") saveHint.showToast("Already saved")
                else saveHint.showToast("Save failed")
            }
        }

        NextImageHint {
            onClicked: {
                registry.markDisliked(root.currentImage)
                registry.advance()
                root.currentImage = registry.pickForScreen(0)
                saveHint.saved = false
            }
        }
    }

    CenterStack {
        id: center
        anchors.centerIn: parent
        pinLength: root.pinLength
        pinFilled: pin.text.length
        dotSizeMm: root.dotSizeMm
        username: root.username
        active: pin.text.length > 0
    }

    PinInput {
        id: pin
        pinLength: root.pinLength
        autoSubmit: root.autoSubmit
        idleSubmitMs: root.idleSubmitMs
        onSubmitted: {
            if (root.authenticator) {
                root.authenticator.tryUnlock(pin.text)
            } else {
                // Testing mode: simulate wrong PIN on non-"1234" input
                if (pin.text !== "1234") rootWrongPin()
            }
        }
    }

    function rootWrongPin() {
        // Shake but do NOT clear the text — user may want to append more
        // characters if their configured pinLength is shorter than the real PW.
        // Escape still clears manually; the idle-submit timer will retry
        // whatever is in the field after idleSubmitMs of no input.
        center.shake()
    }

    // Wire authenticator signals if available
    Connections {
        target: root.authenticator
        ignoreUnknownSignals: true
        function onFailed() { root.rootWrongPin() }
    }

    // Key routing — load-bearing trick for typing-without-focus
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Backspace) {
            pin.backspace(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            pin.submit(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Escape) {
            pin.clear(); event.accepted = true; return
        }
        // Next image: Right arrow or 'N'
        if (event.key === Qt.Key_Right || event.key === Qt.Key_N) {
            registry.markDisliked(root.currentImage)
            registry.advance()
            root.currentImage = registry.pickForScreen(0)
            saveHint.saved = false
            event.accepted = true; return
        }
        // Save image: Down arrow or 'S'
        if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
            var r = registry.saveImage(root.currentImage)
            if (r === "saved") { saveHint.showToast("Saved to Pictures"); saveHint.saved = true }
            else if (r === "exists") saveHint.showToast("Already saved")
            else saveHint.showToast("Save failed")
            event.accepted = true; return
        }
        // Printable: append to PIN
        if (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32) {
            pin.appendChar(event.text)
            event.accepted = true
        }
    }

    Component.onCompleted: forceActiveFocus()
}
