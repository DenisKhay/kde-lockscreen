import QtQuick 2.15

Item {
    id: root
    property int pinLength: 6
    property bool autoSubmit: true
    property alias text: input.text

    // Parameter is named `pw` (not `pin`) because the lockscreen uses `id: pin`
    // on the containing PinInput — a signal parameter named `pin` would shadow
    // that id in the handler, making `pin.text` undefined. Real bug we hit.
    signal submitted(string pw)
    signal wrongPin()

    // Last text we've already emitted submitted() for. Prevents re-firing the
    // same string twice when auto-submit at pinLength has just failed.
    property string _lastAttempted: ""

    function clear() {
        input.text = ""
        _lastAttempted = ""
    }
    function appendChar(ch) {
        if (input.text.length < pinLength + 20) input.text += ch
    }
    function backspace() {
        input.text = input.text.slice(0, -1)
    }
    function submit() {
        console.warn("[PinInput] submit() called len=" + input.text.length + " lastAttempted=" + _lastAttempted)
        if (input.text.length === 0) { console.warn("[PinInput]   early-return: empty"); return }
        if (input.text === _lastAttempted) { console.warn("[PinInput]   early-return: same as lastAttempted"); return }
        _tryText(input.text)
    }
    function _tryText(t) {
        console.warn("[PinInput] _tryText -> emit submitted, len=" + t.length)
        _lastAttempted = t
        root.submitted(t)
    }

    TextInput {
        id: input
        visible: false
        echoMode: TextInput.Password
        onTextChanged: {
            // Length-trigger: fire exactly once per unique text when it hits
            // the configured PIN length. After a failure, the text is NOT
            // cleared — the user can append more chars or press Enter.
            if (root.autoSubmit
                    && text.length === root.pinLength
                    && text !== root._lastAttempted) {
                root._tryText(text)
            }
        }
    }
}
