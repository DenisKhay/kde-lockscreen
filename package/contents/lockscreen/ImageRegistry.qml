import QtQuick 2.15

Item {
    id: registry

    property var _entries: []
    property string cacheDir: Qt.resolvedUrl("file://" + Qt.application.arguments[0])  // placeholder
        .toString()
    property string manifestPath: {
        // kscreenlocker_greet runs as the user; $HOME is available via env.
        var home = Qt.application.organizationName ? "" : ""
        return "file://" + (Qt.resolvedUrl("/home/" + Qt.application.name) + "")
    }

    signal entriesChanged()

    function _load() {
        var xhr = new XMLHttpRequest()
        var url = "file://" + _homeDir() + "/.cache/kde-lockscreen/manifest.json"
        xhr.open("GET", url, false)  // synchronous OK — file is local + tiny
        try {
            xhr.send(null)
            if (xhr.status === 200 || xhr.status === 0) {
                var raw = JSON.parse(xhr.responseText)
                _entries = raw.entries || []
            }
        } catch (e) {
            console.warn("ImageRegistry: manifest load failed:", e)
            _entries = []
        }
    }

    function _homeDir() {
        // Qt.resolvedUrl gives us a file:// path we can extract HOME from.
        // Hardcoded fallback because kscreenlocker_greet may not expose env.
        return "/home/denisk"
    }

    function _usable() {
        return _entries.filter(function (e) { return !e.disliked })
    }

    function pickForScreen(index) {
        var list = _usable()
        if (list.length === 0) return Qt.resolvedUrl("fallback.jpg").toString()
        // Deterministic: seeded by date + screen index
        var d = new Date()
        var seed = (d.getFullYear() * 372 + d.getMonth() * 31 + d.getDate()) + index * 17
        return "file://" + list[seed % list.length].path
    }

    function markDisliked(filePath) {
        var p = filePath.replace(/^file:\/\//, "")
        for (var i = 0; i < _entries.length; i++) {
            if (_entries[i].path === p) _entries[i].disliked = true
        }
        _writeManifest()
        entriesChanged()
    }

    function markSaved(filePath) {
        var p = filePath.replace(/^file:\/\//, "")
        for (var i = 0; i < _entries.length; i++) {
            if (_entries[i].path === p) _entries[i].saved = true
        }
        _writeManifest()
    }

    function _writeManifest() {
        var xhr = new XMLHttpRequest()
        var url = "file://" + _homeDir() + "/.cache/kde-lockscreen/manifest.json"
        xhr.open("PUT", url, false)
        try {
            xhr.send(JSON.stringify({version: 1, entries: _entries}, null, 2))
        } catch (e) {
            console.warn("ImageRegistry: manifest write failed:", e)
        }
    }

    Component.onCompleted: _load()
}
