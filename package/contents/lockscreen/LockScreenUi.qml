import QtQuick 2.15
import QtQuick.Window 2.15

Item {
    id: root
    anchors.fill: parent
    focus: true

    // `authenticator` is a CONTEXT PROPERTY injected by kscreenlocker_greet.
    // Do NOT declare `property var authenticator: ...` here — a same-named
    // property shadows the context property and is initialised to `undefined`
    // before its own expression evaluates, which means tryUnlock would never
    // fire. Access the context property directly below, guarded by typeof for
    // --testing mode (where it is not injected).

    // Config (populated from KConfig in Plasma; defaults here for --testing).
    property int pinLength: 8
    property real dotSizeMm: 4.0
    property real blurRadius: 0        // disabled by default
    property real dimAlpha: 0.0        // disabled by default
    property string fitMode: "cover"
    property bool autoSubmit: true
    property string username: Qt.application.organizationName || "denisk"

    // Current image path for the primary screen. Multi-monitor split is a v2
    // feature; v1 shows the same image on every monitor which at minimum
    // guarantees the window is always fully covered.
    property string currentImage: ""

    // Any user input (mouse move, click, key, image gesture) flips this true
    // and keeps the PIN UI visible even before the first keystroke. The
    // idle timer (below) flips it back after inactivity.
    property bool userInteracted: false
    property int inactivityTimeoutMs: 15000

    // Called from every interaction handler — sets the flag and restarts the
    // idle countdown from zero.
    function markInteraction() {
        userInteracted = true
        idleTimer.restart()
    }

    Timer {
        id: idleTimer
        interval: root.inactivityTimeoutMs
        repeat: false
        onTriggered: {
            // Only fade back to idle if there's nothing typed. While a PIN is
            // in the field, keep the UI visible so the user can see what they
            // typed. (A separate security sweep could clear text here too.)
            if (pin.text.length === 0) root.userInteracted = false
        }
    }

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

    // Input handlers: fire on mouse movement / click anywhere on the screen
    // without stealing events from child MouseAreas (SaveImageHint etc).
    HoverHandler {
        id: hoverTracker
        onPointChanged: root.markInteraction()
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onTapped: root.markInteraction()
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
                root.markInteraction()
                var r = registry.saveImage(root.currentImage)
                if (r === "saved") { saveHint.showToast("Saved to Pictures"); saveHint.saved = true }
                else if (r === "exists") saveHint.showToast("Already saved")
                else saveHint.showToast("Save failed")
            }
        }

        NextImageHint {
            onClicked: {
                root.markInteraction()
                root.currentImage = registry.next()
                saveHint.saved = false
            }
        }
    }

    // --testing-only: briefly flash "UNLOCKED" to prove submit reached here.
    Text {
        id: testOkLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 40
        color: "#9effa0"
        font.pixelSize: 24
        font.family: "DejaVu Sans"
        font.weight: Font.Bold
        text: "UNLOCKED (test mode)"
        opacity: 0
        SequentialAnimation on opacity {
            id: testOkFlash
            running: false
            NumberAnimation { from: 0; to: 1; duration: 150 }
            PauseAnimation { duration: 1200 }
            NumberAnimation { from: 1; to: 0; duration: 400 }
        }
    }

    CenterStack {
        id: center
        anchors.centerIn: parent
        pinLength: root.pinLength
        pinFilled: pin.text.length
        dotSizeMm: root.dotSizeMm
        username: root.username
        active: pin.text.length > 0 || root.userInteracted
    }

    PinInput {
        id: pin
        pinLength: root.pinLength
        autoSubmit: root.autoSubmit
        onSubmitted: function (pw) {
            // Plasma's PAM authenticator API: tryUnlock() kicks off the
            // session (called once at startup), respond(pw) sends the
            // password when PAM has prompted for it. We were calling
            // tryUnlock(pw) which IGNORED the argument — that's why every
            // unlock was silent.
            console.warn("[LockScreenUi] submit -> respond len=" + pw.length)
            if (typeof authenticator !== "undefined" && authenticator !== null) {
                authenticator.respond(pw)
            } else if (pw === "1234") {
                testOkFlash.running = true
            } else {
                root.rootWrongPin()
            }
        }
    }

    function rootWrongPin() {
        console.warn("[LockScreenUi] rootWrongPin -> center.shake()")
        center.shake()
    }

    // Plasma's PamAuthenticator signals: prompt/promptForSecret/succeeded/
    // failed/infoMessage/errorMessage. We don't track prompt text explicitly —
    // the user is always typing a password in our lockscreen.
    Connections {
        target: typeof authenticator !== "undefined" ? authenticator : null
        ignoreUnknownSignals: true
        function onFailed() {
            console.warn("[LockScreenUi] authenticator.failed")
            pin.clear()
            root.rootWrongPin()
        }
        function onSucceeded() {
            console.warn("[LockScreenUi] authenticator.succeeded — unlocking")
            Qt.quit()
        }
        function onPrompt(msg) {
            console.warn("[LockScreenUi] authenticator.prompt: " + msg)
        }
        function onPromptForSecret(msg) {
            console.warn("[LockScreenUi] authenticator.promptForSecret: " + msg)
        }
        function onInfoMessage(msg) { console.warn("[LockScreenUi] info: " + msg) }
        function onErrorMessage(msg) { console.warn("[LockScreenUi] error: " + msg) }
    }

    // Kick off the PAM session once at startup so it sends us a `prompt`.
    // Without this call, respond() has no open dialogue with PAM.
    Component.onCompleted: {
        forceActiveFocus()
        if (typeof authenticator !== "undefined" && authenticator !== null) {
            console.warn("[LockScreenUi] calling authenticator.tryUnlock() (kick-off)")
            authenticator.tryUnlock()
        }
    }

    // Key routing — load-bearing trick for typing-without-focus
    Keys.onPressed: function (event) {
        console.warn("[LockScreenUi] key=" + event.key + " text='" + event.text + "'")
        root.markInteraction()
        if (event.key === Qt.Key_Backspace) {
            pin.backspace(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            pin.submit(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Escape) {
            pin.clear(); event.accepted = true; return
        }
        // Image gestures are arrow-keys ONLY — never letter keys, so that
        // passwords containing 'n' or 's' are typed normally, never stolen.
        if (event.key === Qt.Key_Right) {
            root.currentImage = registry.next()
            saveHint.saved = false
            event.accepted = true; return
        }
        if (event.key === Qt.Key_Left) {
            var prev = registry.previous()
            if (prev !== "") {
                root.currentImage = prev
                saveHint.saved = false
            }
            event.accepted = true; return
        }
        if (event.key === Qt.Key_Down) {
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

}
