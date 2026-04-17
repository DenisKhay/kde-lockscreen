import QtQuick 2.15

Item {
    id: registry

    property var _entries: []
    property var _seen: ({})     // path -> true for images already shown this session
    property int _pickIndex: 0
    property string saveDir: _homeDir() + "/Pictures/kde-lockscreen-saves"

    readonly property int unseenRemaining: _orderedUsable()
        .filter(function (e) { return !_seen[e.path] }).length

    // Priority: bing (1) → wikimedia (2) → nasa (3) → picsum (4)
    readonly property var _priority: ({bing: 1, wikimedia: 2, nasa: 3, picsum: 4})

    signal entriesChanged()

    function _load() {
        // Ensure saveDir exists (silent no-op if it does)
        var mkReq = new XMLHttpRequest()
        mkReq.open("PUT", "file://" + saveDir + "/.keep", false)
        try { mkReq.send("") } catch (e) { /* ignore */ }

        var xhr = new XMLHttpRequest()
        var url = "file://" + _homeDir() + "/.cache/kde-lockscreen/manifest.json"
        xhr.open("GET", url, false)
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
        return "/home/denisk"
    }

    function _priorityOf(e) {
        return registry._priority[e.source] !== undefined
            ? registry._priority[e.source]
            : 99
    }

    function _orderedUsable() {
        var arr = _entries.slice().filter(function (e) { return !e.disliked })
        arr.sort(function (a, b) {
            var pa = registry._priorityOf(a)
            var pb = registry._priorityOf(b)
            if (pa !== pb) return pa - pb
            // Same source: newer date first
            if (a.date > b.date) return -1
            if (a.date < b.date) return 1
            return 0
        })
        return arr
    }

    function _usable() {
        return _orderedUsable()
    }

    function pickForScreen(index) {
        var list = _orderedUsable()
        if (list.length === 0) list = _entries
        if (list.length === 0) return Qt.resolvedUrl("fallback.jpg").toString()

        // Prefer first unseen in priority order.
        var pick = null
        for (var i = 0; i < list.length; i++) {
            if (!_seen[list[i].path]) { pick = list[i]; break }
        }
        // If everything seen, wrap around using pickIndex.
        if (!pick) pick = list[_pickIndex % list.length]

        _seen[pick.path] = true
        _pickIndex += 1
        _maybeRequestRefill()
        return "file://" + pick.path
    }

    function advance() {
        // Kept as no-op for backward compat; pickForScreen itself advances.
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

    // When the unseen pool runs thin, touch a trigger file. A systemd .path
    // unit watches this and spawns the Picsum refill.
    function _maybeRequestRefill() {
        if (unseenRemaining <= 10) {
            var req = new XMLHttpRequest()
            var url = "file://" + _homeDir() + "/.cache/kde-lockscreen/refill-request"
            req.open("PUT", url, false)
            try { req.send(String(Date.now())) } catch (e) { /* ignore */ }
        }
    }

    function saveImage(filePath) {
        var p = filePath.replace(/^file:\/\//, "")
        var entry = null
        for (var i = 0; i < _entries.length; i++) {
            if (_entries[i].path === p) { entry = _entries[i]; break }
        }
        if (!entry) return "failed"

        var basename = p.split("/").pop()
        var target = saveDir + "/" + entry.source + "-" + entry.date + "-" + basename

        var check = new XMLHttpRequest()
        check.open("HEAD", "file://" + target, false)
        try { check.send(null) } catch (e) {}
        if (check.status === 200) return "exists"

        var reader = new XMLHttpRequest()
        reader.open("GET", "file://" + p, false)
        reader.overrideMimeType("text/plain; charset=x-user-defined")
        try { reader.send(null) } catch (e) { return "failed" }
        if (reader.status !== 200 && reader.status !== 0) return "failed"

        var writer = new XMLHttpRequest()
        writer.open("PUT", "file://" + target, false)
        try { writer.send(reader.responseText) } catch (e) { return "failed" }
        if (writer.status !== 200 && writer.status !== 0 && writer.status !== 201) return "failed"

        markSaved(filePath)
        return "saved"
    }

    Component.onCompleted: _load()
}
