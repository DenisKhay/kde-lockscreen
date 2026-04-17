import QtQuick 2.15

Item {
    id: registry

    property var _entries: []
    property var _seen: ({})     // path -> true for images already shown this session
    property var _history: []    // ordered list of paths shown this session
    property int _historyPos: -1 // pointer into _history
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

    // Initial image on greeter load. Pushes it into the nav history.
    function pickForScreen(index) {
        var list = _orderedUsable()
        if (list.length === 0) list = _entries
        if (list.length === 0) return Qt.resolvedUrl("fallback.jpg").toString()
        var pick = list[0]
        _seen[pick.path] = true
        if (_history.length === 0) {
            _history = [pick.path]
            _historyPos = 0
        }
        return "file://" + pick.path
    }

    // Forward navigation. If we're sitting mid-history (user pressed Left
    // earlier), step forward through it. Otherwise fetch a new unseen image
    // and append to history. No dislike side-effect — Right just cycles.
    function next() {
        if (_historyPos < _history.length - 1) {
            _historyPos += 1
            return "file://" + _history[_historyPos]
        }
        var list = _orderedUsable()
        if (list.length === 0) list = _entries
        if (list.length === 0) return Qt.resolvedUrl("fallback.jpg").toString()
        var pick = null
        for (var j = 0; j < list.length; j++) {
            if (!_seen[list[j].path]) { pick = list[j]; break }
        }
        if (!pick) pick = list[_history.length % list.length]
        _seen[pick.path] = true
        _history.push(pick.path)
        _historyPos = _history.length - 1
        _maybeRequestRefill()
        return "file://" + pick.path
    }

    // Backward navigation. Returns "" when there's nothing earlier.
    function previous() {
        if (_historyPos <= 0) return ""
        _historyPos -= 1
        return "file://" + _history[_historyPos]
    }

    // Kept for compatibility — no-op now; history is managed by next()/previous().
    function advance() {}

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

    // QML can't safely copy binary files (XHR PUT mangles bytes > 127 via
    // UTF-8 encoding) and Qt file:// XHR only supports GET/PUT — not HEAD.
    // So we write a save-request file (PUT, always allowed) and let the
    // inhibit daemon handle the real shutil.copy + dedup.
    function saveImage(filePath) {
        var p = filePath.replace(/^file:\/\//, "")
        var entry = null
        for (var i = 0; i < _entries.length; i++) {
            if (_entries[i].path === p) { entry = _entries[i]; break }
        }
        if (!entry) return "failed"

        var reqPath = _homeDir() + "/.cache/kde-lockscreen/save-request"
        var writer = new XMLHttpRequest()
        writer.open("PUT", "file://" + reqPath, false)
        try { writer.send(p + "\n") } catch (e) { return "failed" }

        markSaved(filePath)
        return "saved"
    }

    Component.onCompleted: _load()
}
