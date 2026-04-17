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
    property real blurRadius: 32
    property real dimAlpha: 0.4
    property string fitMode: "smart"
    property bool autoSubmit: true
    property int idleSubmitMs: 10000
    property string username: Qt.application.organizationName || "denisk"

    ImageRegistry { id: registry }

    // Per-screen backgrounds + hints
    Repeater {
        model: Qt.application.screens.length || 1
        delegate: Item {
            x: Qt.application.screens[index] ? Qt.application.screens[index].virtualX : 0
            y: Qt.application.screens[index] ? Qt.application.screens[index].virtualY : 0
            width: Qt.application.screens[index] ? Qt.application.screens[index].width : root.width
            height: Qt.application.screens[index] ? Qt.application.screens[index].height : root.height

            property string currentImage: registry.pickForScreen(index)

            BackgroundLayer {
                id: bg
                anchors.fill: parent
                source: parent.currentImage
                blurRadius: root.blurRadius
                dimAlpha: root.dimAlpha
                fitMode: root.fitMode
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 24
                spacing: 8

                SaveImageHint {
                    id: saveHint
                    saved: registry._usable().some(function (e) {
                        return "file://" + e.path === parent.parent.currentImage && e.saved
                    })
                    onClicked: {
                        var r = registry.saveImage(parent.parent.currentImage)
                        if (r === "saved") saveHint.showToast("Saved to Pictures")
                        else if (r === "exists") saveHint.showToast("Already saved")
                        else saveHint.showToast("Save failed")
                    }
                }

                NextImageHint {
                    onClicked: {
                        registry.markDisliked(parent.parent.currentImage)
                        parent.parent.currentImage = registry.pickForScreen(index)
                    }
                }
            }
        }
    }

    // Center stack on primary screen
    CenterStack {
        id: center
        anchors.centerIn: parent
        pinLength: root.pinLength
        pinFilled: pin.text.length
        dotSizeMm: root.dotSizeMm
        username: root.username
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
            var firstScreen = _firstScreenItem()
            if (firstScreen) {
                registry.markDisliked(firstScreen.currentImage)
                firstScreen.currentImage = registry.pickForScreen(0)
            }
            event.accepted = true; return
        }
        // Save image: Down arrow or 'S'
        if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
            var firstScreenS = _firstScreenItem()
            if (firstScreenS) {
                var r = registry.saveImage(firstScreenS.currentImage)
                // Toast lives in the SaveImageHint on the primary screen
                var hint = _firstSaveHint()
                if (hint) {
                    if (r === "saved") hint.showToast("Saved to Pictures")
                    else if (r === "exists") hint.showToast("Already saved")
                    else hint.showToast("Save failed")
                }
            }
            event.accepted = true; return
        }
        // Printable: append to PIN
        if (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32) {
            pin.appendChar(event.text)
            event.accepted = true
        }
    }

    function _firstScreenItem() {
        for (var i = 0; i < root.children.length; i++) {
            var c = root.children[i]
            if (c.hasOwnProperty && c.hasOwnProperty("currentImage")) return c
        }
        return null
    }
    function _firstSaveHint() {
        var s = _firstScreenItem()
        if (!s) return null
        // The Row is a direct child; walk its children to find SaveImageHint
        for (var i = 0; i < s.children.length; i++) {
            var row = s.children[i]
            if (row.children) {
                for (var j = 0; j < row.children.length; j++) {
                    if (row.children[j].showToast) return row.children[j]
                }
            }
        }
        return null
    }

    Component.onCompleted: forceActiveFocus()
}
