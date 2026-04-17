import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ColumnLayout {
    id: root
    property alias cfg_pinLength: pinLengthSpin.value
    property alias cfg_autoSubmit: autoSubmitCheck.checked
    property alias cfg_idleSubmitMs: idleSubmitSpin.value
    property alias cfg_dotSizeMm: dotSizeSpin.value
    property alias cfg_blurRadius: blurSpin.value
    property alias cfg_dimAlpha: dimSpin.value
    property alias cfg_fitMode: fitCombo.currentText
    property alias cfg_bing: bingCheck.checked
    property alias cfg_wikimedia: wikiCheck.checked
    property alias cfg_nasa: nasaCheck.checked
    property alias cfg_usePicsumInstead: picsumCheck.checked
    property alias cfg_unsplashApiKey: keyField.text
    property alias cfg_saveDir: saveDirField.text

    GroupBox {
        title: "PIN"
        Layout.fillWidth: true
        ColumnLayout {
            RowLayout {
                Label { text: "PIN length" }
                SpinBox { id: pinLengthSpin; from: 4; to: 8; editable: true }
            }
            CheckBox { id: autoSubmitCheck; text: "Auto-submit at configured length" }
            RowLayout {
                Label { text: "Idle auto-submit (ms)" }
                SpinBox { id: idleSubmitSpin; from: 3000; to: 60000; stepSize: 1000; editable: true }
            }
        }
    }

    GroupBox {
        title: "Appearance"
        Layout.fillWidth: true
        GridLayout {
            columns: 2
            Label { text: "Dot size (mm)" }
            SpinBox { id: dotSizeSpin; from: 2; to: 8; stepSize: 1 }
            Label { text: "Blur radius" }
            SpinBox { id: blurSpin; from: 0; to: 50 }
            Label { text: "Dim alpha" }
            SpinBox { id: dimSpin; from: 0; to: 100; stepSize: 5 }
            Label { text: "Image fit" }
            ComboBox { id: fitCombo; model: ["cover", "contain", "smart"] }
        }
    }

    GroupBox {
        title: "Image sources"
        Layout.fillWidth: true
        ColumnLayout {
            CheckBox { id: bingCheck; text: "Bing Image of the Day" }
            CheckBox { id: wikiCheck; text: "Wikimedia Picture of the Day" }
            CheckBox { id: nasaCheck; text: "NASA APOD" }
            CheckBox { id: picsumCheck; text: "Use Picsum (no API key needed)" }
            Label { text: "Unsplash API key (optional)" }
            TextField { id: keyField; Layout.fillWidth: true }
        }
    }

    GroupBox {
        title: "Save destination"
        Layout.fillWidth: true
        TextField { id: saveDirField; Layout.fillWidth: true }
    }
}
