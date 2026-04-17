import QtQuick 2.15

Item {
    id: root
    property int pinLength: 6
    property bool autoSubmit: true
    property alias text: input.text

    signal submitted(string pin)
    signal wrongPin()

    function clear() { input.text = "" }
    function appendChar(ch) {
        if (input.text.length < pinLength + 20) input.text += ch
    }
    function backspace() { input.text = input.text.slice(0, -1) }
    function submit() {
        if (input.text.length === 0) return
        root.submitted(input.text)
    }

    TextInput {
        id: input
        visible: false
        echoMode: TextInput.Password
        onTextChanged: {
            if (root.autoSubmit && text.length === root.pinLength) {
                root.submitted(text)
            }
        }
    }
}
