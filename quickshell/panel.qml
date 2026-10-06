// Gaming Deck — in-game panel (F6 by default): achievements, guides and notes
// for the Steam game being played, drawn on the Wayland overlay layer like
// TEMPS. Nothing is loaded into the game: it is the same for anti-cheat games.
// Started by `gaming-deck panel` (the key) or hidden by `gaming-deck run`, to
// pop up newly unlocked achievements; it quits once no game is running.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

ShellRoot {
    id: root
    property string bin: Quickshell.env("CD_PANEL_BIN") || (Quickshell.env("HOME") + "/.local/bin/gaming-deck")
    property bool shown: false
    property string lang: "en"
    property var game: ({})            // {appid, name, pid, since}
    property var ach: null             // `gaming-deck ach` JSON
    property var guides: []
    property var wiki: ({})
    property var results: []
    property var page: null
    property string wikiState: ""      // "", "busy", "net", "empty", "none"
    property string pendingSearch: ""  // asked for before the wiki was known
    property string tab: "ach"
    property string filter: "pending"
    property var revealed: ({})
    property bool showHidden: false     // H: every hidden achievement's text at once
    property string notes: ""
    property bool notesLoaded: false
    property string cpu: ""
    property string gpu: ""
    property int now: Math.floor(Date.now() / 1000)
    property string statsStamp: ""
    property int idle: 0
    property var toasts: []
    property bool toastOn: true

    readonly property string mono: "JetBrainsMono Nerd Font"
    QtObject {
        id: pal
        readonly property color bg:      "#fc07080d"
        readonly property color card:    "#11141f"
        readonly property color cardHi:  "#172036"
        readonly property color border:  "#1f2638"
        readonly property color accent:  "#5eead4"
        readonly property color violet:  "#a78bfa"
        readonly property color text:    "#e2e8f0"
        readonly property color dim:     "#7c8aa0"
        readonly property color ok:      "#4ade80"
        readonly property color bad:     "#fb7185"
        readonly property color amber:   "#fbbf24"
    }

    // ---- language: the deck's own ESP/ENG ----
    readonly property var es: ({
        "ACHIEVEMENTS": "LOGROS", "GUIDES": "GUÍAS", "NOTES": "NOTAS",
        "Pending": "Pendientes", "Unlocked": "Conseguidos", "All": "Todos",
        "achievements": "logros", "of players": "de jugadores",
        "Hidden achievement — Space or click to reveal": "Logro oculto — Espacio o clic para verlo",
        "Guide ›": "Guía ›", "Unlocked on ": "Conseguido el ",
        "No Steam game is running.": "No hay ningún juego de Steam en marcha.",
        "This game has no achievements, or Steam hasn't saved them on this PC yet (play it once with Steam online).": "Este juego no tiene logros, o Steam aún no los ha guardado en este PC (juégalo una vez con Steam en línea).",
        "Python 3 is needed to read the achievements.": "Hace falta Python 3 para leer los logros.",
        "Couldn't read Steam's achievement files.": "No se pudieron leer los archivos de logros de Steam.",
        "Search the wiki…": "Buscar en la wiki…", "Searching…": "Buscando…",
        "Couldn't reach the wiki (offline?).": "No se pudo conectar con la wiki (¿sin conexión?).",
        "No results.": "Sin resultados.",
        "No Fandom wiki found for this game. Paste its address:": "No se encontró una wiki de Fandom para este juego. Pega su dirección:",
        "OPEN IN BROWSER": "ABRIR EN EL NAVEGADOR", "‹ RESULTS": "‹ RESULTADOS",
        "Text: ": "Texto: ", "Opens in your browser (leave the game with Alt+Tab):": "Se abren en el navegador (sal del juego con Alt+Tab):",
        "guide": "guía", "community guides": "guías de la comunidad", "global achievements": "logros globales",
        "Your notes for this game (saved as you type)": "Tus notas de este juego (se guardan al escribir)",
        "+ TIMESTAMP": "+ MARCA DE TIEMPO", "session": "sesión",
        "Achievement unlocked": "Logro desbloqueado",
        "close": "cerrar", "move": "moverse", "reveal": "ver", "tabs": "pestañas", "Space": "Espacio", "Show hidden": "Mostrar ocultos"
    })
    function tr(s) { return lang === "es" && es[s] !== undefined ? es[s] : s; }

    function parse(t, dflt) { try { return JSON.parse(t); } catch (e) { return dflt; } }
    function dur(s) { s = Math.max(0, s); var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60); return h > 0 ? h + "h " + (m < 10 ? "0" : "") + m + "m" : m + "m"; }
    function tempColor(t) { var n = parseInt(t); return isNaN(n) ? pal.dim : (n >= 85 ? pal.bad : (n >= 75 ? pal.amber : pal.text)); }
    function rarityColor(r) { return r === null || r === undefined ? pal.dim : (r < 5 ? pal.amber : (r < 20 ? pal.violet : pal.dim)); }

    // ---- jobs: one Process each, a newer call replaces a running one ----
    component Job: Process {
        id: job
        property var cur: null
        property var next: null
        stdout: StdioCollector { onStreamFinished: { var c = job.cur; job.cur = null; if (c) c(text); } }
        onRunningChanged: if (!running && next) { var n = next; next = null; cur = n[1]; command = n[0]; running = true; }
    }
    function call(job, args, cb) {
        var cmd = [root.bin].concat(args);
        if (job.running) { job.cur = null; job.next = [cmd, cb]; job.running = false; return; }
        job.cur = cb; job.command = cmd; job.running = true;
    }
    Job { id: jIngame }  Job { id: jAch }  Job { id: jGuides }  Job { id: jWiki }
    Job { id: jSearch }  Job { id: jPage } Job { id: jNotes }   Job { id: jSave }
    Job { id: jTemps }   Job { id: jOpen } Job { id: jMisc }
    Process { id: jStat; property var cur: null
        stdout: StdioCollector { onStreamFinished: { var c = jStat.cur; jStat.cur = null; if (c) c(text.trim()); } } }

    // ---- data ----
    function refreshGame(then) {
        call(jIngame, ["ingame"], function (t) {
            var g = parse(t, {});
            var changed = (g.appid || "") !== (root.game.appid || "");
            root.game = g;
            if (changed) {
                root.ach = null; root.guides = []; root.wiki = ({}); root.results = []; root.page = null;
                root.wikiState = ""; root.notes = ""; root.notesLoaded = false; root.statsStamp = ""; root.revealed = ({});
            }
            if (then) then(changed);
        });
    }
    function loadAll() {
        if (!game.appid) return;
        loadAch(false);
        call(jGuides, ["guides", game.appid], function (t) { root.guides = parse(t, []); });
        wikiState = "busy";
        call(jWiki, ["wiki", game.appid], function (t) {
            root.wiki = parse(t, {}); root.wikiState = root.wiki.base ? "" : "none";
            if (root.wiki.base && root.pendingSearch !== "") { var q = root.pendingSearch; root.pendingSearch = ""; root.wikiSearch(q); }
        });
        if (!notesLoaded) call(jNotes, ["notes", game.appid], function (t) { root.notes = t; root.notesLoaded = true; });
        call(jTemps, ["temps"], readTemps);
    }
    function loadAch(announce) {
        if (!game.appid) return;
        var id = game.appid;
        call(jAch, ["ach", id], function (t) {
            var a = parse(t, null);
            if (!a || root.game.appid !== id) return;
            if (announce && root.ach && root.ach.items && a.items) {
                var had = {};
                root.ach.items.forEach(function (i) { if (i.unlocked) had[i.id] = true; });
                a.items.forEach(function (i) { if (i.unlocked && !had[i.id]) root.pushToast(i); });
            }
            root.ach = a;
        });
    }
    function readTemps(t) {
        t.split("\n").forEach(function (l) {
            var i = l.indexOf("="); if (i < 0) return;
            if (l.substring(0, i) === "CPU") root.cpu = l.substring(i + 1);
            else if (l.substring(0, i) === "GPU") root.gpu = l.substring(i + 1);
        });
    }
    function wikiSearch(q) {
        if (q.trim() === "") return;
        if (!wiki.base) { if (wikiState !== "none") pendingSearch = q; return; }   // the wiki is still being looked up
        page = null; results = []; wikiState = "busy";
        call(jSearch, ["wiki", game.appid, "search", q], function (t) {
            var r = parse(t, null);
            if (!r || r.error) { root.wikiState = "net"; return; }
            root.results = r; root.wikiState = r.length ? "" : "empty";
        });
    }
    function wikiPage(title) {
        wikiState = "busy";
        call(jPage, ["wiki", game.appid, "page", title], function (t) {
            var p = parse(t, null);
            if (!p || p.error || !p.text) { root.wikiState = "net"; return; }
            root.page = p; root.wikiState = "";
        });
    }
    function guideFor(item) {
        tab = "guide";
        var q = item.nameEn || item.name;
        searchBox.text = q;
        wikiSearch(q);
    }
    function openUrl(u) { call(jOpen, ["gopen", u], null); }

    // ---- sorted / filtered achievements ----
    property var shownItems: {
        if (!ach || !ach.items) return [];
        var f = filter, l = ach.items.filter(function (i) { return f === "all" || (f === "done") === i.unlocked; });
        return l.slice().sort(function (a, b) {
            if (a.unlocked !== b.unlocked) return a.unlocked ? 1 : -1;
            if (a.unlocked) return b.time - a.time;                       // newest first
            return (b.rarity === null ? -1 : b.rarity) - (a.rarity === null ? -1 : a.rarity);   // easiest first
        });
    }

    // ---- show / hide, toggled by the key ----
    function show() {
        refreshGame(function () { loadAll(); });
        shown = true;
        focusTimer.restart();
    }
    function hide() { shown = false; saveNotes(); }
    function toggle() { if (shown) hide(); else show(); }
    Timer { id: focusTimer; interval: 60; onTriggered: keys.forceActiveFocus() }

    IpcHandler {
        target: "panel"
        // (not "show": `qs ipc` takes that word for itself)
        function toggle(): void { root.toggle(); }
        function open(): void { root.show(); }
        function close(): void { root.hide(); }
        function tab(name: string): void { if (["ach", "guide", "notes"].indexOf(name) >= 0) root.tab = name; }
        function page(title: string): void { if (!root.shown) root.show(); root.tab = "guide"; root.wikiPage(title); }
        function search(text: string): void { if (!root.shown) root.show(); root.tab = "guide"; searchBox.text = text; root.wikiSearch(text); }
        function ping(): string { return "ok"; }
        // for `gaming-deck panel status` and debugging
        function state(): string { return JSON.stringify({ shown: root.shown, game: root.game, achievements: root.ach ? root.ach.unlocked + "/" + root.ach.total : null, stamp: root.statsStamp, toasts: root.toasts.length, idle: root.idle }); }
    }

    Component.onCompleted: {
        call(jMisc, ["uilang"], function (t) {
            var l = t.trim(); if (l === "es" || l === "en") root.lang = l;
            root.call(jMisc, ["panel", "status"], function (s) { var st = root.parse(s, {}); root.toastOn = st.toast !== false; });
        });
        if (Quickshell.env("CD_PANEL_SHOW") === "1") show();
        else refreshGame(function () { loadAch(false); });
    }

    // every 3 s: the game is still there? its achievement file changed?
    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: {
            root.now = Math.floor(Date.now() / 1000);
            if (root.shown) root.call(jTemps, ["temps"], root.readTemps);
            if (!root.game.appid || root.idle % 4 === 3) {
                root.refreshGame(function (changed) {
                    if (!root.game.appid) {
                        if (!root.shown && ++root.idle > 6) Qt.quit();      // ~20 s without a game: done
                        return;
                    }
                    root.idle = 0;
                    if (changed) { if (root.shown) root.loadAll(); else root.loadAch(false); }
                });
                if (root.game.appid) root.idle++;
                return;
            }
            root.idle++;
            var f = root.ach && root.ach.statsFile;
            if (!f || jStat.running) return;
            jStat.cur = function (st) {
                if (st === "") return;
                if (root.statsStamp !== "" && st !== root.statsStamp) root.loadAch(root.toastOn);
                root.statsStamp = st;
            };
            jStat.command = ["stat", "-c", "%Y", f];
            jStat.running = true;
        }
    }

    // ---- notes ----
    Timer { id: saveTimer; interval: 1200; onTriggered: root.saveNotes() }
    function saveNotes() {
        if (!notesLoaded || !game.appid) return;
        saveTimer.stop();
        call(jSave, ["notes", game.appid, "set", notes], null);
    }

    // ---- toasts ----
    function pushToast(i) { var l = toasts.slice(); l.push(i); toasts = l; if (!toastTimer.running) toastTimer.start(); }
    Timer { id: toastTimer; interval: 6000; onTriggered: { var l = root.toasts.slice(1); root.toasts = l; if (l.length) start(); } }

    PanelWindow {
        id: toastWin
        anchors { top: true }
        margins { top: 36 }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "gaming-deck-toast"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}
        color: "transparent"
        visible: root.toasts.length > 0
        implicitWidth: 420; implicitHeight: 84
        Rectangle {
            id: toastBox
            anchors.fill: parent; radius: 12
            color: pal.bg; border.color: pal.amber; border.width: 1
            property var t: root.toasts.length ? root.toasts[0] : null
            Row {
                anchors.fill: parent; anchors.margins: 12; spacing: 12
                Image { width: 58; height: 58; source: toastBox.t ? toastBox.t.icon : ""; asynchronous: true; cache: true; fillMode: Image.PreserveAspectFit }
                Column {
                    width: parent.width - 70; spacing: 2; anchors.verticalCenter: parent.verticalCenter
                    Text { text: "🏆 " + root.tr("Achievement unlocked"); color: pal.amber; font.family: root.mono; font.pixelSize: 12; font.bold: true }
                    Text { width: parent.width; elide: Text.ElideRight; text: toastBox.t ? toastBox.t.name : ""; color: pal.text; font.pixelSize: 16; font.bold: true }
                    Text {
                        width: parent.width; elide: Text.ElideRight; color: pal.dim; font.pixelSize: 12
                        property var t: toastBox.t
                        text: t ? (t.rarity !== null && t.rarity !== undefined ? t.rarity.toFixed(1) + " % " + root.tr("of players") + " · " : "") + t.desc : ""
                    }
                }
            }
        }
    }

    // ---- the panel ----
    PanelWindow {
        id: win
        visible: root.shown
        anchors { top: true; bottom: true; right: true }
        margins { top: 28; bottom: 28; right: 28 }
        implicitWidth: 560
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "gaming-deck-panel"
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        Rectangle {
            id: keys
            anchors.fill: parent
            radius: 14; color: pal.bg; border.color: pal.border; border.width: 1
            focus: true
            Keys.onPressed: function (e) {
                if (e.key === Qt.Key_Escape) { root.hide(); e.accepted = true; }
                else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                    var t = ["ach", "guide", "notes"], i = t.indexOf(root.tab);
                    root.tab = t[(i + (e.key === Qt.Key_Tab ? 1 : 2)) % 3]; e.accepted = true;
                    if (root.tab === "notes") notesEdit.forceActiveFocus(); else keys.forceActiveFocus();
                }
                else if (root.tab === "ach" && (e.key === Qt.Key_Down || e.key === Qt.Key_Up)) {
                    achList.currentIndex = Math.max(0, Math.min(achList.count - 1, achList.currentIndex + (e.key === Qt.Key_Down ? 1 : -1))); e.accepted = true;
                }
                else if (root.tab === "ach" && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && achList.currentIndex >= 0) {
                    root.guideFor(root.shownItems[achList.currentIndex]); e.accepted = true;
                }
                else if (root.tab === "ach" && e.key === Qt.Key_Space && achList.currentIndex >= 0) {
                    var r = Object.assign({}, root.revealed); r[root.shownItems[achList.currentIndex].id] = true; root.revealed = r; e.accepted = true;
                }
                else if (root.tab === "ach" && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) {
                    var f = ["pending", "done", "all"], j = f.indexOf(root.filter);
                    root.filter = f[(j + (e.key === Qt.Key_Right ? 1 : 2)) % 3]; achList.currentIndex = 0; e.accepted = true;
                }
                else if (root.tab === "ach" && e.key === Qt.Key_H) { root.showHidden = !root.showHidden; e.accepted = true; }
                else if (root.tab === "guide" && root.page && [Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown].indexOf(e.key) >= 0) {
                    var step = (e.key === Qt.Key_PageUp || e.key === Qt.Key_PageDown) ? pageFlick.height * 0.9 : 60;
                    var dy = (e.key === Qt.Key_Up || e.key === Qt.Key_PageUp) ? -step : step;
                    pageFlick.contentY = Math.max(0, Math.min(pageFlick.contentHeight - pageFlick.height, pageFlick.contentY + dy)); e.accepted = true;
                }
                else if (root.tab === "guide" && root.page && e.key === Qt.Key_Backspace) { root.page = null; e.accepted = true; }
                else if (root.tab === "guide" && e.key === Qt.Key_Slash) { searchBox.forceActiveFocus(); e.accepted = true; }
            }

            Column {
                id: head
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                spacing: 10
                Row {
                    width: parent.width
                    Text {
                        width: parent.width - stat.width; elide: Text.ElideRight
                        text: root.game.name || (root.ach && root.ach.game) || "Gaming Deck"
                        color: pal.text; font.pixelSize: 20; font.bold: true
                    }
                    Row {
                        id: stat; spacing: 6; anchors.verticalCenter: parent.verticalCenter
                        Text { text: "CPU"; color: pal.violet; font.family: root.mono; font.pixelSize: 12; font.bold: true }
                        Text { text: root.cpu !== "" ? root.cpu + "°" : "–"; color: root.tempColor(root.cpu); font.family: root.mono; font.pixelSize: 12; font.bold: true }
                        Text { text: "GPU"; color: pal.violet; font.family: root.mono; font.pixelSize: 12; font.bold: true }
                        Text { text: root.gpu !== "" ? root.gpu + "°" : "–"; color: root.tempColor(root.gpu); font.family: root.mono; font.pixelSize: 12; font.bold: true }
                        Text { visible: !!root.game.since; text: "· " + root.dur(root.now - (root.game.since || root.now)); color: pal.dim; font.family: root.mono; font.pixelSize: 12 }
                        Text {
                            text: "  ✕"; color: closeMa.containsMouse ? pal.bad : pal.dim; font.pixelSize: 15
                            MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.hide() }
                        }
                    }
                }
                // progress
                Column {
                    width: parent.width; spacing: 4
                    visible: !!(root.ach && root.ach.total)
                    Text {
                        text: root.ach ? root.ach.unlocked + " / " + root.ach.total + " " + root.tr("achievements") + "  ·  " + root.ach.percent + " %" : ""
                        color: pal.dim; font.family: root.mono; font.pixelSize: 12
                    }
                    Rectangle {
                        width: parent.width; height: 6; radius: 3; color: pal.card
                        Rectangle { height: parent.height; radius: 3; color: pal.accent; width: parent.width * (root.ach ? root.ach.percent / 100 : 0) }
                    }
                }
                // tabs
                Row {
                    spacing: 6
                    Repeater {
                        model: [["ach", "ACHIEVEMENTS"], ["guide", "GUIDES"], ["notes", "NOTES"]]
                        Rectangle {
                            width: tt.implicitWidth + 22; height: 28; radius: 6
                            color: root.tab === modelData[0] ? pal.accent : pal.card
                            Text { id: tt; anchors.centerIn: parent; text: root.tr(modelData[1]); color: root.tab === modelData[0] ? "#07080d" : pal.text; font.family: root.mono; font.pixelSize: 12; font.bold: true }
                            MouseArea { anchors.fill: parent; onClicked: { root.tab = modelData[0]; if (root.tab === "notes") notesEdit.forceActiveFocus(); else keys.forceActiveFocus(); } }
                        }
                    }
                }
            }

            Item {
                id: body
                anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top; margins: 18; topMargin: 12 }

                Text {
                    visible: !root.game.appid
                    width: parent.width; wrapMode: Text.WordWrap
                    text: root.tr("No Steam game is running."); color: pal.dim; font.pixelSize: 14
                }

                // ---------------- achievements ----------------
                Item {
                    anchors.fill: parent
                    visible: root.tab === "ach" && !!root.game.appid
                    Text {
                        visible: !!(root.ach && root.ach.error)
                        width: parent.width; wrapMode: Text.WordWrap; color: pal.dim; font.pixelSize: 14
                        text: !root.ach ? "" : root.ach.error === "noschema" ? root.tr("This game has no achievements, or Steam hasn't saved them on this PC yet (play it once with Steam online).")
                            : root.ach.error === "python" ? root.tr("Python 3 is needed to read the achievements.") : root.tr("Couldn't read Steam's achievement files.")
                    }
                    Row {
                        id: filters; spacing: 6
                        visible: !!(root.ach && root.ach.items)
                        Rectangle {
                            visible: root.ach && root.ach.items ? root.ach.items.some(function (i) { return i.hidden && !i.unlocked; }) : false
                            width: ht.implicitWidth + 18; height: 24; radius: 12
                            color: root.showHidden ? pal.cardHi : "transparent"
                            border.color: root.showHidden ? pal.violet : pal.border; border.width: 1
                            Text { id: ht; anchors.centerIn: parent; text: (root.showHidden ? "◉ " : "○ ") + root.tr("Show hidden") + " (H)"; color: root.showHidden ? pal.violet : pal.dim; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; onClicked: root.showHidden = !root.showHidden }
                        }
                        Repeater {
                            model: [["pending", "Pending"], ["done", "Unlocked"], ["all", "All"]]
                            Rectangle {
                                width: ft.implicitWidth + 18; height: 24; radius: 12
                                color: root.filter === modelData[0] ? pal.cardHi : "transparent"
                                border.color: root.filter === modelData[0] ? pal.accent : pal.border; border.width: 1
                                Text { id: ft; anchors.centerIn: parent; text: root.tr(modelData[1]); color: root.filter === modelData[0] ? pal.accent : pal.dim; font.pixelSize: 12 }
                                MouseArea { anchors.fill: parent; onClicked: { root.filter = modelData[0]; achList.currentIndex = 0; } }
                            }
                        }
                    }
                    ListView {
                        id: achList
                        anchors { left: parent.left; right: parent.right; top: filters.bottom; bottom: parent.bottom; topMargin: 10 }
                        clip: true; spacing: 6
                        model: root.shownItems
                        currentIndex: 0
                        highlightMoveDuration: 80
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            property bool secret: modelData.hidden && !modelData.unlocked && !root.showHidden && !root.revealed[modelData.id]
                            width: achList.width; height: Math.max(64, info.implicitHeight + 16); radius: 8
                            color: achList.currentIndex === index ? pal.cardHi : pal.card
                            border.color: achList.currentIndex === index ? pal.accent : "transparent"; border.width: 1
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    achList.currentIndex = row.index; keys.forceActiveFocus();
                                    if (row.secret) { var r = Object.assign({}, root.revealed); r[row.modelData.id] = true; root.revealed = r; }
                                }
                            }
                            Image {
                                id: ic; x: 8; anchors.verticalCenter: parent.verticalCenter
                                width: 48; height: 48; source: row.modelData.icon; asynchronous: true; cache: true
                                opacity: row.modelData.unlocked ? 1 : 0.55
                            }
                            Column {
                                id: info
                                anchors { left: ic.right; leftMargin: 10; right: gbtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Text { width: parent.width; elide: Text.ElideRight; text: row.secret ? "••••••" : row.modelData.name; color: row.modelData.unlocked ? pal.ok : pal.text; font.pixelSize: 14; font.bold: true }
                                Text {
                                    width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                                    text: row.secret ? root.tr("Hidden achievement — Space or click to reveal") : row.modelData.desc
                                    color: row.secret ? pal.violet : pal.dim; font.pixelSize: 12
                                }
                                Text {
                                    property var r: row.modelData.rarity
                                    visible: r !== null && r !== undefined || row.modelData.unlocked
                                    text: (r !== null && r !== undefined ? r.toFixed(1) + " % " + root.tr("of players") : "")
                                          + (row.modelData.unlocked && row.modelData.time ? (r !== null && r !== undefined ? "  ·  " : "") + root.tr("Unlocked on ")
                                             + new Date(row.modelData.time * 1000).toLocaleDateString(Qt.locale(root.lang === "es" ? "es_ES" : "en_GB"), "d MMM yyyy") : "")
                                    color: root.rarityColor(r); font.family: root.mono; font.pixelSize: 11
                                }
                            }
                            Rectangle {
                                id: gbtn
                                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                visible: !row.secret
                                width: gt.implicitWidth + 14; height: 24; radius: 5; color: gma.containsMouse ? pal.cardHi : "transparent"
                                border.color: pal.border; border.width: 1
                                Text { id: gt; anchors.centerIn: parent; text: root.tr("Guide ›"); color: pal.accent; font.pixelSize: 11; font.bold: true }
                                MouseArea { id: gma; anchors.fill: parent; hoverEnabled: true; onClicked: root.guideFor(row.modelData) }
                            }
                        }
                    }
                }

                // ---------------- guides ----------------
                Item {
                    anchors.fill: parent
                    visible: root.tab === "guide" && !!root.game.appid
                    Column {
                        id: links; width: parent.width; spacing: 6
                        Text { text: root.tr("Opens in your browser (leave the game with Alt+Tab):"); color: pal.dim; font.pixelSize: 11 }
                        Flow {
                            width: parent.width; spacing: 6
                            Repeater {
                                model: root.guides
                                Rectangle {
                                    width: lt.implicitWidth + 18; height: 26; radius: 5
                                    color: lma.containsMouse ? pal.cardHi : pal.card; border.color: pal.border; border.width: 1
                                    Text {
                                        id: lt; anchors.centerIn: parent; font.pixelSize: 12
                                        textFormat: Text.StyledText; color: pal.text
                                        text: "<b>" + modelData.label + "</b> <font color='#7c8aa0'>" + root.tr(modelData.sub) + " ↗</font>"
                                    }
                                    MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; onClicked: root.openUrl(modelData.url) }
                                }
                            }
                        }
                        // wiki search
                        Rectangle {
                            width: parent.width; height: 34; radius: 6; color: pal.card
                            border.color: searchBox.activeFocus ? pal.accent : pal.border; border.width: 1
                            visible: !!root.wiki.base
                            TextInput {
                                id: searchBox
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                verticalAlignment: TextInput.AlignVCenter; clip: true
                                color: pal.text; font.pixelSize: 14; selectByMouse: true
                                onAccepted: root.wikiSearch(text)
                                Keys.onEscapePressed: keys.forceActiveFocus()
                                Text { anchors.verticalCenter: parent.verticalCenter; visible: !parent.text && !parent.activeFocus; text: root.tr("Search the wiki…") + "  (/)"; color: pal.dim; font.pixelSize: 14 }
                            }
                        }
                        // no wiki: let the player give its address
                        Column {
                            width: parent.width; spacing: 6
                            visible: root.wikiState === "none"
                            Text { width: parent.width; wrapMode: Text.WordWrap; text: root.tr("No Fandom wiki found for this game. Paste its address:"); color: pal.dim; font.pixelSize: 12 }
                            Rectangle {
                                width: parent.width; height: 32; radius: 6; color: pal.card; border.color: wikiUrl.activeFocus ? pal.accent : pal.border; border.width: 1
                                TextInput {
                                    id: wikiUrl; anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                    verticalAlignment: TextInput.AlignVCenter; clip: true; color: pal.text; font.pixelSize: 13
                                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !parent.text; text: "https://<game>.fandom.com"; color: pal.dim; font.pixelSize: 13 }
                                    onAccepted: root.call(jMisc, ["wiki", root.game.appid, "set", text.trim()], function () {
                                        root.call(jWiki, ["wiki", root.game.appid], function (t) { root.wiki = root.parse(t, {}); root.wikiState = root.wiki.base ? "" : "none"; });
                                    })
                                }
                            }
                        }
                        Text {
                            visible: root.wikiState === "busy" || root.wikiState === "net" || root.wikiState === "empty"
                            text: root.wikiState === "busy" ? root.tr("Searching…") : root.wikiState === "net" ? root.tr("Couldn't reach the wiki (offline?).") : root.tr("No results.")
                            color: pal.dim; font.pixelSize: 12
                        }
                    }
                    // results
                    ListView {
                        anchors { left: parent.left; right: parent.right; top: links.bottom; bottom: parent.bottom; topMargin: 8 }
                        visible: !root.page && root.results.length > 0
                        clip: true; spacing: 4
                        model: root.results
                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view.width; height: 32; radius: 6
                            color: rma.containsMouse ? pal.cardHi : pal.card
                            Text { anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 10 } elide: Text.ElideRight; text: parent.modelData.title; color: pal.text; font.pixelSize: 13 }
                            MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; onClicked: root.wikiPage(parent.modelData.title) }
                        }
                    }
                    // a page
                    Item {
                        anchors { left: parent.left; right: parent.right; top: links.bottom; bottom: parent.bottom; topMargin: 8 }
                        visible: !!root.page
                        Row {
                            id: pageBar; spacing: 8
                            Rectangle {
                                width: bt.implicitWidth + 14; height: 24; radius: 5; color: pal.card
                                Text { id: bt; anchors.centerIn: parent; text: root.tr("‹ RESULTS"); color: pal.accent; font.pixelSize: 11; font.bold: true }
                                MouseArea { anchors.fill: parent; onClicked: root.page = null }
                            }
                            Rectangle {
                                width: ot.implicitWidth + 14; height: 24; radius: 5; color: pal.card
                                Text { id: ot; anchors.centerIn: parent; text: root.tr("OPEN IN BROWSER") + " ↗"; color: pal.text; font.pixelSize: 11; font.bold: true }
                                MouseArea { anchors.fill: parent; onClicked: if (root.page) root.openUrl(root.page.url) }
                            }
                        }
                        Flickable {
                            id: pageFlick
                            anchors { left: parent.left; right: parent.right; top: pageBar.bottom; bottom: attrib.top; topMargin: 8; bottomMargin: 6 }
                            clip: true; contentHeight: pageText.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            Text {
                                id: pageText; width: pageFlick.width; wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                                text: root.page ? root.page.title + "\n\n" + root.page.text : ""
                onTextChanged: pageFlick.contentY = 0
                                color: pal.text; font.pixelSize: 13; lineHeight: 1.15
                            }
                        }
                        Text {
                            id: attrib; anchors.bottom: parent.bottom; width: parent.width; elide: Text.ElideRight
                            text: root.page ? root.tr("Text: ") + root.page.source + " (Fandom) · " + root.page.license : ""
                            color: pal.dim; font.pixelSize: 10
                        }
                    }
                }

                // ---------------- notes ----------------
                Item {
                    anchors.fill: parent
                    visible: root.tab === "notes" && !!root.game.appid
                    Row {
                        id: notesBar; width: parent.width; spacing: 8
                        Text { width: parent.width - tsb.width - 8; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; text: root.tr("Your notes for this game (saved as you type)"); color: pal.dim; font.pixelSize: 11 }
                        Rectangle {
                            id: tsb; width: tst.implicitWidth + 14; height: 24; radius: 5; color: pal.card
                            Text { id: tst; anchors.centerIn: parent; text: root.tr("+ TIMESTAMP"); color: pal.accent; font.pixelSize: 11; font.bold: true }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var d = new Date(), p = function (n) { return (n < 10 ? "0" : "") + n; };
                                    var s = "[" + d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + " " + p(d.getHours()) + ":" + p(d.getMinutes())
                                            + (root.game.since ? " · " + root.tr("session") + " " + root.dur(root.now - root.game.since) : "") + "] ";
                                    notesEdit.insert(notesEdit.cursorPosition, (notesEdit.cursorPosition > 0 && notesEdit.text[notesEdit.cursorPosition - 1] !== "\n" ? "\n" : "") + s);
                                    notesEdit.forceActiveFocus();
                                }
                            }
                        }
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; top: notesBar.bottom; bottom: parent.bottom; topMargin: 8 }
                        radius: 8; color: pal.card; border.color: notesEdit.activeFocus ? pal.accent : pal.border; border.width: 1
                        Flickable {
                            id: nf; anchors.fill: parent; anchors.margins: 10; clip: true
                            contentHeight: notesEdit.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                            TextEdit {
                                id: notesEdit; width: nf.width; wrapMode: TextEdit.Wrap
                                color: pal.text; font.pixelSize: 14; selectByMouse: true
                                text: root.notes
                                onTextChanged: if (root.notesLoaded && text !== root.notes) { root.notes = text; saveTimer.restart(); }
                                Keys.onEscapePressed: root.hide()
                                onCursorRectangleChanged: {
                                    if (cursorRectangle.y < nf.contentY) nf.contentY = cursorRectangle.y;
                                    else if (cursorRectangle.y + cursorRectangle.height > nf.contentY + nf.height) nf.contentY = cursorRectangle.y + cursorRectangle.height - nf.height;
                                }
                            }
                        }
                    }
                }
            }

            Text {
                id: foot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                text: "Esc " + root.tr("close") + "  ·  Tab " + root.tr("tabs") + "  ·  ↑↓ ←→ " + root.tr("move") + "  ·  ⏎ " + root.tr("guide") + "  ·  " + root.tr("Space") + " " + root.tr("reveal")
                color: pal.dim; font.family: root.mono; font.pixelSize: 10
            }
        }
    }
}
