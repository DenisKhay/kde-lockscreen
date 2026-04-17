import QtQuick 2.15

Item {
    id: root
    property int pinLength: 6
    property bool autoSubmit: true
    property int idleSubmitMs: 10000
    property alias text: input.text

    signal submitted(string pin)
    signal wrongPin()

    // Last text we've already emitted submitted() for. Prevents re-firing the
    // same string twice.
    property string _lastAttempted: ""

    function clear() {
        input.text = ""
        _lastAttempted = ""
        idleTimer.stop()
    }
    function appendChar(ch) {
        if (input.text.length < pinLength + 20) input.text += ch
    }
    function backspace() {
        input.text = input.text.slice(0, -1)
    }
    function submit() {
        // Manual submit via Enter key.
        if (input.text.length === 0) return
        if (input.text === _lastAttempted) return
        _tryText(input.text)
    }
    function _tryText(t) {
        _lastAttempted = t
        idleTimer.stop()
        root.submitted(t)
    }

    TextInput {
        id: input
        visible: false
        echoMode: TextInput.Password
        onTextChanged: {
            // Length-trigger: fire once per unique text at the configured length.
            if (root.autoSubmit
                    && text.length === root.pinLength
                    && text !== root._lastAttempted) {
                root._tryText(text)
                return
            }
            // Any change to untried non-empty text arms the idle timer.
            if (text.length > 0 && text !== root._lastAttempted) {
                idleTimer.restart()
            } else {
                idleTimer.stop()
            }
        }
    }

    // Idle-submit: fires idleSubmitMs after the last keystroke if text is
    // non-empty and hasn't been tried yet.
    Timer {
        id: idleTimer
        interval: root.idleSubmitMs
        repeat: false
        onTriggered: {
            if (input.text.length > 0 && input.text !== root._lastAttempted) {
                root._tryText(input.text)
            }
        }
    }
}
