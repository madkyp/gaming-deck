import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "es.js" as I18n

ShellRoot {
    FloatingWindow {
        id: win
        title: "Gaming Deck"
        implicitWidth: 1180
        implicitHeight: 820
        color: pal.bg
        // closing the window ends the process: a windowless instance would
        // reopen its window on every reload (each install/update of shell.qml).
        // A reload also closes the old window, but destroys this timer with it.
        onClosed: quitTimer.start()
        Timer { id: quitTimer; interval: 1500; onTriggered: Qt.quit() }

        // ---- palette (GAMING DECK): deep blue-black, cyan → violet accent ----
        QtObject {
            id: pal
            readonly property color bg:       "#07080d"
            readonly property color panel:    "#0c0e16"
            readonly property color side:     "#090b12"
            readonly property color card:     "#11141f"
            readonly property color cardHi:   "#172036"
            readonly property color border:   "#1f2638"
            readonly property color accent:   "#5eead4"
            readonly property color accentHi: "#99f6e4"
            readonly property color violet:   "#a78bfa"
            readonly property color pink:     "#f0abfc"
            readonly property color text:     "#e2e8f0"
            readonly property color dim:      "#64748b"
            readonly property color ok:       "#4ade80"
            readonly property color bad:      "#fb7185"
            readonly property color sky:      "#38bdf8"
            readonly property color amber:    "#fbbf24"
            readonly property color logBg:    "#05060a"
        }
        readonly property string mono: "JetBrainsMono Nerd Font"
        readonly property string home: Quickshell.env("HOME")
        property string scriptPath: Quickshell.env("GAMING_DECK_BIN") || (home + "/.local/bin/gaming-deck")
        // UI language: "en" or "es" (ESP/ENG in the sidebar); saved by the backend
        property string lang: "en"
        function t(s) {
            if (lang !== "es" || typeof s !== "string") return s;
            if (I18n.ES[s] !== undefined) return I18n.ES[s];
            for (var i = 0; i < I18n.PATTERNS.length; i++)
                if (I18n.PATTERNS[i][0].test(s)) return s.replace(I18n.PATTERNS[i][0], I18n.PATTERNS[i][1]);
            var m = /^([0-9][0-9\/]*)( .*)$/.exec(s);             // "6 GAMES", "2/3 READY"
            if (m && I18n.ES[m[2]] !== undefined) return m[1] + I18n.ES[m[2]];
            for (var k in I18n.ES)                                 // "REVIEWING foo…", "FAILED · 3"
                if (/[ #:·] ?$/.test(k) && k.length > 3 && s.indexOf(k) === 0) return I18n.ES[k] + s.slice(k.length);
            return s;
        }
        // GAMING_DECK_VIEW=fx|status|health|… opens straight on a section
        Component.onCompleted: {
            var v = Quickshell.env("GAMING_DECK_VIEW");
            if (v) gameView = v;
            versionProc.running = true; selfcheckProc.running = true;
            openGaming();
        }
        // the sidebar's sections: [key, glyph, label]
        readonly property var sections: [
            ["library",  "", "LIBRARY"],
            ["fx",       "", "FX"],
            ["status",   "", "STATUS"],
            ["health",   "", "HEALTH"],
            ["shaders",  "", "SHADERS"],
            ["bench",    "", "BENCH"],
            ["prefixes", "", "PREFIXES"],
            ["maint",    "", "MAINTENANCE"]]
        function tagTone(tone) { return tone === "ok" ? pal.ok : (tone === "bad" ? pal.bad : (tone === "warn" ? pal.amber : pal.sky)); }
        // "Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070/9070 XT/9070 GRE]" → "Radeon RX 9070/9070 XT/9070 GRE"
        function shortGpu(n) {
            n = String(n || "");
            var m = /\[(Radeon[^\]]*)\]/.exec(n);
            if (m) return m[1];
            return n.replace(/^(NVIDIA Corporation|Advanced Micro Devices, Inc\.( \[AMD\/ATI\])?|Intel Corporation)\s*/, "");
        }
        function sectionTitle(k) {
            var s = sections.filter(function (x) { return x[0] === k; })[0];
            return k === "game" ? selGameName : (s ? win.t(s[2]) : "");
        }
        function goSection(k) {
            if (k === "fx") openFx(); else gameView = k;
        }
        // Gaming Deck itself: installed version, a newer one on GitHub
        property string deckVersion: ""
        property var    deckNew: ({})
        // MAINTENANCE: GE-Proton, game clean-up, backup
        property var    proton: ({})
        property var    gclean: []
        property string confirmClean: ""


        function srcColor(s) {
            switch (s) {
                case "repo":     return pal.accent;
                case "aur":      return pal.pink;
                case "flatpak":  return pal.sky;
                case "github":   return pal.amber;
                case "appimage": return pal.ok;
                case "deck":     return pal.accentHi;
                case "proton":   return pal.bad;
                default:         return pal.dim;
            }
        }
        function riskColor(r) { return r === "high" ? pal.bad : (r === "medium" ? pal.amber : pal.ok); }
        function expandHome(p) { return p.charAt(0) === "~" ? home + p.substring(1) : p; }
        function human(b) {
            if (!b) return "";
            var u = ["B", "KB", "MB", "GB", "TB"], i = 0;
            while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
            return (i === 0 ? b : b.toFixed(b < 10 ? 1 : 0)) + " " + u[i];
        }


        // ---- gaming state -----------------------------------------------
        property string gameView: "library"
        onGameViewChanged: loadGameView()
        function loadGameView() {
            if (gameView === "status") gstatProc.running = true;
            else if (gameView === "shaders") shaderProc.running = true;
            else if (gameView === "bench") { if (selGame && selGameSource === "steam") benchProc.running = true; }
            else if (gameView === "prefixes") { pfxProc.running = true; pfxBakProc.running = true; }
            else if (gameView === "health") healthProc.running = true;
            else if (gameView === "fx" && !fxStatProc.running) openFx();
            else if (gameView === "maint") { protonProc.running = true; gcleanProc.running = true; selfcheckProc.running = true; }
        }
        property var    games: []
        property var    ioInfo: ({})        // the selected game's disk + I/O scheduler (IO PRIORITY)
        property var    mods: ({})          // the selected game's mods in Crisol ({} = no Crisol / not there)
        property var    uopts: ({})         // an Umbral game's options (Umbral 0.12+: umbral --get); {} = read-only
        function uset(args) { runGame(["uset", selGame].concat(args), "SAVING…"); }
        // the variables of an Umbral game as "A=1 B=2" ↔ the env.X=… arguments that turn one into the other
        function uenvArgs(text) {
            var want = {}, args = [];
            text.trim().split(/\s+/).forEach(function (w) { var i = w.indexOf("="); if (i > 0) want[w.substring(0, i)] = w.substring(i + 1); });
            var have = uopts.env || {};
            Object.keys(have).forEach(function (k) { if (!(k in want)) args.push("env." + k + "="); });
            Object.keys(want).forEach(function (k) { if (have[k] !== want[k]) args.push("env." + k + "=" + want[k]); });
            return args;
        }
        property var    gstat: ({})
        property var    pdb: ({})           // ProtonDB summaries by appid
        property var    tools: []           // Proton versions Steam can use
        property var    gp: ({})            // profile being edited
        property var    gameArgs: []
        property string gameLog: ""
        // the last EXPORT / IMPORT result, shown in the BACKUP card ({} = nothing yet)
        property var    bkResult: ({})
        property string gameStatus: ""
        property string selGame: ""
        property string selGameId: ""
        property string selGameName: ""
        property string selGameSource: ""
        property string selGameLaunch: ""
        property string selGameCompat: ""
        property bool   selGameWrapped: false
        property var    selGameObj: ({})
        property bool   confirmJoin: false
        property var    sug: ({})           // launch options players use (ProtonDB open data)
        property var    tips: ({})          // suggestion count per appid
        property var    pdbStat: ({})       // local ProtonDB index status
        property var    shaders: ({})       // shader caches (per game + driver)
        property var    health: ({})        // gaming health checks
        property var    ups: ({})           // upscaler upgrades for the selected game
        property var    gaudit: ({})        // profiles vs this PC
        property var    fx: ({})            // visual shaders: install state + selected game
        property var    fxGames: []         // SweetFX DB games matching the search
        property string fxGameId: ""
        property var    fxPresets: []
        property string fxMsg: ""
        property string fxConfirm: ""       // anti-cheat games: second click applies
        property bool   fxActive: !!fx.current && !!win.gp.fx
        property bool   fxAnticheat: !!fx.online && fx.online.level === "anticheat"
        property var    fxCur: fx.current || ({})   // the applied look, never undefined while fx reloads
        property bool   fxReshade: fx.mode === "reshade"
        property bool   fxGame: selGameSource === "steam" || selGameSource === "umbral"
        property bool   fxUmbral: selGameSource === "umbral"
        property var    fxRsGame: fx.reshade ? fx.reshade.game : null
        property bool   fxReady: fxReshade ? (!!fx.reshade && fx.reshade.ready === true) : (fx.vkbasalt === true && fx.shadersInstalled === true)
        function openFx() {
            gameView = "fx"; fxConfirm = ""; fxTopFor = "";
            if (selGameSource === "steam" || selGameSource === "umbral") {
                fxStatProc.running = true;
                if (fxQuery.text === "" || fxLastGame !== selGame) { fxQuery.text = selGameName; fxLastGame = selGame; fxSearch(selGameName); }
            }
        }
        property string fxLastGame: ""
        property string fxScope: "game"     // game | library
        property string fxImportFile: ""    // archive picked for IMPORT
        property bool   fxGuideOpen: false  // FX: all steps listed (otherwise only the pending ones / a summary)
        property bool   fxDetails: false    // FX: executable, API and keys (advanced)
        property bool   fxAddLink: false    // FX: the win.t("save a preset page") field is open
        property string fxTopFor: ""
        function fxToTop() { fxScroll.contentItem.contentY = 0; }
        // the FX steps, from the game's real state: [done, title, how]
        property var    fxSteps: {
            var key = (fx.key || "Home").toUpperCase(), rs = fxReshade;
            return [
                [(rs ? "reshade" : "vkbasalt") === fx.recommended,
                 (rs ? "reshade" : "vkbasalt") === fx.recommended ? win.t("Route: ") + (rs ? "ReShade" : "vkBasalt")
                                                                  : win.t("Switch to ") + (fx.recommended === "reshade" ? "ReShade" : "vkBasalt"),
                 ((rs ? "reshade" : "vkbasalt") === fx.recommended ? win.t("The recommended one for this game. ") : win.t("Recommended here: ") + (fx.recommended === "reshade" ? "ReShade" : "vkBasalt") + ". ")
                 + win.t(((fx.advice || {}).reasons || [""])[0])],
                [fxReady, win.t("Install ") + (rs ? "ReShade" : "vkBasalt + shaders"),
                 rs ? win.t("Downloaded from reshade.me into your user folder, no password.") : win.t("From chaotic-aur (asks for your password) plus the standard shaders.")],
                fxUmbral
                ? [fx.wrapped === true, win.t("Launch it from Umbral"),
                   fx.wrapped ? win.t("Umbral asks the deck for the shaders/TEMPS each time it starts the game.")
                              : win.t("Needs Umbral 0.10.0 or newer (it asks the deck before launching): update Umbral.")]
                : [fx.wrapped === true, win.t("Launch it through Gaming Deck"),
                 fx.wrapped ? win.t("Its Steam launch options go through the deck, which loads the shaders.")
                            : (fx.steamRunning ? win.t("Close Steam, then USE IN STEAM.") : win.t("USE IN STEAM puts the deck in its launch options."))],
                [fxActive, win.t("Pick a look"),
                 fxActive ? win.t("Active: ") + fxCur.name + win.t(". Change it any time below.")
                          : ((fx.links || []).length
                             ? win.t("Your saved preset: ") + fx.links[0].label + win.t(" — open it, download the file, then IMPORT…")
                               + (fx.links[0].notes ? win.t(" Its guide, mapped to the deck, is under SAVED below.") : "")
                             : win.t("Below: a QUICK LOOK, a SweetFX DB preset (APPLY), or one from Nexus: SEARCH NEXUS → download it → IMPORT…"))],
                [fxActive && fx.wrapped === true && fxReady, win.t("Play and tweak"),
                 rs ? win.t("Launch the game and press ") + key + win.t(": ReShade's menu, tick/untick effects and move sliders (saved to this game). ")
                      + ((fx.effectsKey || "End") !== "None" ? (fx.effectsKey || "End").toUpperCase() + win.t(" switches all effects on/off. ") : "")
                      + win.t("Turn on Performance Mode once you like it. Screenshots (PRINT SCREEN): ") + (fx.shotsDir || "~/Pictures/ReShade") + "."
                    : win.t("Launch the game; ") + key + win.t(" turns the effects on/off to compare.")]
            ];
        }
        property int    fxStepsDone: fxSteps.filter(function (s) { return s[0]; }).length
        property var    fxImportList: []    // its presets, when there's more than one
        property var    fxScan: []          // fx scan: every game's best preset / compatibility
        property var    fxScanByKey: { var m = {}; fxScan.forEach(function (r) { m[r.key] = r; }); return m; }
        property int    fxEligible: fxScan.filter(function (r) { return r.eligible && !r.current; }).length
        function fxSearch(q) {
            if (!q || fxSearchProc.running) return;
            fxGames = []; fxPresets = []; fxGameId = ""; fxMsg = "";
            fxSearchProc.command = [scriptPath, "fx", "search", q]; fxSearchProc.running = true;
        }
        // preset list order: "new" (as SweetFX DB lists them), "downloads", "best" (downloads weighed by the review)
        property string fxSort: "new"
        function fxSorted(list, reviews, how) {
            if (how === "new") return list;
            var w = { light: 1.3, moderate: 1.0, strong: 0.6, empty: 0, old: 0 };
            function score(p) {
                if (p.shader && p.shader !== "ReShade") return -1;
                var r = reviews[p.id], d = p.downloads || 0;
                if (how === "downloads") return d;
                return d * (r ? (w[r.verdict] !== undefined ? w[r.verdict] : 0.6) : 0.8);
            }
            return list.slice().sort(function (a, b) { return score(b) - score(a) || (b.downloads || 0) - (a.downloads || 0); });
        }
        function fxLoadPresets(id) {
            fxGameId = id; fxPresets = []; fxReviews = {}; fxMsg = "Loading presets…";
            fxPresetsProc.command = [scriptPath, "fx", "presets", id]; fxPresetsProc.running = true;
        }
        // what each listed preset does (fx reviews: the most downloaded ones, cached)
        property var fxReviews: ({})
        function verdictTone(v) { return v === "light" ? "ok" : (v === "moderate" || v === "empty" || v === "old" ? "warn" : "bad"); }
        function verdictLabel(v) { return v === "light" ? win.t("LIGHT") : v === "moderate" ? win.t("MODERATE") : v === "empty" ? win.t("EMPTY") : v === "old" ? win.t("OLD FORMAT") : win.t("STRONG"); }
        function fxApply(k, label, cmd) {
            if (fxAnticheat && fxConfirm !== k) { fxConfirm = k; return; }
            fxConfirm = "";
            runGame(cmd || ["fx", "set", selGame, k], label);
        }
        property string copiedFix: ""       // fix command just copied (for feedback)
        property string confirmShader: ""   // target awaiting a second click
        property var    bench: ({})         // A/B benchmark of the selected game
        property string benchLoadedFor: ""  // game whose variants are in the editors (unsaved edits survive refreshes)
        property string pendingRun: ""      // "A"/"B": run right after the variants are saved
        property var    pfx: ({})           // Wine/Proton prefixes
        property var    pfxBackups: []
        property bool   sugExpanded: false
        property var    sugRecommended: (sug.suggestions || []).filter(function (x) { return x.recommended; })
        property var    sugOthers: (sug.suggestions || []).filter(function (x) { return x.foryou && !x.recommended; })
        property bool   gameBusy: gamesProc.running || gameProc.running || gprofProc.running

        function tierColor(t) {
            switch (t) {
                case "platinum": return "#b4c7dc";
                case "gold":     return pal.amber;
                case "silver":   return "#a6a6a6";
                case "bronze":   return "#cd7f32";
                case "borked":   return pal.bad;
                default:         return pal.dim;
            }
        }
        function gameName(id) {
            var g = games.filter(function (x) { return x.id === String(id); })[0];
            return g ? g.name : "app " + id;
        }
        function openGaming() {
            gamesProc.running = true; gstatProc.running = true; toolsProc.running = true; pdbStatProc.running = true;
            loadGameView();
        }
        function selectGame(g) {
            selGame = g.key; selGameId = g.id; selGameName = g.name; selGameSource = g.source;
            selGameLaunch = g.launch; selGameCompat = g.compat; selGameWrapped = g.wrapped; selGameObj = g;
            gameLog = ""; if (g.source === "steam" || g.source === "umbral") gprofProc.running = true;
            ups = {}; if (g.source === "steam") upsProc.running = true;
            ioInfo = {}; if (g.source === "steam" || g.source === "umbral") { ioProc.command = [scriptPath, "iosched", g.key]; ioProc.running = true; }
            uopts = {}; if (g.source === "umbral") uoptsProc.running = true;
            mods = {}; if (g.source === "steam" || g.source === "umbral") modsProc.running = true;
            sug = {}; sugExpanded = false; if (g.source === "steam") sugProc.running = true;
            if (g.new) { seenProc.command = [scriptPath, "gseen", g.key]; seenProc.running = true; }
            fx = {}; fxConfirm = ""; if (gameView === "fx") openFx();
        }
        // is a suggestion already part of the profile being edited?
        function sugApplied(x) {
            if (x.kind === "env") return (" " + gEnv.text + " ").indexOf(" " + x.token + " ") >= 0;
            if (x.kind === "arg") return (" " + gArgs.text + " ").indexOf(" " + x.token + " ") >= 0;
            if (x.token === "gamemoderun") return gp.gamemode === true;
            if (x.token === "mangohud") return gp.mangohud === true;
            return (" " + gPrefix.text + " ").indexOf(" " + x.token + " ") >= 0;
        }
        // value this profile already gives to a suggested env var ("" if unset)
        // add or remove a set of VAR=value in the ENV field (saved with SAVE / PLAY)
        function toggleEnvSet(set, on) {
            var names = Object.keys(set || {});
            var rest = gEnv.text.split(/\s+/).filter(function (e) { return e && names.indexOf(e.split("=")[0]) < 0; });
            if (!on) names.forEach(function (n) { rest.push(n + "=" + set[n]); });
            gEnv.text = rest.join(" ");
        }
        // add/remove VAR=1 in the ENV field (saved with SAVE / PLAY)
        function toggleEnv(name) {
            var rest = gEnv.text.split(/\s+/).filter(function (e) { return e && e.split("=")[0] !== name; });
            if (envValue(name) !== "1") rest.push(name + "=1");
            gEnv.text = rest.join(" ");
        }
        function envValue(name) {
            var hit = gEnv.text.split(/\s+/).filter(function (e) { return e.split("=")[0] === name; })[0];
            return hit === undefined ? null : hit.substring(name.length + 1);
        }
        function sugLabel(x, applied, mark) {
            var l = (applied ? "✓ " : mark) + x.token + "  " + x.pct + "%";
            if (x.kind === "env" && !applied) {
                var mine = envValue(x.var);
                if (mine !== null) l += win.t(" · you =") + mine;
            }
            return l;
        }
        function sugTip(x, applied) {
            var t = x.pct + win.t("% of ") + (x.basis === "similar" ? win.t("players with a GPU like yours") : (x.basis === "vendor" ? win.t("players with your GPU vendor") : "players"))
                    + win.t(" who say it works use it (") + x.n + win.t(" reports)");
            if (x.kind === "env" && x.unset !== undefined) t += "; " + x.unset + win.t("% leave it at the default");
            if (x.adapted) t += win.t("; value adapted to this PC");
            return t + (applied ? win.t(". Already in the profile.") : win.t(". Click to add, then SAVE."));
        }
        // add a suggestion to the editor (saved with SAVE, never automatically)
        function applySug(x) {
            if (sugApplied(x)) return;
            if (x.kind === "env") {
                var name = x.token.split("=")[0];
                var rest = gEnv.text.split(/\s+/).filter(function (e) { return e && e.split("=")[0] !== name; });
                gEnv.text = rest.concat([x.token]).join(" ");
            } else if (x.kind === "arg") {
                gArgs.text = (gArgs.text.trim() + " " + x.token).trim();
            } else if (x.token === "gamemoderun") { gpSet("gamemode", true); }
            else if (x.token === "mangohud") { gpSet("mangohud", true); }
            else { gPrefix.text = (gPrefix.text.trim() + " " + (x.token === "gamescope" ? "gamescope -f --" : x.token)).trim(); }
        }
        property var stHist: ({ gpuLoad: [], gpuTemp: [], cpuTemp: [], ram: [], vram: [] })
        property string confirmSched: ""    // scheduler changes that touch /etc: second click
        function durationText(sec) {
            var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
            return h > 0 ? h + " h " + m + " min" : (m > 0 ? m + " min" : sec + " s");
        }
        // STATUS is live while it's on screen
        Timer {
            interval: 3000; repeat: true
            running: win.visible && win.gameView === "status"
            onTriggered: if (!gstatProc.running) gstatProc.running = true
        }
        function playtimeText(sec) {
            if (!sec) return win.t("never played");
            var h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
            return (h > 0 ? h + " h " : "") + m + win.t(" min played");
        }
        function gpSet(k, v) { var o = Object.assign({}, gp); o[k] = v; gp = o; }
        function envString(e) {
            return Object.keys(e || {}).map(function (k) { return k + "=" + e[k]; }).join(" ");
        }
        function runGame(args, label) { gameArgs = args; gameLog = ""; gameStatus = label; confirmShader = ""; gameProc.running = true; }
        // destructive shader actions need a second click on the same button
        function shaderAction(args, key, label) {
            if (confirmShader !== key) { confirmShader = key; return; }
            runGame(args, label);
        }
        function loadBench() {
            [benchA, benchB].forEach(function (w) {
                var x = bench[w.v] || {};
                w.label = x.label || w.v; w.env = x.env || ""; w.args = x.args || "";
                w.gm = x.gamemode || ""; w.proton = x.proton || "";
            });
        }
        function saveBench(extra) {
            var a = ["bench", "set", selGame];
            [benchA, benchB].forEach(function (w) {
                a = a.concat([w.v, "label=" + w.label.trim(), "env=" + w.env.trim(), "args=" + w.args.trim(),
                              "gamemode=" + w.gm, "proton=" + w.proton]);
            });
            runGame(a.concat(extra || []), win.t("SAVING…"));
        }
        function runBench(v) { pendingRun = v; saveBench([]); }
        function pct(v) { return v === undefined || v === null ? "" : (v > 0 ? "+" : "") + v + "%"; }
        function dateOfEpoch(e) { return e ? new Date(e * 1000).toISOString().substring(0, 10) : "?"; }
        property bool pendingPlay: false
        function playGame() {
            if (selGameSource === "steam") { pendingPlay = true; saveGameProfile(); }
            else runGame(["gplay", selGame], win.t("LAUNCHING…"));
        }
        function saveGameProfile() {
            runGame(["gprofile", "set", selGame,
                     "gamemode=" + (gp.gamemode === true), "mangohud=" + (gp.mangohud === true),
                     "overlay=" + (gp.overlay === true), "ionice=" + (gp.ionice === true), "nice=" + (gp.nice || 0),
                     "env=" + gEnv.text.trim(), "prefix=" + gPrefix.text.trim(), "args=" + gArgs.text.trim()],
                    win.t("SAVING…"));
        }


        // ---- backend processes ------------------------------------------
        Process {
            id: gamesProc
            command: [win.scriptPath, "games"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try { win.games = JSON.parse(text); } catch (e) { win.games = []; }
                    if (win.fxScan.length === 0 && !fxScanProc.running) { fxScanProc.cached = true; fxScanProc.running = true; }
                    if (!gauditProc.running) gauditProc.running = true;
                    win.gameStatus = win.games.length + " GAMES";
                    // keep the selection in sync (launch options / Proton may have changed)
                    var cur = win.games.filter(function (g) { return g.key === win.selGame; })[0];
                    if (cur) { win.selGameLaunch = cur.launch; win.selGameCompat = cur.compat; win.selGameWrapped = cur.wrapped; }
                    var ids = win.games.filter(function (g) { return g.source === "steam"; }).map(function (g) { return g.id; });
                    if (ids.length > 0) {
                        pdbProc.command = [win.scriptPath, "protondb"].concat(ids); pdbProc.running = true;
                        tipsProc.command = [win.scriptPath, "gtips"].concat(ids); tipsProc.running = true;
                    }
                }
            }
        }
        Process {
            id: pdbProc
            stdout: StdioCollector { onStreamFinished: { try { win.pdb = JSON.parse(text); } catch (e) {} } }
        }
        Process {
            id: gstatProc
            command: [win.scriptPath, "gstatus"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try { win.gstat = JSON.parse(text); } catch (e) { return; }
                    // live history for the STATUS graphs (100 samples ≈ 5 min at 3 s)
                    var h = win.stHist, g = win.gstat.gpu || {}, y = win.gstat.system || {};
                    function push(a, v) { var b = a.concat([v == null ? 0 : v]); return b.length > 100 ? b.slice(b.length - 100) : b; }
                    win.stHist = {
                        gpuLoad: push(h.gpuLoad, g.load), gpuTemp: push(h.gpuTemp, g.temp), cpuTemp: push(h.cpuTemp, y.temp),
                        ram: push(h.ram, y.memTotal ? 100 * y.memUsed / y.memTotal : 0),
                        vram: push(h.vram, g.vramTotal ? 100 * g.vramUsed / g.vramTotal : 0)
                    };
                }
            }
        }
        Process {
            id: toolsProc
            command: [win.scriptPath, "compattools"]
            stdout: StdioCollector { onStreamFinished: { try { win.tools = JSON.parse(text); } catch (e) { win.tools = []; } } }
        }
        Process {
            id: gprofProc
            command: [win.scriptPath, "gprofile", "get", win.selGame]
            stdout: StdioCollector {
                onStreamFinished: {
                    try { win.gp = JSON.parse(text); } catch (e) { win.gp = {}; }
                    gEnv.text = win.envString(win.gp.env); gPrefix.text = win.gp.prefix || ""; gArgs.text = win.gp.args || "";
                }
            }
        }
        Process {
            id: gameProc
            command: [win.scriptPath].concat(win.gameArgs)
            stdout: SplitParser { onRead: (l) => win.gameLog += l + "\n" }
            stderr: SplitParser { onRead: (l) => win.gameLog += l + "\n" }
            onExited: (c, s) => {
                win.gameStatus = c === 0 ? "DONE ✓" : (c === 3 ? "CLOSE STEAM FIRST" : "FAILED · " + c);
                if (win.gameArgs[0] === "export" || win.gameArgs[0] === "gaming-import") {
                    var lines = win.gameLog.replace(/\x1b\[[0-9;]*m/g, "").trim().split("\n").filter(function (x) { return x.trim() !== ""; });
                    var saved = /Backup saved to (.+)$/.exec(lines.join("\n").split("\n").filter(function (x) { return x.indexOf("Backup saved to") >= 0; })[0] || "");
                    win.bkResult = { ok: c === 0, what: win.gameArgs[0] === "export" ? "export" : "import",
                                     file: saved ? saved[1].trim() : "", lines: lines.slice(-4) };
                }
                gamesProc.running = true; gstatProc.running = true; pdbStatProc.running = true;
                if (win.gameArgs[0] === "pdbindex" && win.selGameId) sugProc.running = true;
                if (win.gameArgs[0] === "shaderclean") shaderProc.running = true;
                // PLAY on a Steam game saves the editor first, then launches
                if (win.gameArgs[0] === "gprofile" && win.gameArgs[1] === "set" && win.pendingPlay) {
                    win.pendingPlay = false;
                    if (c === 0) { Qt.callLater(function () { win.runGame(["gplay", win.selGame], win.t("LAUNCHING…")); }); return; }
                }
                if (win.gameArgs[0] === "bench" && win.gameArgs[1] === "set" && win.pendingRun !== "") {
                    var v = win.pendingRun; win.pendingRun = "";
                    // started after this handler returns (restarting a Process from its own onExited is unsafe)
                    if (c === 0) { Qt.callLater(function () { win.runGame(["bench", "run", win.selGame, v], win.t("RUN ") + v + "…"); }); return; }
                }
                if (win.gameArgs[0] === "bench") benchProc.running = true;
                if (win.gameArgs[0] === "prefix") { pfxProc.running = true; pfxBakProc.running = true; }
                if (win.gameArgs[0] === "steamcompat") upsProc.running = true;
                if ((win.gameArgs[0] === "uset" || win.gameArgs[0] === "gaudit") && win.selGameSource === "umbral") uoptsProc.running = true;
                if (win.gameArgs[0] === "fx" || (win.gameArgs[0] === "steamwrap" && win.gameView === "fx")) fxStatProc.running = true;
                if (win.gameArgs[0] === "fx" && win.fxScope === "library") { fxScanProc.cached = false; fxScanProc.running = true; }
                if (win.selGame) gprofProc.running = true;
                if (["clean", "proton", "gaming-import", "export"].indexOf(win.gameArgs[0]) >= 0) { protonProc.running = true; gcleanProc.running = true; }
                if (win.gameArgs[0] === "selfupdate") { versionProc.running = true; selfcheckProc.running = true; }
            }
        }
        Process {
            id: sugProc
            command: [win.scriptPath, "gsuggest", win.selGameId]
            stdout: StdioCollector { onStreamFinished: { try { win.sug = JSON.parse(text); } catch (e) { win.sug = {}; } } }
        }
        Process {
            id: tipsProc
            stdout: StdioCollector { onStreamFinished: { try { win.tips = JSON.parse(text); } catch (e) {} } }
        }
        Process {
            id: pdbStatProc
            command: [win.scriptPath, "pdbindex", "status"]
            stdout: StdioCollector { onStreamFinished: { try { win.pdbStat = JSON.parse(text); } catch (e) { win.pdbStat = {}; } } }
        }
        Process { id: seenProc }
        Process {
            id: pfxProc
            command: [win.scriptPath, "prefixes"]
            stdout: StdioCollector { onStreamFinished: { try { win.pfx = JSON.parse(text); } catch (e) { win.pfx = {}; } } }
        }
        Process {
            id: pfxBakProc
            command: [win.scriptPath, "prefix", "backups"]
            stdout: StdioCollector { onStreamFinished: { try { win.pfxBackups = JSON.parse(text); } catch (e) { win.pfxBackups = []; } } }
        }
        Process {
            id: pfxOpenProc
            command: ["xdg-open", win.home + "/gaming-deck-backups/prefixes"]
        }
        Process {
            id: benchProc
            command: [win.scriptPath, "bench", "get", win.selGame]
            stdout: StdioCollector {
                onStreamFinished: {
                    try { win.bench = JSON.parse(text); } catch (e) { win.bench = {}; }
                    if (win.benchLoadedFor !== win.selGame) { win.loadBench(); win.benchLoadedFor = win.selGame; }
                    benchChart.requestPaint();
                }
            }
        }
        Process {
            id: upsProc
            command: [win.scriptPath, "upscale", win.selGame]
            stdout: StdioCollector { onStreamFinished: { try { win.ups = JSON.parse(text); } catch (e) { win.ups = {}; } } }
        }
        Process {
            id: gauditProc
            command: [win.scriptPath, "gaudit"]
            stdout: StdioCollector { onStreamFinished: { try { win.gaudit = JSON.parse(text); } catch (e) { win.gaudit = {}; } } }
        }
        Process {
            id: healthProc
            command: [win.scriptPath, "health"]
            stdout: StdioCollector { onStreamFinished: { try { win.health = JSON.parse(text); } catch (e) { win.health = {}; } } }
        }
        Process { id: fixCopyProc }
        Process {
            id: langProc
            running: true
            command: [win.scriptPath, "uilang"]
            stdout: StdioCollector { onStreamFinished: { var l = text.trim(); if (l === "es" || l === "en") win.lang = l; } }
        }
        Process { id: langSaveProc }
        Process {
            id: modsProc
            command: [win.scriptPath, "mods", win.selGame]
            stdout: StdioCollector { onStreamFinished: { try { win.mods = JSON.parse(text); } catch (e) { win.mods = {}; } } }
        }
        Process {
            id: uoptsProc
            command: [win.scriptPath, "uopts", win.selGame]
            stdout: StdioCollector { onStreamFinished: { try { win.uopts = JSON.parse(text); } catch (e) { win.uopts = {}; } } }
        }
        Process {
            id: ioProc
            stdout: StdioCollector { onStreamFinished: { try { win.ioInfo = JSON.parse(text); } catch (e) { win.ioInfo = {}; } } }
        }
        Process {
            id: fxStatProc
            command: [win.scriptPath, "fx", "status", win.selGame]
            stdout: StdioCollector {
                onStreamFinished: {
                    try { win.fx = JSON.parse(text); } catch (e) { win.fx = {}; }
                    // a new game (or the tab just opened) starts at the top: loading content can leave it scrolled
                    if (win.fxTopFor !== win.selGame) { win.fxTopFor = win.selGame; Qt.callLater(win.fxToTop); }
                }
            }
        }
        Process {
            id: fxPickProc
            command: [win.scriptPath, "pickfile", win.t("Choose a downloaded ReShade preset"), "@downloads",
                      "ReShade preset (zip, 7z, rar, ini) | *.zip *.7z *.rar *.ini *.txt"]
            stdout: StdioCollector {
                onStreamFinished: {
                    var f = text.trim(); if (!f) return;
                    win.fxImportFile = f; win.fxImportList = []; win.fxMsg = "Reading " + f.replace(/^.*\//, "") + "…";
                    fxImpListProc.command = [win.scriptPath, "fx", "importlist", f]; fxImpListProc.running = true;
                }
            }
        }
        Process {
            id: fxImpListProc
            stdout: StdioCollector {
                onStreamFinished: {
                    var l = []; try { l = JSON.parse(text); } catch (e) { }
                    if (l.length === 0) { win.fxMsg = "No ReShade preset in that file (it needs a Techniques= line)."; return; }
                    if (l.length === 1) {
                        win.fxMsg = "";
                        win.fxApply("file:" + win.fxImportFile, win.t("IMPORTING PRESET…"), ["fx", "import", win.selGame, win.fxImportFile]);
                    } else { win.fxImportList = l; win.fxMsg = l.length + " presets in this file: pick one"; }
                }
            }
        }
        Process {
            id: fxScanProc
            property bool cached: false
            command: [win.scriptPath, "fx", "scan"].concat(cached ? ["--cached"] : [])
            stdout: StdioCollector { onStreamFinished: { try { win.fxScan = JSON.parse(text); } catch (e) { } } }
        }
        Process {
            id: fxSearchProc
            stdout: StdioCollector {
                onStreamFinished: {
                    try { win.fxGames = JSON.parse(text); } catch (e) { win.fxGames = []; }
                    if (win.fxGames.length === 0) win.fxMsg = "No game with that name on SweetFX Settings DB: try another name, or use a quick look.";
                    else {
                        // the SweetFX game the active preset came from, when it's among the results
                        var g = win.fxGames.filter(function (x) { return x.id === win.fxCur.sfxGame; })[0];
                        win.fxLoadPresets((g || win.fxGames[0]).id);
                    }
                }
            }
        }
        Process {
            id: fxReviewsProc
            stdout: StdioCollector { onStreamFinished: { try { win.fxReviews = JSON.parse(text); } catch (e) { win.fxReviews = {}; } } }
        }
        Process {
            id: fxPresetsProc
            stdout: StdioCollector {
                onStreamFinished: {
                    try { win.fxPresets = JSON.parse(text); } catch (e) { win.fxPresets = []; }
                    win.fxMsg = win.fxPresets.length === 0 ? "This game has no presets yet." : win.fxPresets.length + " presets";
                    Qt.callLater(win.fxToTop);
                    if (win.fxPresets.length) { fxReviewsProc.command = [win.scriptPath, "fx", "reviews", win.fxGameId]; fxReviewsProc.running = true; }
                }
            }
        }
        Timer { id: copiedTimer; interval: 1800; onTriggered: win.copiedFix = "" }
        Process {
            id: shaderProc
            command: [win.scriptPath, "shadercache"]
            stdout: StdioCollector { onStreamFinished: { try { win.shaders = JSON.parse(text); } catch (e) { win.shaders = {}; } } }
        }

        Process {
            id: versionProc
            command: [win.scriptPath, "version"]
            stdout: StdioCollector { onStreamFinished: { var m = text.match(/^SHORT=(.*)$/m); win.deckVersion = m ? m[1] : ""; } }
        }
        Process {
            id: selfcheckProc
            command: [win.scriptPath, "selfcheck"]
            stdout: StdioCollector { onStreamFinished: { try { win.deckNew = JSON.parse(text); } catch (e) { win.deckNew = {}; } } }
        }
        Process {
            id: protonProc
            command: [win.scriptPath, "proton", "status"]
            stdout: StdioCollector { onStreamFinished: { try { win.proton = JSON.parse(text); } catch (e) { win.proton = {}; } } }
        }
        Process {
            id: gcleanProc
            command: [win.scriptPath, "cleanscan"]
            stdout: StdioCollector { onStreamFinished: { try { win.gclean = JSON.parse(text); } catch (e) { win.gclean = []; } } }
        }
        Process {
            id: importPickProc
            command: [win.scriptPath, "pickfile", win.t("Choose a Gaming Deck backup (.json)")]
            stdout: StdioCollector { onStreamFinished: { var p = text.trim(); if (p) win.runGame(["gaming-import", p], win.t("IMPORTING…")); } }
        }


        // ---- reusable bits ----------------------------------------------
        // hover hint in the deck's colours (Qt's default tooltip is a white box)
        component Tip: ToolTip {
            id: tipc
            delay: 450
            padding: 7
            width: Math.min(380, tipText.implicitWidth + leftPadding + rightPadding)
            contentItem: Text {
                id: tipText
                text: tipc.text; wrapMode: Text.WordWrap
                color: pal.text; font.family: win.mono; font.pixelSize: 10
            }
            background: Rectangle { color: pal.cardHi; border.color: pal.accent; border.width: 1; radius: 6 }
        }
        // a fix command, shown and copied, never run
        component FixLine: RowLayout {
            property string cmd
            spacing: 6
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: fixTxt.implicitHeight + 10
                radius: 4; color: pal.logBg; border.color: pal.border; border.width: 1
                Text {
                    id: fixTxt
                    anchors.fill: parent; anchors.margins: 5
                    text: cmd === "reboot" ? win.t("Restart the PC") : "$ " + cmd
                    wrapMode: Text.WrapAnywhere
                    color: pal.sky; font.family: win.mono; font.pixelSize: 10
                }
            }
            Chip {
                visible: cmd !== "reboot"
                label: win.copiedFix === cmd ? win.t("COPIED ✓") : win.t("COPY")
                tint: pal.ok; active: win.copiedFix === cmd
                onClicked: {
                    fixCopyProc.command = ["wl-copy", "--", cmd];
                    fixCopyProc.running = true;
                    win.copiedFix = cmd; copiedTimer.restart();
                }
            }
        }
        component Section: RowLayout {
            property string label
            property string info: ""
            spacing: 9
            Rectangle { width: 7; height: 7; color: pal.accent; Layout.alignment: Qt.AlignVCenter }
            Text {
                text: label
                color: pal.text; font.family: win.mono
                font.pixelSize: 12; font.letterSpacing: 4; font.bold: true
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                visible: info !== ""
                text: info; elide: Text.ElideLeft
                color: pal.dim; font.family: win.mono
                font.pixelSize: 12; font.letterSpacing: 2
            }
        }

        component ActBtn: Item {
            id: ab
            property string glyph
            property string label
            property bool boxed: false
            property bool on: true
            signal clicked
            Layout.fillWidth: true
            implicitHeight: col.implicitHeight
            opacity: on ? 1.0 : 0.3

            ColumnLayout {
                id: col
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 40; implicitHeight: 40; radius: 8
                    color: ab.boxed && ab.on ? pal.cardHi : "transparent"
                    border.color: ab.boxed && ab.on ? pal.accent : "transparent"
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: ab.glyph; font.family: win.mono; font.pixelSize: 18
                        color: ab.boxed && ab.on ? pal.accentHi : pal.text
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: ab.label; color: pal.dim; font.family: win.mono
                    font.pixelSize: 10; font.letterSpacing: 2
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: ab.on
                cursorShape: Qt.PointingHandCursor
                onClicked: ab.clicked()
            }
        }

        component BarSep: Rectangle { width: 1; Layout.preferredHeight: 46; color: pal.border }
        // one variant of an A/B benchmark
        component BenchVariant: Rectangle {
            id: bv
            property string v
            property color tint
            property alias label: bvLabel.text
            property alias env: bvEnv.text
            property alias args: bvArgs.text
            property string gm: ""        // "", "true", "false"
            property string proton: ""    // "" = as is
            Layout.fillWidth: true
            implicitHeight: bvCol.implicitHeight + 16
            radius: 8; color: pal.card; border.width: 1; border.color: tint
            ColumnLayout {
                id: bvCol
                anchors.fill: parent; anchors.margins: 8; spacing: 6
                RowLayout {
                    spacing: 6
                    Text { text: bv.v; color: bv.tint; font.family: win.mono; font.pixelSize: 13; font.bold: true }
                    Field { id: bvLabel; Layout.fillWidth: true; font.pixelSize: 11; placeholderText: win.t("name") }
                }
                Field { id: bvEnv; Layout.fillWidth: true; font.pixelSize: 10; placeholderText: win.t("extra env: VAR=1 VAR2=x") }
                Field { id: bvArgs; Layout.fillWidth: true; font.pixelSize: 10; placeholderText: win.t("args (replace the profile's)") }
                Flow {
                    Layout.fillWidth: true; spacing: 4
                    Text { text: "GAMEMODE"; color: pal.dim; font.family: win.mono; font.pixelSize: 8; height: 22; verticalAlignment: Text.AlignVCenter }
                    Repeater {
                        model: [["", win.t("PROFILE")], ["true", "ON"], ["false", "OFF"]]
                        delegate: Chip { required property var modelData; label: modelData[1]; implicitHeight: 22
                                         active: bv.gm === modelData[0]; onClicked: bv.gm = modelData[0] }
                    }
                }
                Flow {
                    Layout.fillWidth: true; spacing: 4
                    Text { text: "PROTON"; color: pal.dim; font.family: win.mono; font.pixelSize: 8; height: 22; verticalAlignment: Text.AlignVCenter }
                    Repeater {
                        model: [{ name: "", display: win.t("AS IS") }].concat(win.tools)
                        delegate: Chip { required property var modelData; label: modelData.display; implicitHeight: 22
                                         active: bv.proton === modelData.name; onClicked: bv.proton = modelData.name }
                    }
                }
            }
        }


        // small toggle / button chip
        component Chip: Rectangle {
            id: chip
            property string label
            property bool active: false
            property bool on: true
            property color tint: pal.accent
            property string tip: ""
            signal clicked
            implicitWidth: ct.implicitWidth + 16
            implicitHeight: 26
            radius: 5
            opacity: on ? 1.0 : 0.35
            color: active ? pal.cardHi : "transparent"
            border.color: active ? tint : pal.border
            border.width: 1
            Text {
                id: ct
                anchors.centerIn: parent
                text: chip.label; font.family: win.mono; font.pixelSize: 9
                font.bold: true; font.letterSpacing: 1
                color: chip.active ? chip.tint : pal.dim
            }
            MouseArea {
                id: chipMa
                anchors.fill: parent; enabled: chip.on; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: chip.clicked()
            }
            Tip { visible: chip.tip !== "" && chipMa.containsMouse; text: chip.tip }
        }

        // source badge
        component Badge: Rectangle {
            property string label
            property color tint: pal.accent
            width: 62; height: 20; radius: 4
            color: "transparent"
            border.color: tint; border.width: 1
            Text {
                anchors.centerIn: parent
                text: label.toUpperCase(); color: tint
                font.family: win.mono; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1
            }
        }

        component Field: TextField {
            placeholderTextColor: pal.dim
            color: pal.text; font.family: win.mono; font.pixelSize: 12; leftPadding: 10
            background: Rectangle { color: "transparent"; border.color: pal.border; border.width: 1; radius: 6 }
        }

        // small boxed button (row actions)
        // takes the shaders off the selected game: red, with a bin, and a second click to confirm
        component FxRemoveBtn: Rectangle {
            id: frb
            property bool armed: false
            implicitWidth: frbRow.implicitWidth + 22; implicitHeight: 28
            radius: 6; color: armed ? Qt.rgba(0.98, 0.44, 0.52, 0.18) : "transparent"
            border.width: 1; border.color: pal.bad
            opacity: win.gameBusy ? 0.4 : 1.0
            Timer { id: frbDisarm; interval: 4000; onTriggered: frb.armed = false }
            RowLayout {
                id: frbRow; anchors.centerIn: parent; spacing: 6
                Text { text: "\uf1f8"; color: pal.bad; font.family: win.mono; font.pixelSize: 12 }
                Text {
                    text: frb.armed ? win.t("SURE? CLICK AGAIN") : win.t("REMOVE SHADERS")
                    color: pal.bad; font.family: win.mono; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1
                }
            }
            MouseArea {
                id: frbMa; anchors.fill: parent; enabled: !win.gameBusy; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!frb.armed) { frb.armed = true; frbDisarm.restart(); return; }
                    frb.armed = false;
                    win.runGame(["fx", "set", win.selGame, "off"], win.t("TURNING OFF…"));
                }
            }
            Tip { visible: frbMa.containsMouse && !frb.armed; text: win.t("Remove the shaders from this game") }
        }
        component MiniBtn: Rectangle {
            id: mb
            property string label
            property bool on: true
            property bool primary: true
            property color tint: pal.accent
            signal clicked
            // never narrower than its text (Spanish labels are longer); a fixed width
            // given by a layout still fits: the text shrinks a little as a last resort
            implicitWidth: Math.max(76, mbTxt.implicitWidth + 18)
            width: implicitWidth; height: 30; radius: 6
            color: primary && on ? pal.cardHi : "transparent"
            border.color: primary && on ? tint : pal.border
            border.width: 1
            opacity: on ? 1.0 : 0.4
            Text {
                id: mbTxt
                anchors.centerIn: parent
                width: Math.min(implicitWidth, mb.width - 8)
                horizontalAlignment: Text.AlignHCenter
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: 6
                text: mb.label
                color: mb.primary && mb.on ? pal.accentHi : pal.dim
                font.family: win.mono; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1
            }
            MouseArea {
                anchors.fill: parent; enabled: mb.on
                cursorShape: Qt.PointingHandCursor
                onClicked: mb.clicked()
            }
        }

        component LogBox: Rectangle {
            id: lb
            property string content: ""
            property string placeholder: "// log output"
            property int base: 170
            property bool expanded: false
            Layout.preferredHeight: expanded ? Math.max(base * 2.5, 420) : base
            Layout.minimumHeight: 60
            radius: 8; color: pal.logBg
            border.color: pal.border; border.width: 1
            ScrollView {
                anchors.fill: parent
                anchors.margins: 8
                anchors.rightMargin: 30
                clip: true
                TextArea {
                    readOnly: true
                    text: lb.content || win.t(lb.placeholder)
                    color: lb.content ? pal.text : pal.dim
                    font.family: win.mono; font.pixelSize: 11
                    wrapMode: TextArea.WordWrap
                    background: null
                    onTextChanged: cursorPosition = length
                }
            }
            // expand / shrink
            Rectangle {
                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 6
                width: 22; height: 22; radius: 4
                color: expandMa.containsMouse ? pal.cardHi : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: lb.expanded ? "" : ""
                    color: pal.dim; font.family: win.mono; font.pixelSize: 11
                }
                MouseArea {
                    id: expandMa
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: lb.expanded = !lb.expanded
                }
            }
        }

        // centered placeholder for empty panels
        component EmptyHint: ColumnLayout {
            property string title
            property string sub: ""
            anchors.centerIn: parent
            spacing: 8
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "力"; color: "#141127"; font.pixelSize: 96; font.bold: true
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: title; color: pal.dim; font.family: win.mono; font.pixelSize: 12; font.letterSpacing: 2
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: sub !== ""
                text: sub; color: pal.dim; font.family: win.mono; font.pixelSize: 10
            }
        }

        component Hint: Text {
            Layout.fillWidth: true
            color: pal.dim; font.family: win.mono; font.pixelSize: 10; wrapMode: Text.WordWrap
        }


        // small rounded tag (covers, banner)
        component Pill: Rectangle {
            property string label
            property color tint: pal.accent
            implicitWidth: pillTxt.implicitWidth + 12; implicitHeight: 16; radius: 8
            color: Qt.rgba(tint.r, tint.g, tint.b, 0.16); border.width: 1; border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.55)
            Text {
                id: pillTxt; anchors.centerIn: parent; text: parent.label; color: parent.tint
                font.family: win.mono; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1
            }
        }

        // ---- layout: sidebar · content -----------------------------------
        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---- sidebar ----
            Rectangle {
                Layout.fillHeight: true; Layout.preferredWidth: 214
                color: pal.side
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: pal.border }
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 18; spacing: 5
                    // brand
                    RowLayout {
                        spacing: 12
                        Image {
                            source: "file://" + win.home + "/.local/share/icons/hicolor/scalable/apps/gaming-deck.svg"
                            sourceSize.width: 88; sourceSize.height: 88
                            Layout.preferredWidth: 44; Layout.preferredHeight: 44
                        }
                        ColumnLayout {
                            spacing: 0
                            Text { text: "GAMING"; color: pal.accent; font.family: win.mono; font.pixelSize: 14; font.bold: true; font.letterSpacing: 5 }
                            Text { text: "DECK"; color: pal.text; font.family: win.mono; font.pixelSize: 14; font.bold: true; font.letterSpacing: 5 }
                        }
                    }
                    Item { Layout.preferredHeight: 18 }
                    Repeater {
                        model: win.sections
                        delegate: Rectangle {
                            required property var modelData
                            property bool sel: win.gameView === modelData[0] || (modelData[0] === "library" && win.gameView === "game")
                            Layout.fillWidth: true; Layout.preferredHeight: 40; radius: 10
                            color: sel ? pal.cardHi : (navMa.containsMouse ? pal.card : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Rectangle {
                                visible: parent.sel; width: 3; height: 20; radius: 2
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: pal.accent }
                                    GradientStop { position: 1.0; color: pal.violet }
                                }
                            }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 10; spacing: 12
                                Text {
                                    text: modelData[1]; color: parent.parent.sel ? pal.accent : pal.dim
                                    font.family: win.mono; font.pixelSize: 15
                                    Layout.preferredWidth: 20; horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    text: win.t(modelData[2]); color: parent.parent.sel ? pal.text : pal.dim
                                    font.family: win.mono; font.pixelSize: 11; font.bold: true; font.letterSpacing: 2
                                }
                            }
                            MouseArea {
                                id: navMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: win.goSection(modelData[0])
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    // a newer Gaming Deck on GitHub
                    Rectangle {
                        visible: !!win.deckNew.new
                        Layout.fillWidth: true; Layout.preferredHeight: 34; radius: 10
                        color: Qt.rgba(pal.amber.r, pal.amber.g, pal.amber.b, 0.10); border.width: 1; border.color: pal.amber
                        Text {
                            anchors.centerIn: parent; text: win.t("● NEW VERSION"); color: pal.amber
                            font.family: win.mono; font.pixelSize: 10; font.bold: true; font.letterSpacing: 2
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.gameView = "maint" }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        MiniBtn {
                            Layout.fillWidth: true; height: 32; label: "STEAM"; primary: false
                            onClicked: steamOpenProc.running = true
                        }
                        MiniBtn {
                            width: 38; height: 32; label: ""; primary: false; on: !win.gameBusy
                            onClicked: { win.gameLog = ""; win.openGaming(); }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        // ESP | ENG
                        Row {
                            spacing: 0
                            Repeater {
                                model: [["es", "ESP"], ["en", "ENG"]]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: langTxt.implicitWidth + 14; height: 20; radius: 4
                                    color: win.lang === modelData[0] ? pal.accent : "transparent"
                                    border.color: pal.border; border.width: win.lang === modelData[0] ? 0 : 1
                                    Text {
                                        id: langTxt; anchors.centerIn: parent; text: modelData[1]
                                        color: win.lang === modelData[0] ? pal.bg : pal.dim
                                        font.family: win.mono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: if (win.lang !== modelData[0]) { win.lang = modelData[0]; langSaveProc.command = [win.scriptPath, "uilang", modelData[0]]; langSaveProc.running = true; }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: win.deckVersion; color: pal.dim; font.family: win.mono; font.pixelSize: 9 }
                    }
                }
            }

            // ---- content ----
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.margins: 24
                spacing: 14
                // section title
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    visible: win.gameView !== "game"
                    Text {
                        text: win.sectionTitle(win.gameView); color: pal.text
                        font.family: win.mono; font.pixelSize: 20; font.bold: true; font.letterSpacing: 4
                    }
                    Rectangle {
                        Layout.preferredWidth: 46; Layout.preferredHeight: 3; radius: 2; Layout.alignment: Qt.AlignVCenter
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: pal.accent }
                            GradientStop { position: 1.0; color: pal.violet }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: win.t(win.gameStatus); color: pal.dim; font.family: win.mono
                        font.pixelSize: 11; font.letterSpacing: 2; elide: Text.ElideLeft
                    }
                }

                // ---- LIBRARY ----
                // profiles that don't fit this PC (moved from the other one via BACKUP)
                Rectangle {
                    Layout.fillWidth: true
                    visible: win.gameView === "library" && (win.gaudit.issues || []).length > 0
                    implicitHeight: auditCol.implicitHeight + 16
                    radius: 8; color: "#1a150c"; border.color: pal.amber; border.width: 1
                    ColumnLayout {
                        id: auditCol
                        anchors.fill: parent; anchors.margins: 8; spacing: 4
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                color: pal.amber; font.family: win.mono; font.pixelSize: 11; font.bold: true
                                text: win.t("CHECK FOR THIS PC — ") + (win.gaudit.issues || []).length + win.t(" setting(s) don't fit this ")
                                      + String(win.gaudit.vendor || "").toUpperCase() + win.t(" GPU or aren't set up here yet")
                            }
                            MiniBtn {
                                width: Math.max(90, implicitWidth); height: 28; label: win.t("FIX ALL"); on: !win.gameBusy
                                onClicked: win.runGame(["gaudit", "fix", "all"], win.t("ADJUSTING PROFILES…"))
                            }
                        }
                        Repeater {
                            model: win.gaudit.issues || []
                            delegate: Text {
                                required property var modelData
                                Layout.fillWidth: true; elide: Text.ElideRight
                                color: pal.text; font.family: win.mono; font.pixelSize: 10
                                text: "· " + win.gameName(String(modelData.key).replace(/^[a-z]+:/, "")) + ": "
                                      + (modelData.kind === "env" ? modelData.var + win.t(" is ") + (modelData.vendor === "mesa" ? "Mesa" : modelData.vendor.toUpperCase()) + win.t("-only → remove")
                                         : modelData.kind === "reshade" ? win.t("ReShade isn't installed in its folder on this PC → set it up")
                                         : modelData.kind === "shader" ? modelData.file + (modelData.pack ? win.t(" is missing here → install ") + modelData.pack.name
                                                                                                          : win.t(" is missing and isn't in any known pack → import the preset again"))
                                         : modelData.kind === "gamemode" ? win.t("GAMEMODE is on but GameMode isn't installed → install it")
                                         : win.t("vkBasalt isn't installed here → FX → INSTALL"))
                            }
                        }
                    }
                }
                // all the games, as covers (Steam's artwork; Umbral's own covers)
                GridView {
                    id: coverGrid
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 200
                    visible: win.gameView === "library"
                    clip: true; model: win.games
                    boundsBehavior: Flickable.StopAtBounds
                    property int cols: Math.max(2, Math.floor(width / 178))
                    cellWidth: Math.floor(width / cols); cellHeight: Math.round(cellWidth * 1.5)
                    ScrollBar.vertical: ScrollBar {}
                    EmptyHint {
                        visible: win.games.length === 0
                        title: gamesProc.running ? win.t("READING YOUR LIBRARY…") : win.t("NO GAMES FOUND")
                        sub: gamesProc.running ? "" : win.t("installed Steam games and Umbral games show up here")
                    }
                    delegate: Item {
                        required property var modelData
                        width: coverGrid.cellWidth; height: coverGrid.cellHeight
                        Rectangle {
                            id: coverCard
                            anchors.fill: parent; anchors.margins: 7
                            radius: 12; clip: true; color: pal.card
                            border.width: coverMa.containsMouse || win.selGame === modelData.key ? 2 : 1
                            border.color: coverMa.containsMouse ? pal.accent : (win.selGame === modelData.key ? pal.violet : pal.border)
                            scale: coverMa.containsMouse ? 1.035 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            Image {
                                anchors.fill: parent; anchors.margins: 1
                                source: modelData.cover ? "file://" + modelData.cover : ""
                                fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 360
                            }
                            // no artwork: the name on a soft gradient
                            Rectangle {
                                anchors.fill: parent; visible: !modelData.cover; radius: 12
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#1b2540" }
                                    GradientStop { position: 1.0; color: "#0c0e16" }
                                }
                                Text {
                                    anchors.centerIn: parent; width: parent.width - 24
                                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                                    text: modelData.name; color: pal.text; font.pixelSize: 15; font.bold: true
                                }
                            }
                            // bottom shade with the name and tags
                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                height: parent.height * 0.45; radius: 12
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#0007080d" }
                                    GradientStop { position: 1.0; color: "#f207080d" }
                                }
                            }
                            ColumnLayout {
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.margins: 10; spacing: 5
                                Text {
                                    Layout.fillWidth: true; visible: !!modelData.cover
                                    text: modelData.name; color: pal.text; elide: Text.ElideRight
                                    font.pixelSize: 12; font.bold: true
                                }
                                Flow {
                                    Layout.fillWidth: true; spacing: 4
                                    Pill { label: modelData.source === "umbral" ? "UMBRAL" : "STEAM"; tint: modelData.source === "umbral" ? pal.pink : pal.sky }
                                    Pill {
                                        visible: !!(win.pdb[modelData.id] || {}).tier
                                        label: String((win.pdb[modelData.id] || {}).tier || "").toUpperCase(); tint: win.tierColor((win.pdb[modelData.id] || {}).tier)
                                    }
                                    Pill { visible: !!(win.fxScanByKey[modelData.key] || {}).current; label: "FX"; tint: pal.accent }
                                    Pill { visible: modelData.new === true; label: win.t("NEW"); tint: pal.amber }
                                }
                            }
                            MouseArea {
                                id: coverMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { win.selectGame(modelData); win.gameView = "game"; }
                            }
                        }
                    }
                }

                // ---- GAME PAGE: the game's banner, then its profile ----
                Flickable {
                    id: gamePage
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: win.gameView === "game" && win.selGame !== ""
                    clip: true; contentWidth: width; contentHeight: gameCol.implicitHeight + 8
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    ColumnLayout {
                        id: gameCol
                        width: gamePage.width - 14; spacing: 12

                        // banner: Steam's hero image (or the cover), the logo, PLAY
                        Rectangle {
                            id: heroBox
                            Layout.fillWidth: true; Layout.preferredHeight: 230
                            radius: 14; clip: true; color: pal.card; border.color: pal.border; border.width: 1
                            property var g: win.selGameObj || ({})
                            Image {
                                anchors.fill: parent; anchors.margins: 1
                                source: heroBox.g.hero ? "file://" + heroBox.g.hero : (heroBox.g.cover ? "file://" + heroBox.g.cover : "")
                                fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 1400
                                opacity: heroBox.g.hero ? 1.0 : 0.35
                            }
                            Rectangle {
                                anchors.fill: parent; radius: 14
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#e807080d" }
                                    GradientStop { position: 0.55; color: "#7007080d" }
                                    GradientStop { position: 1.0; color: "#1007080d" }
                                }
                            }
                            Chip {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 14
                                label: "←  " + win.t("LIBRARY"); onClicked: win.gameView = "library"
                            }
                            ColumnLayout {
                                anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 22
                                width: parent.width * 0.6; spacing: 10
                                Image {
                                    visible: !!heroBox.g.logo
                                    source: heroBox.g.logo ? "file://" + heroBox.g.logo : ""
                                    fillMode: Image.PreserveAspectFit; asynchronous: true
                                    Layout.preferredWidth: 340; Layout.preferredHeight: 96
                                    horizontalAlignment: Image.AlignLeft; verticalAlignment: Image.AlignBottom
                                    sourceSize.width: 680
                                }
                                Text {
                                    visible: !heroBox.g.logo
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    text: win.selGameName; color: pal.text; font.pixelSize: 28; font.bold: true
                                }
                                Flow {
                                    Layout.fillWidth: true; spacing: 6
                                    Pill { label: win.selGameSource === "umbral" ? "UMBRAL" : "STEAM"; tint: win.selGameSource === "umbral" ? pal.pink : pal.sky }
                                    Pill {
                                        visible: !!(win.pdb[win.selGameId] || {}).tier
                                        label: "PROTONDB " + String((win.pdb[win.selGameId] || {}).tier || "").toUpperCase(); tint: win.tierColor((win.pdb[win.selGameId] || {}).tier)
                                    }
                                    Pill { visible: !!heroBox.g.size; label: win.human(heroBox.g.size); tint: pal.dim }
                                    Pill { visible: heroBox.g.wrapped === true; label: win.t("◆ LAUNCHED THROUGH THE DECK"); tint: pal.accent }
                                }
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 22
                                width: playTxt.implicitWidth + 44; height: 44; radius: 22
                                opacity: win.gameBusy ? 0.5 : 1.0
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: pal.accent }
                                    GradientStop { position: 1.0; color: pal.violet }
                                }
                                Text {
                                    id: playTxt; anchors.centerIn: parent
                                    text: "▶  " + win.t("PLAY"); color: pal.bg
                                    font.family: win.mono; font.pixelSize: 13; font.bold: true; font.letterSpacing: 3
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: !win.gameBusy
                                    onClicked: win.playGame()
                                }
                            }
                        }


                    // header: game + ProtonDB verdict
                    RowLayout {
                        Layout.fillWidth: true; spacing: 9
                        Rectangle { width: 7; height: 7; color: pal.accent; Layout.alignment: Qt.AlignVCenter }
                        Text {
                            text: win.selGameSource === "steam" ? win.t("PROFILE") : win.t("GAME")
                            color: pal.text; font.family: win.mono; font.pixelSize: 12; font.letterSpacing: 4; font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: win.selGameName + (win.selGameSource === "steam" && !win.gp.custom ? win.t("  · default profile") : "")
                            color: pal.dim; font.family: win.mono; font.pixelSize: 11
                        }
                        Text {
                            id: pdbTxt
                            visible: win.selGameSource === "steam" && !!(win.pdb[win.selGameId] || {}).total
                            property var d: win.pdb[win.selGameId] || {}
                            text: String(d.tier || "").toUpperCase() + " · " + d.total + win.t(" reports ↗")
                            color: win.tierColor(d.tier); font.family: win.mono; font.pixelSize: 10; font.bold: true
                            font.underline: pdbMa.containsMouse
                            MouseArea {
                                id: pdbMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally("https://www.protondb.com/app/" + win.selGameId)
                            }
                            Tip { visible: pdbMa.containsMouse; text: win.t("ProtonDB: score ") + pdbTxt.d.score + win.t(" · trending ") + pdbTxt.d.trendingTier
                                          + win.t(" · confidence ") + pdbTxt.d.confidence + win.t(". Click to open.") }
                        }
                    }

                    // Umbral games: their options live in Umbral (edited here with Umbral 0.12+)
                    Rectangle {
                        Layout.fillWidth: true
                        visible: win.selGameSource === "umbral"
                        implicitHeight: umbCol.implicitHeight + 20
                        radius: 8; color: pal.card; border.color: pal.border; border.width: 1
                        ColumnLayout {
                            id: umbCol
                            anchors.fill: parent; anchors.margins: 10; spacing: 4
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                color: pal.text; font.family: win.mono; font.pixelSize: 11
                                text: (win.selGameObj.umbralKind === "battlenet" ? win.t("Battle.net client")
                                       : win.selGameObj.umbralKind === "blizzard" ? win.t("Battle.net game")
                                       : win.selGameObj.umbralKind === "emulator" ? win.t("ROM (emulator)")
                                       : win.selGameObj.umbralKind === "scummvm" ? win.t("ScummVM game") : win.t("Own game"))
                                      // emulators and ScummVM run natively: no Wine prefix
                                      + (win.selGameObj.prefixName ? "  ·  " + win.selGameObj.prefixName + " prefix (" + (win.selGameObj.compat || "?") + ")" : "")
                                      + "  ·  " + win.playtimeText(win.selGameObj.playtime)
                                      + (win.selGameObj.lastPlayed ? win.t("  ·  last ") + String(win.selGameObj.lastPlayed).substring(0, 10) : "")
                            }
                            Text {
                                Layout.fillWidth: true; elide: Text.ElideMiddle; visible: !!win.selGameObj.exe
                                color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                text: String(win.selGameObj.exe || "").replace(win.home, "~")
                            }
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                text: win.uopts.effective
                                      ? win.t("Saved in Umbral itself (it applies them at once if it's open). A · means it comes from the prefix; Battle.net's options are its prefix's.")
                                      : win.t("Launch options are set in Umbral. Gaming Deck adds TEMPS and shaders when Umbral 0.10.0+ starts the game.")
                            }
                            // Umbral 0.12+: its options, edited here (umbral --set)
                            RowLayout {
                                visible: !!win.uopts.effective; spacing: 6
                                Repeater {
                                    model: [["gamemode", "GAMEMODE"], ["mangohud", "MANGOHUD"], ["wayland", "WAYLAND"]]
                                    delegate: Chip {
                                        required property var modelData
                                        property var own: (win.uopts.options || {})[modelData[0]]
                                        property bool eff: (win.uopts.effective || {})[modelData[0]] === true
                                        label: modelData[1] + (own === null && eff ? " ·" : "")
                                        tint: pal.ok; active: eff; on: !win.gameBusy
                                        tip: own === null ? win.t("Inherited from the prefix. Click to set it on this game.") : win.t("Set on this game. Click to switch it.")
                                        onClicked: win.uset([modelData[0] + "=" + (eff ? "off" : "on")])
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Text { text: win.t("FPS LIMIT"); color: pal.dim; font.family: win.mono; font.pixelSize: 9 }
                                Repeater {
                                    model: [0, 60, 120, 144]
                                    delegate: Chip {
                                        required property var modelData
                                        property var cur: (win.uopts.effective || {}).fps_limit
                                        label: modelData === 0 ? win.t("NONE") : String(modelData)
                                        active: modelData === 0 ? !cur : cur === modelData; on: !win.gameBusy
                                        onClicked: win.uset(["fps_limit=" + (modelData === 0 ? "default" : modelData)])
                                    }
                                }
                            }
                            RowLayout {
                                visible: !!win.uopts.effective; spacing: 6; Layout.fillWidth: true
                                Text { text: "ENV"; Layout.preferredWidth: 30; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                Field {
                                    id: uEnv; Layout.fillWidth: true; font.pixelSize: 11
                                    placeholderText: win.t("VAR=value VAR2=value (this game)")
                                    property string loaded: Object.keys(win.uopts.env || {}).map(function (k) { return k + "=" + win.uopts.env[k]; }).join(" ")
                                    onLoadedChanged: text = loaded
                                }
                                MiniBtn {
                                    label: win.t("SAVE"); on: !win.gameBusy && win.uenvArgs(uEnv.text).length > 0
                                    onClicked: win.uset(win.uenvArgs(uEnv.text))
                                }
                            }
                            RowLayout {
                                spacing: 6
                                Chip {
                                    label: "TEMPS"; tint: pal.ok; active: win.gp.overlay === true; on: !win.gameBusy
                                    tip: win.t("CPU · GPU temperature line at the top right while the game runs")
                                    onClicked: win.runGame(["gprofile", "set", win.selGame, "overlay=" + !(win.gp.overlay === true)], win.t("SAVING…"))
                                }
                                Chip {
                                    label: "FX"; tint: pal.ok; active: win.gp.fx === true
                                    tip: win.t("Visual shaders (ReShade / vkBasalt) for this game")
                                    onClicked: win.openFx()
                                }
                            }
                        }
                    }

                    // mods (Crisol): how many, the profile, updates and the mod loader; open it or play with mods
                    Rectangle {
                        Layout.fillWidth: true
                        visible: win.mods.layout !== undefined
                        implicitHeight: modsRow.implicitHeight + 20
                        radius: 8; color: pal.card; border.color: pal.border; border.width: 1
                        RowLayout {
                            id: modsRow
                            anchors.fill: parent; anchors.margins: 10; spacing: 10
                            Text { text: win.t("MODS"); Layout.preferredWidth: 52; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                color: pal.text; font.family: win.mono; font.pixelSize: 11
                                property var ld: win.mods.loader || {}
                                // older Crisol (< 0.2) lists only mods/applied: show what there is
                                text: !win.mods.mods ? win.t("No mods yet (Crisol)")
                                      : (win.mods.enabled !== undefined && win.mods.enabled !== null ? win.mods.enabled + "/" : "")
                                        + win.mods.mods + win.t(" mods on")
                                        + (win.mods.profile ? "  ·  " + win.mods.profile : "")
                                        + (win.mods.applied ? "" : "  ·  " + win.t("not applied"))
                                        + (win.mods.pending_changes ? "  ·  " + win.t("changes to apply") : "")
                                        + (win.mods.updates ? "  ·  " + win.mods.updates + win.t(" updates") : "")
                                        + (ld.level === "required" && !ld.installed ? "  ·  ⚠ " + win.t("missing loader: ") + ld.name : "")
                            }
                            MiniBtn {
                                label: win.t("PLAY WITH MODS"); visible: (win.mods.enabled !== undefined && win.mods.enabled !== null ? win.mods.enabled : win.mods.mods || 0) > 0
                                on: !win.gameBusy; onClicked: win.runGame(["mplay", win.selGame], "LAUNCHING…")
                            }
                            MiniBtn {
                                label: win.t("OPEN IN CRISOL"); primary: false
                                on: !win.gameBusy; onClicked: win.runGame(["mopen", win.selGame], "OPENING…")
                            }
                        }
                    }

                    // launch settings (Steam)
                    Rectangle {
                        Layout.fillWidth: true
                        visible: win.selGameSource === "steam"
                        implicitHeight: launchGrid.implicitHeight + 20
                        radius: 8; color: pal.card; border.color: pal.border; border.width: 1
                        GridLayout {
                            id: launchGrid
                            anchors.fill: parent; anchors.margins: 10
                            columns: 2; columnSpacing: 12; rowSpacing: 8
                            Text { text: win.t("LAUNCH"); Layout.preferredWidth: 52; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Chip {
                                    // on but GameMode isn't installed on this PC: it would do nothing
                                    property bool missing: (win.gstat.gamemode || {}).installed === false
                                    label: "GAMEMODE" + (missing && win.gp.gamemode === true ? " ⚠" : "")
                                    tint: missing ? pal.amber : pal.ok; active: win.gp.gamemode === true
                                    tip: missing ? win.t("GameMode isn't installed on this PC: this does nothing. HEALTH or CHECK FOR THIS PC installs it.") : ""
                                    onClicked: win.gpSet("gamemode", !win.gp.gamemode)
                                }
                                Chip { label: win.t("MANGOHUD"); tint: pal.ok; active: win.gp.mangohud === true; onClicked: win.gpSet("mangohud", !win.gp.mangohud) }
                                Chip { label: "FX"; tint: pal.ok; active: win.gp.fx === true; onClicked: win.openFx()
                                       tip: win.t("Visual shaders (vkBasalt): sharpening, anti-aliasing, ReShade presets") }
                                Chip { label: "TEMPS"; tint: pal.ok; active: win.gp.overlay === true; onClicked: win.gpSet("overlay", !win.gp.overlay)
                                       tip: win.t("A CPU · GPU temperature line at the top right while the game runs (click-through, closes with the game)") }
                                Chip {
                                    // ⚠ when on but the game's disk ignores the level (only BFQ honours it)
                                    label: win.t("IO PRIORITY") + (win.gp.ionice === true && win.ioInfo.levels === false ? " ⚠" : "")
                                    tint: win.ioInfo.levels === false ? pal.amber : pal.ok; active: win.gp.ionice === true
                                    onClicked: win.gpSet("ionice", !win.gp.ionice)
                                    tip: win.t("The game reads and writes the disk ahead of other programs (ionice best-effort, level 0). It helps when something else uses the disk while you play: downloads, updates, copies.")
                                         + (!win.ioInfo.scheduler ? ""
                                            : win.ioInfo.levels ? "\n\n" + win.t("This game's disk honours it: ") + win.ioInfo.disk + " (" + win.ioInfo.scheduler + ")."
                                            : "\n\n" + win.t("No effect here: this game's disk ") + win.ioInfo.disk + win.t(" uses ") + win.ioInfo.scheduler + win.t(", which ignores the level (only BFQ honours it)."))
                                }
                                Item { Layout.fillWidth: true }
                                Text { text: "NICE"; color: pal.dim; font.family: win.mono; font.pixelSize: 9 }
                                Repeater {
                                    model: [0, -5, -10]
                                    delegate: Chip {
                                        required property var modelData
                                        label: String(modelData); active: win.gp.nice === modelData
                                        onClicked: win.gpSet("nice", modelData)
                                    }
                                }
                            }
                            Text { text: "ENV"; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                            Field { id: gEnv; Layout.fillWidth: true; font.pixelSize: 11; placeholderText: "VAR=value VAR2=value" }
                            Text { text: "PREFIX"; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Field { id: gPrefix; Layout.fillWidth: true; font.pixelSize: 11; placeholderText: win.t("before the game, e.g. gamescope -f --") }
                                Text { text: "ARGS"; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                Field { id: gArgs; Layout.fillWidth: true; font.pixelSize: 11; placeholderText: win.t("after the game, e.g. -novid") }
                            }
                            Text { text: "PROTON"; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1
                                   Layout.alignment: Qt.AlignTop; Layout.topMargin: 6 }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                Chip {
                                    label: win.t("STEAM DEFAULT"); active: win.selGameCompat === ""
                                    on: !win.gameBusy; tip: win.t("Steam must be closed to change it")
                                    onClicked: win.runGame(["steamcompat", win.selGameId, "default"], win.t("SETTING PROTON…"))
                                }
                                Repeater {
                                    model: win.tools
                                    delegate: Chip {
                                        required property var modelData
                                        label: modelData.display; active: win.selGameCompat === modelData.name
                                        on: !win.gameBusy; tip: win.t("Steam must be closed to change it")
                                        onClicked: win.runGame(["steamcompat", win.selGameId, modelData.name], win.t("SETTING PROTON…"))
                                    }
                                }
                            }
                            // FSR 4 / DLSS / XeSS upgrades (GE-Proton, Proton-CachyOS)
                            Text { text: win.t("UPSCALE"); color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1
                                   Layout.alignment: Qt.AlignTop; Layout.topMargin: 6 }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4
                                Flow {
                                    Layout.fillWidth: true; spacing: 6
                                    visible: (win.ups.options || []).some(function (o) { return o.available || o.on; })
                                    Repeater {
                                        model: win.ups.options || []
                                        delegate: Chip {
                                            required property var modelData
                                            // OptiScaler sets PROTON_FSR4_UPGRADE too: then it's OptiScaler's, not the plain FSR 4 chip's
                                            property bool isOn: modelData.id === "fsr4"
                                                ? win.envValue(modelData.var) === "1" && win.envValue("PROTON_USE_OPTISCALER") !== "1"
                                                : win.envValue(modelData.var) === "1"
                                            label: (isOn ? "✓ " : "") + win.t(modelData.label)
                                            tint: pal.ok; active: isOn
                                            on: modelData.available || isOn
                                            tip: modelData.available
                                                 ? (modelData.id === "fsr4" ? win.t("The game's FSR 3.1 runs as FSR 4 (AMD's ML upscaler). Proton downloads the DLL. SAVE to apply.")
                                                    : modelData.id === "optifsr4"
                                                      ? win.t("OptiScaler takes over the game's DLSS / XeSS / FSR and renders it with FSR 4 — pick that upscaler in the game's settings. Proton downloads everything; nothing to install.")
                                                        + (win.ups.preferDirect ? win.t(" This game has FSR 3.1: the plain FSR 4 chip is simpler.") : "")
                                                        + win.t(" Its menu: INSERT (Page Down if INSERT is your shader key).")
                                                    : win.t("Proton swaps in the newest ") + modelData.label.replace(" (newest)", "") + win.t(" DLL. SAVE to apply."))
                                                 : win.t(modelData.why)
                                            onClicked: win.toggleEnvSet(modelData.set, isOn)
                                        }
                                    }
                                    Chip {
                                        visible: (win.ups.options || []).some(function (o) { return o.available && (o.id === "fsr4" || o.id === "dlss"); })
                                        property string iv: (win.ups.options || []).some(function (o) { return o.id === "fsr4" && o.available; }) ? "PROTON_FSR4_INDICATOR" : "PROTON_DLSS_INDICATOR"
                                        label: (win.envValue(iv) === "1" ? "✓ " : "") + win.t("ON-SCREEN CHECK"); active: win.envValue(iv) === "1"
                                        tip: win.t("Shows the upscaler's own watermark in game, to confirm the upgrade is active")
                                        onClicked: win.toggleEnv(iv)
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                    // nothing applies: one line, the reasons on hover
                                    property bool none: !(win.ups.options || []).some(function (o) { return o.available || o.on; })
                                    MouseArea { id: upsMa; anchors.fill: parent; hoverEnabled: true; visible: parent.none }
                                    Tip { visible: upsMa.containsMouse; text: (win.ups.options || []).map(function (o) { return win.t(o.label) + ": " + win.t(o.why); }).join("\n") }
                                    text: !win.ups.ships ? "" : none ? win.t("No upscaler upgrade for this game ⓘ") :
                                          win.t("Ships: ") + ([win.ups.ships.fsr31dx12 ? "FSR 3.1 (DX12)" : "", win.ups.ships.fsr31vk ? "FSR 3.1 (Vulkan)" : "",
                                                        win.ups.ships.dlss ? "DLSS" : "", win.ups.ships.xess ? "XeSS" : ""]
                                                       .filter(function (x) { return x; }).join(" · ") || win.t("no swappable upscaler DLL"))
                                          + win.t("  ·  Proton: ") + (win.ups.proton && win.ups.proton.tool ? win.ups.proton.tool : win.t("Steam default"))
                                          + ((win.ups.proton || {}).supports && win.ups.proton.supports.length ? win.t(" (supports upgrades)") : win.t(" (no upgrades: GE-Proton or Proton-CachyOS do)"))
                                }
                            }
                        }
                    }

                    // suggestions from players with hardware like this PC (Steam)
                    Rectangle {
                        Layout.fillWidth: true
                        visible: win.selGameSource === "steam"
                        implicitHeight: sugCol.implicitHeight + 20
                        radius: 8; color: pal.card; border.color: pal.border; border.width: 1
                        ColumnLayout {
                            id: sugCol
                            anchors.fill: parent; anchors.margins: 10; spacing: 8
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text { text: win.t("★ SUGGESTED FOR THIS PC"); color: pal.amber; font.family: win.mono; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1 }
                                Text {
                                    Layout.fillWidth: true; elide: Text.ElideRight
                                    color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                    text: !win.sug.index || !win.sug.reports ? "" :
                                          (win.sug.gpuName || "") + " · " + (win.sug.similarReports > 0 ? win.sug.similarReports + win.t(" similar players")
                                          : (win.sug.vendorReports > 0 ? win.sug.vendorReports + " " + String(win.sug.vendor).toUpperCase() + win.t(" players") : win.sug.reports + win.t(" players")))
                                }
                                Chip {
                                    visible: win.sugOthers.length > 0
                                    label: win.sugExpanded ? win.t("LESS ▴") : "+" + win.sugOthers.length + win.t(" MORE ▾")
                                    onClicked: win.sugExpanded = !win.sugExpanded
                                }
                                Chip {
                                    visible: win.pdbStat.present !== true || win.pdbStat.stale === true
                                    label: win.pdbStat.present === true ? win.t("UPDATE DATA") : win.t("GET DATA (70 MB)")
                                    on: !win.gameBusy; tint: pal.amber; active: true
                                    tip: win.t("ProtonDB's open data (every game's reported launch options), indexed locally to ≈5 MB")
                                    onClicked: win.runGame(["pdbindex", "update"], win.t("INDEXING PROTONDB DATA…"))
                                }
                            }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                visible: win.sugRecommended.length > 0
                                Repeater {
                                    model: win.sugRecommended
                                    delegate: Chip {
                                        required property var modelData
                                        property bool applied: win.sugApplied(modelData)
                                        label: win.sugLabel(modelData, applied, "★ ")
                                        tint: pal.amber; active: true; opacity: applied ? 0.55 : 1.0
                                        tip: win.sugTip(modelData, applied)
                                        onClicked: win.applySug(modelData)
                                    }
                                }
                            }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                visible: win.sugExpanded && win.sugOthers.length > 0
                                Repeater {
                                    model: win.sugOthers
                                    delegate: Chip {
                                        required property var modelData
                                        property bool applied: win.sugApplied(modelData)
                                        label: win.sugLabel(modelData, applied, "+ ")
                                        tint: pal.ok; active: applied
                                        tip: win.sugTip(modelData, applied)
                                        onClicked: win.applySug(modelData)
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true; elide: Text.ElideRight
                                color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                text: win.pdbStat.present !== true ? win.t("Get the data once to see what players with hardware like yours use.")
                                      : (!win.sug.index ? "" : (win.sug.reports === 0 ? win.t("No ProtonDB report with launch options for this game yet.")
                                         : (win.sugRecommended.length + win.sugOthers.length === 0 ? win.t("Players don't agree on any launch option for this game.")
                                            : (win.sugRecommended.length === 0 ? win.t("Nothing is used by enough similar players to recommend it. ") : "")
                                              + win.t("Click to add, then SAVE · % of players who say it works · ProtonDB (ODbL) ") + win.pdbStat.date)))
                            }
                        }
                    }

                    // status + actions
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            font.family: win.mono; font.pixelSize: 10
                            color: win.selGameSource === "steam" && win.selGameWrapped ? pal.ok : pal.dim
                            text: win.selGameSource !== "steam" ? ""
                                  : (win.selGameWrapped ? win.t("● Launched through Gaming Deck")
                                     : win.t("○ Steam options: ") + (win.selGameLaunch || "none"))
                            Tip { visible: stMa.containsMouse && parent.text !== ""; text: win.selGameWrapped ? win.t("The profile applies on every launch from Steam.")
                                          : win.t("USE IN STEAM moves these options into the profile (Steam must be closed).") }
                            MouseArea { id: stMa; anchors.fill: parent; hoverEnabled: true }
                        }
                        MiniBtn {
                            width: Math.max(70, implicitWidth); height: 32; primary: false; label: win.t("RESET")
                            visible: win.selGameSource === "steam" && win.gp.custom === true
                            on: !win.gameBusy
                            onClicked: win.runGame(["gprofile", "reset", win.selGame], win.t("RESETTING…"))
                        }
                        MiniBtn {
                            width: Math.max(120, implicitWidth); height: 32; primary: false
                            visible: win.selGameSource === "steam"
                            label: win.selGameWrapped ? win.t("RESTORE STEAM") : win.t("USE IN STEAM")
                            on: !win.gameBusy
                            onClicked: win.runGame(["steamwrap", win.selGameId, win.selGameWrapped ? "off" : "on"],
                                                   win.selGameWrapped ? win.t("RESTORING…") : win.t("WRAPPING…"))
                        }
                        MiniBtn {
                            width: Math.max(76, implicitWidth); height: 32; label: win.t("SAVE")
                            visible: win.selGameSource === "steam"
                            on: !win.gameBusy
                            onClicked: win.saveGameProfile()
                        }
                        MiniBtn {
                            width: Math.max(76, implicitWidth); height: 32; label: win.t("▶ PLAY"); tint: pal.ok
                            on: !win.gameBusy
                            onClicked: win.playGame()
                        }
                    }
                    }
                }


                // ---- PREFIXES ----
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: win.gameView === "prefixes"
                    spacing: 8

                    Hint {
                        text: !win.pfx.prefixes ? "" : win.pfx.prefixes.length + win.t(" prefixes · ") + win.human(win.pfx.total)
                              + ((win.pfx.orphanBytes || 0) > 0 ? " · " + win.human(win.pfx.orphanBytes) + win.t(" in orphans (no game uses them)") : "")
                              + " · " + win.pfxBackups.length + win.t(" backups in ~/gaming-deck-backups/prefixes")
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        radius: 8; color: pal.panel; border.color: pal.border; border.width: 1; clip: true
                        EmptyHint {
                            visible: !win.pfx.prefixes || win.pfx.prefixes.length === 0
                            title: pfxProc.running ? win.t("LOOKING FOR PREFIXES…") : win.t("NO WINE/PROTON PREFIXES FOUND")
                        }
                        ListView {
                            id: pfxList
                            anchors.fill: parent; anchors.margins: 4
                            clip: true; spacing: 3
                            model: win.pfx.prefixes || []
                            ScrollBar.vertical: ScrollBar {}
                            delegate: Rectangle {
                                required property var modelData
                                width: pfxList.width - 8; height: 52; radius: 8
                                color: pal.card; border.width: 1
                                border.color: modelData.orphan ? pal.amber : (modelData.running ? pal.ok : pal.border)
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        RowLayout {
                                            spacing: 8
                                            Text { text: modelData.owner.toUpperCase(); color: win.srcColor(modelData.owner === "steam" ? "flatpak" : "aur")
                                                   font.family: win.mono; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1 }
                                            Text { text: win.t(modelData.name); color: pal.text; font.family: win.mono; font.pixelSize: 12; font.bold: true
                                                   elide: Text.ElideRight; Layout.maximumWidth: 300 }
                                            Text { text: win.human(modelData.size); color: pal.amber; font.family: win.mono; font.pixelSize: 10 }
                                            Text { visible: modelData.orphan; text: win.t("ORPHAN"); color: pal.amber; font.family: win.mono; font.pixelSize: 8; font.bold: true }
                                            Text { visible: modelData.running; text: win.t("IN USE"); color: pal.ok; font.family: win.mono; font.pixelSize: 8; font.bold: true }
                                            Text { visible: modelData.kind === "tool" || modelData.kind === "shared"; text: modelData.kind === "tool" ? win.t("TOOL") : win.t("SHARED")
                                                   color: pal.dim; font.family: win.mono; font.pixelSize: 8; font.bold: true }
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideMiddle
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                            text: (modelData.version || "?") + "  ·  " + modelData.arch + win.t("  ·  used ") + win.dateOfEpoch(modelData.lastUsed)
                                                  + "  ·  " + modelData.path.replace(win.home, "~")
                                        }
                                    }
                                    MiniBtn { width: Math.max(64, implicitWidth); label: win.t("BACKUP"); primary: false; on: !win.gameBusy && !modelData.running
                                              onClicked: win.runGame(["prefix", "backup", modelData.path], win.t("BACKING UP…")) }
                                    MiniBtn { width: Math.max(60, implicitWidth); label: win.t("CLONE"); primary: false; on: !win.gameBusy && !modelData.running
                                              onClicked: win.runGame(["prefix", "clone", modelData.path], win.t("CLONING…")) }
                                    MiniBtn {
                                        width: Math.max(80, implicitWidth); tint: pal.bad
                                        property string key: "pfx:" + modelData.path
                                        // stands out only where deleting is the suggestion (orphans) or being confirmed
                                        primary: modelData.orphan || win.confirmShader === key
                                        label: win.confirmShader === key ? win.t("CONFIRM?") : win.t("DELETE")
                                        on: !win.gameBusy && !modelData.running && modelData.kind !== "tool" && modelData.kind !== "shared"
                                        onClicked: win.shaderAction(["prefix", "delete", modelData.path], key, win.t("BACKING UP + DELETING…"))
                                    }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Hint {
                            text: win.t("DELETE always makes a backup first (a Steam game's prefix is recreated on its next launch — saves kept only in the prefix would be lost without it). CLONE copies the Wine prefix to ~/Games/prefixes (instant on Btrfs). Restore a backup: gaming-deck prefix restore <backup> <folder>.")
                        }
                        MiniBtn { width: Math.max(100, implicitWidth); label: win.t("BACKUPS ↗"); primary: false; onClicked: pfxOpenProc.running = true }
                    }
                }

                // ---- BENCH (A/B) ----
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: win.gameView === "bench"
                    spacing: 8

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        visible: win.selGame === "" || win.selGameSource !== "steam"
                        EmptyHint { title: win.selGame === "" ? win.t("PICK A GAME IN LIBRARY FIRST") : win.t("A/B BENCHMARKS ARE FOR STEAM GAMES") }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 8
                        visible: win.selGame !== "" && win.selGameSource === "steam"

                        Section { Layout.fillWidth: true; label: "A / B"; info: win.selGameName }

                        // the two variants side by side
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            BenchVariant { id: benchA; v: "A"; tint: pal.accent }
                            BenchVariant { id: benchB; v: "B"; tint: pal.pink }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text { text: win.t("MEASURE"); color: pal.dim; font.family: win.mono; font.pixelSize: 9 }
                            Repeater {
                                model: [30, 60, 120, 300]
                                delegate: Chip { required property int modelData; label: modelData + " s"; active: win.bench.duration === modelData
                                                 onClicked: win.saveBench(["duration=" + modelData]) }
                            }
                            Text { text: win.t("AFTER"); color: pal.dim; font.family: win.mono; font.pixelSize: 9; Layout.leftMargin: 8 }
                            Repeater {
                                model: [5, 15, 30, 60]
                                delegate: Chip { required property int modelData; label: modelData + " s"; active: win.bench.delay === modelData
                                                 onClicked: win.saveBench(["delay=" + modelData]) }
                            }
                            Item { Layout.fillWidth: true }
                            MiniBtn { width: Math.max(70, implicitWidth); label: win.t("SAVE"); on: !win.gameBusy; onClicked: win.saveBench([]) }
                            MiniBtn { width: Math.max(70, implicitWidth); label: win.t("RUN A"); tint: pal.accent; on: !win.gameBusy && win.selGameWrapped
                                      onClicked: win.runBench("A") }
                            MiniBtn { width: Math.max(70, implicitWidth); label: win.t("RUN B"); tint: pal.pink; on: !win.gameBusy && win.selGameWrapped
                                      onClicked: win.runBench("B") }
                        }
                        Hint {
                            text: !win.selGameWrapped ? win.t("The game must launch through Gaming Deck: LIBRARY → USE IN STEAM first.")
                                  : win.t("RUN starts the game from Steam; MangoHud records every frame after the delay, for the measured time. Play the same scene in both runs, quit the game, then REFRESH. Variants changing Proton need Steam closed.")
                                    + (win.bench.originalProton ? win.t("  Proton was changed for a run: RESTORE PROTON when done.") : "")
                        }

                        // results
                        Rectangle {
                            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 150
                            radius: 8; color: pal.panel; border.color: pal.border; border.width: 1; clip: true
                            EmptyHint {
                                visible: !win.bench.results || (!win.bench.results.A && !win.bench.results.B)
                                title: win.t("NO RUNS YET")
                            }
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 10; spacing: 12
                                visible: !!win.bench.results && (!!win.bench.results.A || !!win.bench.results.B)
                                GridLayout {
                                    columns: 4; rowSpacing: 4; columnSpacing: 12
                                    Layout.alignment: Qt.AlignTop
                                    Repeater {
                                        model: [["", "A", "B", win.t("Δ B vs A")],
                                                [win.t("Avg FPS"), "avgFps", "avgFps", "avgFps"], [win.t("1% low"), "low1", "low1", "low1"],
                                                [win.t("0.1% low"), "low01", "low01", ""], [win.t("p99 frame ms"), "p99ms", "p99ms", "p99ms"],
                                                [win.t("Spikes"), "spikes", "spikes", ""], [win.t("CPU load %"), "cpuLoad", "cpuLoad", ""],
                                                [win.t("GPU load %"), "gpuLoad", "gpuLoad", ""], [win.t("GPU max °C"), "gpuTempMax", "gpuTempMax", ""],
                                                [win.t("Frames"), "frames", "frames", ""]]
                                        delegate: Item {
                                            required property var modelData
                                            required property int index
                                            Layout.columnSpan: 4; Layout.fillWidth: true; implicitHeight: 16
                                            RowLayout {
                                                anchors.fill: parent; spacing: 12
                                                property var ra: (win.bench.results || {}).A
                                                property var rb: (win.bench.results || {}).B
                                                Text { Layout.preferredWidth: 96; text: modelData[0]; color: pal.dim; font.family: win.mono; font.pixelSize: 10 }
                                                Text { Layout.preferredWidth: 60; color: index === 0 ? pal.accent : pal.text; font.family: win.mono; font.pixelSize: 10; font.bold: index === 0
                                                       text: index === 0 ? ((win.bench.A || {}).label || "A") : (parent.ra ? String(parent.ra[modelData[1]]) : "—") }
                                                Text { Layout.preferredWidth: 60; color: index === 0 ? pal.pink : pal.text; font.family: win.mono; font.pixelSize: 10; font.bold: index === 0
                                                       text: index === 0 ? ((win.bench.B || {}).label || "B") : (parent.rb ? String(parent.rb[modelData[2]]) : "—") }
                                                Text {
                                                    Layout.preferredWidth: 70; font.family: win.mono; font.pixelSize: 10
                                                    property var d: index === 0 || modelData[3] === "" || !win.bench.compare ? undefined : win.bench.compare[modelData[3]]
                                                    // higher FPS is better; lower frametime is better
                                                    color: index === 0 ? pal.dim : (d === undefined ? pal.dim
                                                           : ((modelData[3] === "p99ms" ? -d : d) >= 0 ? pal.ok : pal.bad))
                                                    text: index === 0 ? modelData[3] : (d === undefined ? "" : win.pct(d))
                                                }
                                            }
                                        }
                                    }
                                }
                                // frametime curves (worst frame per bucket)
                                Canvas {
                                    id: benchChart
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                        var r = win.bench.results || {}, a = r.A ? r.A.series : [], b = r.B ? r.B.series : [];
                                        var p99 = Math.max(r.A ? r.A.p99ms : 0, r.B ? r.B.p99ms : 0);
                                        var ymax = Math.max(p99 * 1.6, 5);
                                        ctx.strokeStyle = "#2a2740"; ctx.lineWidth = 1;
                                        [16.7, 33.3].forEach(function (ms) {
                                            if (ms > ymax) return;
                                            var y = height - ms / ymax * height;
                                            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
                                            ctx.fillStyle = "#6a6580"; ctx.font = "9px monospace"; ctx.fillText(ms + " ms", 2, y - 2);
                                        });
                                        function line(sr, col) {
                                            if (!sr || sr.length < 2) return;
                                            ctx.strokeStyle = col; ctx.lineWidth = 1.2; ctx.beginPath();
                                            for (var i = 0; i < sr.length; i++) {
                                                var x = i / (sr.length - 1) * width, y = height - Math.min(sr[i], ymax) / ymax * height;
                                                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                                            }
                                            ctx.stroke();
                                        }
                                        line(a, "#b9a3e3"); line(b, "#d9a7d0");
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Item { Layout.fillWidth: true }
                            MiniBtn { width: Math.max(110, implicitWidth); label: win.t("REFRESH RESULTS"); primary: false; on: !win.gameBusy; onClicked: benchProc.running = true }
                            MiniBtn { width: Math.max(110, implicitWidth); label: win.t("RESTORE PROTON"); primary: false; visible: !!win.bench.originalProton; on: !win.gameBusy
                                      onClicked: win.runGame(["bench", "restore", win.selGame], win.t("RESTORING…")) }
                            MiniBtn { width: Math.max(70, implicitWidth); label: win.t("CLEAR"); tint: pal.bad; primary: false; on: !win.gameBusy
                                      onClicked: win.runGame(["bench", "clear", win.selGame], win.t("CLEARING…")) }
                        }
                    }
                }

                // ---- FX (visual shaders) ----
                // FX: this game / my whole library (fixed above the scrolling part)
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    visible: win.gameView === "fx"
                    Chip { label: win.t("THIS GAME"); active: win.fxScope === "game"; onClicked: win.fxScope = "game" }
                    Chip {
                        label: win.t("MY LIBRARY") + (win.fxEligible > 0 ? "  ·  " + win.fxEligible + win.t(" to set up") : "")
                        active: win.fxScope === "library"
                        onClicked: { win.fxScope = "library"; if (win.fxScan.length === 0 && !fxScanProc.running) { fxScanProc.cached = false; fxScanProc.running = true; } }
                    }
                    Item { Layout.fillWidth: true }
                }

                ScrollView {
                    id: fxScroll
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: win.gameView === "fx"
                    contentWidth: availableWidth
                    clip: true
                    ColumnLayout {
                        width: fxScroll.availableWidth
                        spacing: 8

                        ColumnLayout {
                        id: fxGameCol
                        Layout.fillWidth: true; spacing: 8
                        visible: win.fxScope === "game"

                            EmptyHint {
                                Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 40; anchors.centerIn: undefined
                                visible: !win.fxGame
                                title: win.t("PICK A STEAM OR UMBRAL GAME IN LIBRARY")
                            }

                            // header: game · GPU · vkBasalt
                            RowLayout {
                                Layout.fillWidth: true; spacing: 9
                                visible: win.fxGame
                                Rectangle { width: 7; height: 7; color: pal.accent; Layout.alignment: Qt.AlignVCenter }
                                Text { text: win.t("VISUAL SHADERS"); color: pal.text; font.family: win.mono; font.pixelSize: 12; font.letterSpacing: 4; font.bold: true }
                                Text { Layout.fillWidth: true; elide: Text.ElideRight; text: win.selGameName; color: pal.dim; font.family: win.mono; font.pixelSize: 11 }
                                Text {
                                    Layout.maximumWidth: 320; elide: Text.ElideMiddle
                                    text: win.shortGpu(win.fx.gpu) + "  ·  " + (win.fxReshade
                                          ? (win.fx.reshade && win.fx.reshade.version ? "ReShade " + win.fx.reshade.version : win.t("ReShade not installed"))
                                          : (win.fx.vkbasalt ? "vkBasalt " + win.fx.version : win.t("vkBasalt not installed")))
                                    color: (win.fxReshade ? (win.fx.reshade || {}).ready : win.fx.vkbasalt) ? pal.dim : pal.amber
                                    font.family: win.mono; font.pixelSize: 10
                                }
                            }

                            // a game no shader tool can hook (2D GDI, e.g. RPG Maker XP)
                            Rectangle {
                                Layout.fillWidth: true
                                visible: win.fxGame && win.fx.recommended === "none"
                                implicitHeight: noFxTxt.implicitHeight + 16
                                radius: 8; color: pal.card; border.color: pal.amber; border.width: 1
                                Text {
                                    id: noFxTxt
                                    anchors.fill: parent; anchors.margins: 8; wrapMode: Text.WordWrap
                                    color: pal.amber; font.family: win.mono; font.pixelSize: 11
                                    text: win.t("This game is drawn in 2D with GDI (RPG Maker style), not with DirectX, OpenGL or Vulkan: neither ReShade nor vkBasalt can hook it. TEMPS still works (LIBRARY).")
                                }
                            }

                            // guided steps (live state of this game)
                            Rectangle {
                                Layout.fillWidth: true
                                visible: win.fxGame && !!win.fx.gpu && win.fx.recommended !== "none"
                                implicitHeight: guideCol.implicitHeight + 16
                                radius: 8; color: pal.card; border.width: 1
                                border.color: win.fxStepsDone === 5 ? pal.ok : pal.accent
                                ColumnLayout {
                                    id: guideCol
                                    anchors.fill: parent; anchors.margins: 8; spacing: 5
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        Text {
                                            text: win.fxStepsDone === 5 ? win.t("● READY") : win.t("STEPS")
                                            color: win.fxStepsDone === 5 ? pal.ok : pal.text
                                            font.family: win.mono; font.pixelSize: 10; font.bold: true; font.letterSpacing: 2
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            font.family: win.mono; font.pixelSize: 10
                                            color: win.fxStepsDone === 5 ? pal.text : pal.dim
                                            text: win.fxStepsDone === 5
                                                  ? (win.fxReshade ? "ReShade" : "vkBasalt") + "  ·  " + (win.fxCur.name || "") + " (" + (win.fxCur.applied || 0) + win.t(" effects)")
                                                    + win.t("  ·  menu ") + (win.fx.key || "Home").toUpperCase()
                                                    + (win.fxReshade && (win.fx.effectsKey || "End") !== "None" ? win.t("  ·  on/off ") + (win.fx.effectsKey || "End").toUpperCase() : "")
                                                  : win.fxStepsDone + win.t(" of 5 done — next: ") + ((win.fxSteps.filter(function (s) { return !s[0]; })[0] || ["", ""])[1])
                                        }
                                        Text {
                                            visible: win.fxStepsDone === 5 && (win.fxCur.skipped || []).length > 0
                                            text: "⚠ " + (win.fxCur.skipped || []).length + win.t(" skipped"); color: pal.amber
                                            font.family: win.mono; font.pixelSize: 10
                                            MouseArea { id: skipMa; anchors.fill: parent; hoverEnabled: true }
                                            Tip { visible: skipMa.containsMouse; text: (win.fxCur.skipped || []).map(function (x) { return x.effect + " — " + x.why; }).join("\n") }
                                        }
                                        Chip {
                                            visible: win.fxStepsDone === 5 && win.fxCur.source === "sfx"
                                            label: "PRESET ↗"; onClicked: Qt.openUrlExternally(win.fxCur.url)
                                        }
                                        FxRemoveBtn { visible: win.fxStepsDone === 5 }
                                        Chip { label: win.fxGuideOpen ? win.t("GUIDE ▴") : win.t("GUIDE ▾"); tip: win.t("Every step, with what each one does"); onClicked: win.fxGuideOpen = !win.fxGuideOpen }
                                    }
                                    // what is installed: where the preset came from, each effect and its shader pack
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        visible: win.fxStepsDone === 5 && (win.fxCur.effects || []).length > 0
                                        Text {
                                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                            property var packs: Object.keys(win.fxCur.packs || {}).map(function (k) { return win.fxCur.packs[k]; })
                                                                     .filter(function (p, i, a) { return p && a.indexOf(p) === i; })
                                            text: [win.fxCur.source === "file" ? (win.fxCur.archive ? win.t("Imported from ") + win.fxCur.archive : win.t("Imported preset"))
                                                   : win.fxCur.source === "sfx" ? win.t("From SweetFX Settings DB") : win.t("Built-in look"),
                                                   win.fxCur.importedAt ? new Date(win.fxCur.importedAt * 1000).toLocaleString(Qt.locale(), "dd/MM/yyyy HH:mm") : "",
                                                   (win.fxCur.bundled || 0) > 0 ? win.fxCur.bundled + win.t(" shader file(s) from the archive") : "",
                                                   packs.length ? win.t("shader packs: ") + packs.join(", ") : ""].filter(function (x) { return x; }).join("  ·  ")
                                        }
                                        // what the preset does (review): verdict, warnings, and a lighter version in one click
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 4
                                            visible: !!win.fxCur.review
                                            property var rv: win.fxCur.review || ({})
                                            property var pending: (rv.suggestOff || []).filter(function (f) { return (win.fxCur.disabled || []).indexOf(f) < 0; })
                                            Repeater {
                                                model: { var r = parent.rv; return r.verdict ? [{ t: win.verdictLabel(r.verdict), tone: win.verdictTone(r.verdict), why: win.t("How much this preset changes the game's look") }].concat(r.flags || []) : []; }
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    implicitWidth: crTxt.implicitWidth + 10; implicitHeight: 16; radius: 3
                                                    color: "transparent"; border.width: 1; border.color: win.tagTone(modelData.tone)
                                                    Text { id: crTxt; anchors.centerIn: parent; text: win.t(modelData.t); color: win.tagTone(modelData.tone); font.family: win.mono; font.pixelSize: 8; font.bold: true }
                                                    MouseArea { id: crMa; anchors.fill: parent; hoverEnabled: true }
                                                    Tip { visible: crMa.containsMouse && !!modelData.why; text: win.t(modelData.why) }
                                                }
                                            }
                                            Item { Layout.fillWidth: true }
                                            Chip {
                                                visible: parent.pending.length > 0
                                                label: win.t("LIGHTER"); tint: pal.ok; on: !win.gameBusy
                                                tip: win.t("Switch off what usually makes it look worse: ") + parent.pending.map(function (f) { return f.replace(/\.fx$/i, ""); }).join(", ")
                                                     + win.t(". You can switch any of them back on below.")
                                                onClicked: win.runGame(["fx", "lighter", win.selGame], win.t("APPLYING…"))
                                            }
                                        }
                                        Flow {
                                            Layout.fillWidth: true; spacing: 4
                                            property bool switchable: win.fxCur.source === "file" || win.fxCur.source === "sfx"
                                            Repeater {
                                                model: (win.fxCur.effects || []).map(function (e) { return { e: e, st: "on" }; })
                                                       .concat((win.fxCur.disabled || []).map(function (e) { return { e: e, st: "off" }; }))
                                                       .concat((win.fxCur.skipped || []).map(function (s) { return { e: s.file || s.effect, st: "missing", why: s.why }; }))
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    implicitWidth: effTxt.implicitWidth + 12; implicitHeight: 18; radius: 4
                                                    color: "transparent"; border.width: 1
                                                    border.color: modelData.st === "missing" ? pal.bad : (effMa.containsMouse && parent.switchable ? pal.accent : pal.border)
                                                    opacity: modelData.st === "off" ? 0.55 : 1
                                                    Text {
                                                        id: effTxt; anchors.centerIn: parent
                                                        property string pk: modelData.st === "on" ? ((win.fxCur.packs || {})[modelData.e] || "") : ""
                                                        text: (modelData.st === "on" ? "✓ " : (modelData.st === "off" ? "○ " : "✗ ")) + modelData.e.replace(/\.fx$/i, "") + (pk ? "  · " + pk : "")
                                                        color: modelData.st === "missing" ? pal.bad : pal.text; font.family: win.mono; font.pixelSize: 9
                                                        font.strikeout: modelData.st === "off"
                                                    }
                                                    MouseArea {
                                                        id: effMa; anchors.fill: parent; hoverEnabled: true
                                                        cursorShape: parent.parent.switchable && modelData.st !== "missing" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                        onClicked: if (parent.parent.switchable && modelData.st !== "missing" && !win.gameBusy)
                                                                       win.runGame(["fx", "toggle", win.selGame, modelData.e, modelData.st === "on" ? "off" : "on"], win.t("APPLYING…"))
                                                    }
                                                    Tip {
                                                        visible: effMa.containsMouse
                                                        text: modelData.st === "missing" ? win.t(modelData.why || "")
                                                              : !parent.parent.switchable ? ""
                                                              : (modelData.st === "on" ? win.t("Click to switch it off") : win.t("Switched off — click to switch it back on")) + win.t(" (applies the next time the game starts)")
                                                    }
                                                }
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 6
                                            Text {
                                                Layout.fillWidth: true; elide: Text.ElideMiddle
                                                color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                                text: win.t("preset file: ") + (win.fxCur.presetFile || "")
                                            }
                                            Chip {
                                                visible: !!win.fxCur.presetFile; label: win.t("FOLDER ↗")
                                                tip: win.t("Open the folder with this game's preset")
                                                onClicked: Qt.openUrlExternally("file://" + String(win.fxCur.presetFile).replace(/^~/, win.home).replace(/\/[^\/]*$/, ""))
                                            }
                                        }
                                    }
                                    Repeater {
                                        // all steps when opened; otherwise just the next one (none when all is done)
                                        model: win.fxSteps.map(function (s, i) { return { s: s, i: i }; })
                                                   .filter(function (x, n, all) {
                                                       return win.fxGuideOpen
                                                           || (!x.s[0] && all.slice(0, n).every(function (y) { return y.s[0]; }));
                                                   })
                                        delegate: RowLayout {
                                            required property var modelData
                                            property int index: modelData.i
                                            property var step: modelData.s
                                            Layout.fillWidth: true; spacing: 8
                                            property bool next: !step[0] && win.fxSteps.slice(0, index).every(function (s) { return s[0]; })
                                            Text {
                                                text: step[0] ? "✓" : String(index + 1)
                                                Layout.preferredWidth: 14; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignTop
                                                color: step[0] ? pal.ok : (next ? pal.amber : pal.dim)
                                                font.family: win.mono; font.pixelSize: 11; font.bold: true
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 1
                                                Text {
                                                    text: step[1]; font.family: win.mono; font.pixelSize: 11; font.bold: next
                                                    color: step[0] ? pal.dim : (next ? pal.text : pal.dim)
                                                }
                                                Text {
                                                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                                                    text: step[2]; color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                                }
                                            }
                                            // the pending step's own button
                                            MiniBtn {
                                                visible: next && index === 0
                                                width: Math.max(140, implicitWidth); height: 28; label: win.fx.recommended === "vkbasalt" ? win.t("USE VKBASALT ★") : win.t("USE RESHADE ★")
                                                on: !win.gameBusy
                                                onClicked: win.fx.recommended === "vkbasalt"
                                                           ? win.fxApply("mode:vkbasalt", win.t("SWITCHING…"), ["fx", "mode", win.selGame, "vkbasalt"])
                                                           : win.fxApply("mode:reshade", win.t("SETTING UP RESHADE…"), ["fx", "mode", win.selGame, "reshade"])
                                            }
                                            MiniBtn {
                                                visible: next && index === 1
                                                width: Math.max(90, implicitWidth); height: 28; label: win.t("INSTALL"); on: !win.gameBusy
                                                onClicked: win.runGame(win.fxReshade ? ["fx", "reshade", "install"] : ["fx", "install"], win.t("INSTALLING…"))
                                            }
                                            MiniBtn {
                                                visible: next && index === 2 && !win.fxUmbral
                                                width: Math.max(120, implicitWidth); height: 28; label: win.t("USE IN STEAM")
                                                on: !win.gameBusy && !win.fx.steamRunning
                                                onClicked: win.runGame(["steamwrap", win.selGameId, "on"], win.t("WRAPPING…"))
                                            }
                                            Chip {
                                                visible: next && index === 3
                                                label: (win.fx.links || []).length ? win.t("OPEN ") + win.fx.links[0].label + " ↗" : win.t("SEARCH NEXUS ↗")
                                                onClicked: Qt.openUrlExternally((win.fx.links || []).length ? win.fx.links[0].url
                                                    : "https://duckduckgo.com/?q=" + encodeURIComponent("site:nexusmods.com " + win.selGameName + " reshade preset"))
                                            }
                                            MiniBtn {
                                                visible: next && index === 3 && (win.fx.links || []).length > 0
                                                width: Math.max(90, implicitWidth); height: 28; label: win.t("IMPORT…")
                                                on: !win.gameBusy && win.fxReady && !fxPickProc.running
                                                onClicked: fxPickProc.running = true
                                            }
                                        }
                                    }
                                }
                            }

                            // route: ReShade (DLL) or vkBasalt (Vulkan layer)
                            Rectangle {
                                Layout.fillWidth: true
                                visible: win.fxGame && !!win.fx.gpu && win.fx.recommended !== "none"
                                implicitHeight: fxRoute.implicitHeight + 20
                                radius: 8; color: pal.card; border.color: pal.border; border.width: 1
                                ColumnLayout {
                                    id: fxRoute
                                    anchors.fill: parent; anchors.margins: 10; spacing: 6
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        Text { text: win.t("ROUTE"); Layout.preferredWidth: 92; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Chip {
                                            property string k: "mode:reshade"
                                            label: win.fxConfirm === k ? win.t("CONFIRM?") : "RESHADE" + (win.fx.recommended === "reshade" ? "  ★" : "")
                                            tint: pal.ok; active: win.fxReshade
                                            on: !win.gameBusy
                                            tip: win.t("ReShade itself: presets exactly as made (depth effects too) and its in-game menu. For D3D9–12 and OpenGL games.")
                                            onClicked: if (!win.fxReshade) win.fxApply(k, win.t("SETTING UP RESHADE…"), ["fx", "mode", win.selGame, "reshade"])
                                        }
                                        Chip {
                                            property string k: "mode:vkbasalt"
                                            label: win.fxConfirm === k ? win.t("CONFIRM?") : "VKBASALT" + (win.fx.recommended === "vkbasalt" ? "  ★" : "")
                                            tint: pal.ok; active: !win.fxReshade
                                            on: !win.gameBusy
                                            tip: win.t("A Vulkan layer: simplest, no files in the game folder; presets are converted and effects that need depth are skipped.")
                                            onClicked: if (win.fxReshade) win.fxApply(k, win.t("SWITCHING…"), ["fx", "mode", win.selGame, "vkbasalt"])
                                        }
                                        // why the ★ one: one line, the full reasons on hover
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                            text: "★ " + win.t(((win.fx.advice || {}).reasons || [""])[0] || "")
                                            MouseArea { id: whyMa; anchors.fill: parent; hoverEnabled: true }
                                            Tip { visible: whyMa.containsMouse; text: ((win.fx.advice || {}).reasons || []).map(win.t).join("\n\n") }
                                        }
                                        Chip {
                                            label: win.fxDetails ? win.t("SETTINGS ▴") : win.t("SETTINGS ▾")
                                            tip: win.t("Executable, graphics API and the in-game keys")
                                            onClicked: win.fxDetails = !win.fxDetails
                                        }
                                    }
                                    // ReShade: which .exe, which API
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        visible: win.fxReshade && win.fxDetails
                                        Text { text: win.t("EXECUTABLE"); Layout.preferredWidth: 92; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Flow {
                                            Layout.fillWidth: true; spacing: 6
                                            Repeater {
                                                model: (win.fx.reshade || {}).exes || []
                                                delegate: Chip {
                                                    required property var modelData
                                                    label: modelData.rel + "  ·  " + modelData.arch + "-bit"
                                                    active: !!win.fxRsGame && win.fxRsGame.exe === modelData.path
                                                    on: !win.gameBusy
                                                    tip: win.t("Install ReShade next to this .exe (detected API: ") + modelData.api + ")"
                                                    onClicked: win.runGame(["fx", "mode", win.selGame, "reshade", modelData.path], win.t("MOVING RESHADE…"))
                                                }
                                            }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        visible: win.fxReshade && !!win.fxRsGame && win.fxDetails
                                        Text { text: "HOOKS"; Layout.preferredWidth: 92; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Repeater {
                                            model: [["dxgi", "DXGI · DX10–12"], ["d3d9", "D3D9"], ["opengl32", "OPENGL"]]
                                            delegate: Chip {
                                                required property var modelData
                                                label: modelData[1]; active: !!win.fxRsGame && win.fxRsGame.api === modelData[0]
                                                on: !win.gameBusy
                                                tip: win.t("Only change it if ReShade doesn't show up in game")
                                                onClicked: win.runGame(["fx", "mode", win.selGame, "reshade", win.fxRsGame.exe, modelData[0]], win.t("SWITCHING API…"))
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                            text: "✓ " + (win.fxRsGame ? win.fxRsGame.api : "") + win.t(".dll + d3dcompiler_47 linked in the game folder · OFF removes them")
                                        }
                                    }
                                    // the in-game key (ReShade's menu / vkBasalt on-off), one for all games
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        visible: win.fxDetails
                                        Text { text: win.t("MENU KEY"); Layout.preferredWidth: 92; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Repeater {
                                            model: [["Home", "HOME", ""], ["Insert", "INSERT", ""], ["F10", "F10", ""], ["F11", "F11", ""],
                                                    ["F12", "F12", win.t("Steam takes screenshots with F12 by default")]]
                                            delegate: Chip {
                                                required property var modelData
                                                label: modelData[1]; active: (win.fx.key || "Home") === modelData[0]
                                                on: !win.gameBusy; tip: modelData[2]
                                                onClicked: win.runGame(["fx", "key", modelData[0]], win.t("SETTING KEY…"))
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                            text: win.fxReshade ? win.t("opens ReShade's menu in game") : win.t("turns the effects on/off in game")
                                        }
                                    }
                                    // ReShade: one key that switches every effect on/off (the mod guides' "END")
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        visible: win.fxReshade && win.fxDetails
                                        Text { text: win.t("ON/OFF KEY"); Layout.preferredWidth: 92; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Repeater {
                                            model: [["End", "END", win.t("The key most preset guides suggest")], ["F9", "F9", win.t("Some games quick-load with F9")], ["None", win.t("NONE"), win.t("No key: effects stay on")]]
                                            delegate: Chip {
                                                required property var modelData
                                                label: modelData[1]; active: (win.fx.effectsKey || "End") === modelData[0]
                                                on: !win.gameBusy; tip: modelData[2]
                                                onClicked: win.runGame(["fx", "effectskey", modelData[0]], win.t("SETTING KEY…"))
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                            text: win.t("switches all effects on/off in game — compare, or drop them in heavy scenes")
                                        }
                                    }
                                    // ReShade's screenshot key: the desktop may keep PrtSc for itself
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        visible: win.fxReshade && win.fxDetails
                                        Text { text: win.t("SCREENSHOT KEY"); Layout.preferredWidth: 92; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Repeater {
                                            model: ["PrtSc", "F8", "F10", "F11"]
                                            delegate: Chip {
                                                required property var modelData
                                                label: modelData === "PrtSc" ? win.t("PRT SC") : modelData
                                                active: (win.fx.shotKey || "PrtSc") === modelData
                                                on: !win.gameBusy && modelData !== win.fx.key && modelData !== win.fx.effectsKey
                                                tip: modelData === "PrtSc" ? win.t("Hyprland/HyDE and most desktops take PrtSc for their own screenshots: then the game never gets it") : ""
                                                onClicked: win.runGame(["fx", "shotkey", modelData], win.t("SETTING KEY…"))
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                            text: win.t("saves a screenshot with the effects to ") + (win.fx.shotsDir || "~/Pictures/ReShade")
                                                  + win.t(" · keys apply the next time the game starts")
                                        }
                                    }
                                    // must launch through the wrapper
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        visible: win.fx.wrapped === false && (win.fxReshade || win.fxActive)
                                        Text {
                                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            color: pal.amber; font.family: win.mono; font.pixelSize: 10
                                            text: win.fxUmbral ? win.t("⚠ Umbral 0.10.0 or newer is needed: it asks the deck for shaders and TEMPS before starting the game. Update Umbral.")
                                                  : win.t("⚠ This game doesn't launch through Gaming Deck yet, so the shaders won't load. ") + (win.fx.steamRunning ? win.t("Close Steam, then press USE IN STEAM.") : win.t("Press USE IN STEAM."))
                                        }
                                        MiniBtn {
                                            visible: !win.fxUmbral
                                            width: Math.max(120, implicitWidth); height: 28; label: win.t("USE IN STEAM")
                                            on: !win.gameBusy && !win.fx.steamRunning
                                            onClicked: win.runGame(["steamwrap", win.selGameId, "on"], win.t("WRAPPING…"))
                                        }
                                    }
                                }
                            }

                            // one-time setup (ReShade: no password, all user files)
                            Rectangle {
                                Layout.fillWidth: true
                                visible: win.fxGame && win.fxReshade && !!win.fx.reshade && win.fx.reshade.ready && win.fx.reshade.update
                                implicitHeight: fxRsSetup.implicitHeight + 20
                                radius: 8; color: pal.card; border.color: pal.accent; border.width: 1
                                RowLayout {
                                    id: fxRsSetup
                                    anchors.fill: parent; anchors.margins: 10; spacing: 10
                                    Text {
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        color: pal.text; font.family: win.mono; font.pixelSize: 11
                                        text: win.fx.reshade && win.fx.reshade.update
                                              ? "ReShade " + win.fx.reshade.latest + win.t(" is out (you have ") + win.fx.reshade.version + win.t("). Games pick it up on their next launch.")
                                              : win.t("One-time setup, no password: ReShade ") + ((win.fx.reshade || {}).latest || "") + win.t(" from reshade.me, d3dcompiler_47 (Mozilla's Firefox installer, checksum-verified, like winetricks) and the standard shaders.")
                                    }
                                    MiniBtn {
                                        width: Math.max(96, implicitWidth); height: 32; label: win.fx.reshade && win.fx.reshade.update ? win.t("UPDATE") : win.t("INSTALL")
                                        on: !win.gameBusy
                                        onClicked: win.runGame(["fx", "reshade", "install"], win.t("DOWNLOADING RESHADE…"))
                                    }
                                }
                            }

                            // one-time setup
                            Rectangle {
                                Layout.fillWidth: true
                                // only when it says something the steps don't: chaotic-aur missing, or half installed
                                visible: win.fxGame && !win.fxReshade && !!win.fx.gpu
                                         && ((win.fx.chaotic === false && !win.fx.vkbasalt) || (win.fx.vkbasalt && (!win.fx.vkbasalt32 || !win.fx.shadersInstalled)))
                                implicitHeight: fxSetup.implicitHeight + 20
                                radius: 8; color: pal.card; border.color: pal.accent; border.width: 1
                                RowLayout {
                                    id: fxSetup
                                    anchors.fill: parent; anchors.margins: 10; spacing: 10
                                    Text {
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        color: pal.text; font.family: win.mono; font.pixelSize: 11
                                        text: win.fx.chaotic === false && !win.fx.vkbasalt
                                              ? win.t("vkBasalt comes from chaotic-aur, which isn't enabled here. Enable it (or build vkbasalt + lib32-vkbasalt from the AUR), then come back.")
                                              : win.t("One-time setup: vkBasalt (the Vulkan layer that draws the effects, 64 + 32-bit, from chaotic-aur) and the standard ReShade shaders (official packages, ~0.5 MB). Works the same on AMD and NVIDIA.")
                                    }
                                    MiniBtn {
                                        visible: win.fx.chaotic !== false || win.fx.vkbasalt
                                        width: Math.max(96, implicitWidth); height: 32; label: win.t("INSTALL")
                                        on: !win.gameBusy
                                        onClicked: win.runGame(["fx", "install"], win.t("INSTALLING SHADERS…"))
                                    }
                                }
                            }

                            // online / anti-cheat warning
                            Rectangle {
                                Layout.fillWidth: true
                                visible: win.fxGame && !!win.fx.online && win.fx.online.level !== "none"
                                implicitHeight: fxWarn.implicitHeight + 16
                                radius: 8; border.width: 1
                                color: win.fxAnticheat ? "#1f0d14" : "#1a150c"
                                border.color: win.fxAnticheat ? pal.bad : pal.amber
                                Text {
                                    id: fxWarn
                                    anchors.fill: parent; anchors.margins: 8
                                    wrapMode: Text.WordWrap; font.family: win.mono; font.pixelSize: 10
                                    color: win.fxAnticheat ? pal.bad : pal.amber
                                    text: win.fxAnticheat
                                          ? win.t("⚠ ONLINE GAME WITH ANTI-CHEAT (") + win.fx.online.anticheats.join(", ") + win.t("). Shaders hook into the game's rendering; an anti-cheat may treat that as a modification and ban the account. Use them only if you accept that risk — applying one here asks for confirmation.")
                                          : win.t("⚠ Online multiplayer game: some online games forbid visual mods in their rules. Check before using shaders there.")
                                }
                            }

                            // route + what's active
                            Rectangle {
                                Layout.fillWidth: true
                                visible: false   // shown in the READY strip now
                                implicitHeight: fxActCol.implicitHeight + 20
                                radius: 8; color: pal.card; border.color: pal.border; border.width: 1
                                ColumnLayout {
                                    id: fxActCol
                                    anchors.fill: parent; anchors.margins: 10; spacing: 6
                                    Text {
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        font.family: win.mono; font.pixelSize: 10
                                        visible: !win.fxReshade
                                        color: (win.fx.route || {}).ok ? pal.dim : pal.bad
                                        text: ((win.fx.route || {}).ok ? "✓ " : "✗ ") + ((win.fx.route || {}).reason || "")
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            font.family: win.mono; font.pixelSize: 11; font.bold: true
                                            color: win.fxActive ? pal.ok : pal.dim
                                            text: win.fxActive
                                                  ? win.t("● ACTIVE: ") + win.fxCur.name + "  ·  " + win.fxCur.applied + win.t(" effect") + (win.fxCur.applied > 1 ? "s" : "")
                                                    + ((win.fxCur.skipped || []).length ? "  ·  " + win.fxCur.skipped.length + win.t(" skipped") : "")
                                                  : win.t("○ No shaders on this game")
                                        }
                                        Chip {
                                            visible: win.fxActive && win.fxCur.source === "sfx"
                                            label: "PRESET ↗"; onClicked: Qt.openUrlExternally(win.fxCur.url)
                                        }
                                        FxRemoveBtn { visible: win.fxActive }
                                    }
                                    Repeater {
                                        model: win.fxActive ? (win.fxCur.skipped || []) : []
                                        delegate: Text {
                                            required property var modelData
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            text: "✗ " + modelData.effect + " — " + modelData.why
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                        }
                                    }
                                    Text {
                                        visible: win.fxActive
                                        text: win.fxReshade ? win.t("In game: ") + (win.fx.key || "Home").toUpperCase() + win.t(" opens ReShade's menu — tweak values, switch effects on/off; changes are saved to this game's preset.")
                                                            : win.t("In game: ") + (win.fx.key || "Home").toUpperCase() + win.t(" turns the effects on/off to compare.")
                                        color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                    }
                                }
                            }

                            // quick looks (vkBasalt's own effects) + presets from the internet
                            Rectangle {
                                // grows only when there is a preset list to show: down to the bottom of the window, 400 at least
                                Layout.fillWidth: true
                                Layout.preferredHeight: win.fxPresets.length > 0 ? Math.max(400, fxScroll.availableHeight - fxGameCol.y - y - 4)
                                                                               : fxLooksCol.implicitHeight + 20
                                visible: win.fxGame && !!win.fx.route && (win.fx.route.ok || win.fxReshade) && win.fx.recommended !== "none"
                                radius: 8; color: pal.card; border.color: pal.border; border.width: 1
                                ColumnLayout {
                                    id: fxLooksCol
                                    anchors.fill: parent; anchors.margins: 10; spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        Text { text: win.t("QUICK LOOK"); Layout.preferredWidth: 92; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Repeater {
                                            model: [["sharpen", win.t("SHARPEN"), win.t("AMD FidelityFX CAS: crisper image, almost free")],
                                                    ["sharpen-aa", win.t("SHARPEN + AA"), win.t("SMAA anti-aliasing, then CAS sharpening")],
                                                    ["fxaa", "FXAA", win.t("Light anti-aliasing, softer edges")],
                                                    ["clarity", win.t("CLARITY"), win.t("Denoised luma sharpening: detail without boosting grain")],
                                                    ["test", win.t("TEST (B/W)"), win.t("Black and white, impossible to miss: to check the effects are drawn in this game. Then pick a real look.")]]
                                            delegate: Chip {
                                                required property var modelData
                                                property string k: "builtin:" + modelData[0]
                                                label: win.fxConfirm === k ? win.t("CONFIRM?") : modelData[1]
                                                tint: pal.ok; tip: modelData[2]
                                                active: win.fxActive && win.fxCur.source === "builtin" && win.fxCur.name === modelData[0]
                                                on: !win.gameBusy && win.fxReady
                                                onClicked: win.fxApply(k, win.t("APPLYING…"))
                                            }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        Text { text: win.t("FROM A FILE"); Layout.preferredWidth: 92; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Chip {
                                            label: fxPickProc.running || fxImpListProc.running ? win.t("OPENING…") : win.t("IMPORT…")
                                            tint: pal.ok; on: !win.gameBusy && win.fxReady && !fxPickProc.running
                                            tip: win.t("A preset you downloaded (Nexus Mods…): zip, 7z, rar or .ini. Its own shaders come along; its ReShade.ini/DLLs are ignored.")
                                            onClicked: fxPickProc.running = true
                                        }
                                        Chip {
                                            label: win.t("SEARCH NEXUS ↗"); tip: win.t("Web search for this game's ReShade presets on Nexus Mods")
                                            onClicked: Qt.openUrlExternally("https://duckduckgo.com/?q=" + encodeURIComponent("site:nexusmods.com " + win.selGameName + " reshade preset"))
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                            text: win.t("download it, then IMPORT")
                                        }
                                    }
                                    // preset pages saved for this game (can be saved before installing it)
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        Text { text: win.t("SAVED"); Layout.preferredWidth: 92; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Repeater {
                                            model: win.fx.links || []
                                            delegate: Chip {
                                                required property var modelData
                                                label: (modelData.installed ? "✓ " : "") + modelData.label + " ↗"
                                                tint: pal.ok; active: modelData.installed === true
                                                tip: (modelData.installed ? win.t("Installed: the preset in use was imported from this mod's file.") + "\n" : "")
                                                     + modelData.url + win.t(" — right-click removes it")
                                                onClicked: Qt.openUrlExternally(modelData.url)
                                                MouseArea {
                                                    anchors.fill: parent; acceptedButtons: Qt.RightButton
                                                    onClicked: win.runGame(["fx", "link", "rm", win.selGame, modelData.url], win.t("REMOVING LINK…"))
                                                }
                                            }
                                        }
                                        Text {
                                            visible: (win.fx.links || []).length === 0 && !win.fxAddLink
                                            Layout.fillWidth: true; color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                            text: win.t("preset pages you keep for this game (e.g. from Nexus)")
                                        }
                                        Item { Layout.fillWidth: true; visible: (win.fx.links || []).length > 0 && !win.fxAddLink }
                                        Chip { visible: !win.fxAddLink; label: win.t("+ LINK"); tip: win.t("Keep a preset page for this game"); onClicked: win.fxAddLink = true }
                                        Field {
                                            id: fxLinkField; Layout.fillWidth: true; font.pixelSize: 10
                                            visible: win.fxAddLink
                                            placeholderText: win.t("paste a preset page (Nexus…) to keep it here")
                                            onAccepted: if (text.trim()) { win.runGame(["fx", "link", "add", win.selGame, text.trim()], win.t("SAVING LINK…")); text = ""; }
                                        }
                                        Chip {
                                            visible: win.fxAddLink
                                            label: win.t("SAVE"); on: fxLinkField.text.trim().indexOf("https://") === 0 && !win.gameBusy
                                            onClicked: { win.runGame(["fx", "link", "add", win.selGame, fxLinkField.text.trim()], win.t("SAVING LINK…")); fxLinkField.text = ""; win.fxAddLink = false; }
                                        }
                                    }
                                    // notes of a saved page (e.g. the preset author's install guide, mapped to the deck)
                                    Repeater {
                                        model: (win.fx.links || []).filter(function (l) { return !!l.notes; })
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: noteTxt.implicitHeight + 14
                                            radius: 6; color: pal.panel; border.color: pal.border; border.width: 1
                                            Text {
                                                id: noteTxt
                                                anchors.fill: parent; anchors.margins: 7
                                                text: modelData.label + " — " + modelData.notes
                                                wrapMode: Text.WordWrap; color: pal.text; font.family: win.mono; font.pixelSize: 10
                                            }
                                        }
                                    }
                                    Flow {
                                        Layout.fillWidth: true; spacing: 6
                                        visible: win.fxImportList.length > 1
                                        Repeater {
                                            model: win.fxImportList
                                            delegate: Chip {
                                                required property var modelData
                                                label: modelData.path.replace(/^.*\//, "") + "  ·  " + modelData.effects + " fx"
                                                tip: modelData.path; tint: pal.ok
                                                on: !win.gameBusy
                                                onClicked: { var f = win.fxImportFile, pth = modelData.path; win.fxImportList = [];
                                                             win.fxApply("file:" + f, win.t("IMPORTING PRESET…"), ["fx", "import", win.selGame, f, pth]); }
                                            }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        Text {
                                            text: "PRESETS ⓘ"; Layout.preferredWidth: 92; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1
                                            MouseArea { id: presetsMa; anchors.fill: parent; hoverEnabled: true }
                                            Tip { visible: presetsMa.containsMouse; text: win.t("From SweetFX Settings DB (sfx.thelazy.net), made for ReShade") + (win.fxReshade ? "." : win.t("; in vkBasalt, effects that need the depth buffer are skipped.")) + win.t(" Shaders come from the packages the official ReShade installer lists.") }
                                        }
                                        Field {
                                            id: fxQuery; Layout.fillWidth: true; font.pixelSize: 11
                                            placeholderText: win.t("game name on SweetFX Settings DB")
                                            onAccepted: win.fxSearch(text)
                                        }
                                        Chip { label: fxSearchProc.running ? win.t("SEARCHING…") : win.t("SEARCH"); on: !fxSearchProc.running; onClicked: win.fxSearch(fxQuery.text) }
                                    }
                                    Flow {
                                        Layout.fillWidth: true; spacing: 6
                                        visible: win.fxGames.length > 1
                                        Repeater {
                                            model: win.fxGames
                                            delegate: Chip {
                                                required property var modelData
                                                label: modelData.title; active: win.fxGameId === modelData.id
                                                onClicked: win.fxLoadPresets(modelData.id)
                                            }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        visible: win.fxMsg !== ""
                                        Text {
                                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            text: win.t(win.fxMsg); color: pal.dim; font.family: win.mono; font.pixelSize: 10
                                        }
                                        Repeater {
                                            model: win.fxPresets.length > 1
                                                   ? [["new", win.t("NEWEST"), win.t("As SweetFX DB lists them: the newest first")],
                                                      ["downloads", win.t("MOST DOWNLOADED"), win.t("The most downloaded first")],
                                                      ["best", win.t("BEST"), win.t("Downloads weighed by the review: light presets go up, strong ones down, empty or old-format ones to the end")]]
                                                   : []
                                            delegate: Chip {
                                                required property var modelData
                                                label: modelData[1]; tip: modelData[2]; active: win.fxSort === modelData[0]
                                                onClicked: { win.fxSort = modelData[0]; Qt.callLater(win.fxToTop); }
                                            }
                                        }
                                    }
                                    ListView {
                                        id: fxList
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        clip: true; spacing: 3
                                        model: win.fxSorted(win.fxPresets, win.fxReviews, win.fxSort)
                                        ScrollBar.vertical: ScrollBar {}
                                        delegate: Rectangle {
                                            required property var modelData
                                            id: presetRow
                                            property string k: "sfx:" + modelData.id
                                            property var rv: win.fxReviews[modelData.id] || null
                                            width: fxList.width - 10; height: 50; radius: 6
                                            color: pal.panel; border.width: 1
                                            border.color: win.fxActive && win.fxCur.id === modelData.id ? pal.ok : pal.border
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 6; spacing: 6
                                                ColumnLayout {
                                                    Layout.fillWidth: true; spacing: 3
                                                    Text {
                                                        Layout.fillWidth: true; elide: Text.ElideRight
                                                        text: modelData.name; color: pal.text; font.family: win.mono; font.pixelSize: 11
                                                    }
                                                    // downloads · year · effects, then what the review found (hover a tag)
                                                    RowLayout {
                                                        spacing: 4
                                                        Text {
                                                            text: (modelData.downloads || 0) + win.t(" downloads") + "  ·  " + String(modelData.added || "").replace(/^.*\s(\d{4})$/, "$1")
                                                                  + (presetRow.rv ? "  ·  " + presetRow.rv.effects + win.t(" effects") : "")
                                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                                        }
                                                        Repeater {
                                                            model: {
                                                                var r = presetRow.rv;
                                                                if (r) return [{ t: win.verdictLabel(r.verdict), tone: win.verdictTone(r.verdict),
                                                                                 why: r.verdict === "empty" ? win.t("No effects in it: it changes nothing")
                                                                                    : r.verdict === "old" ? win.t("An old preset file (SweetFX or ReShade 1–2): today's ReShade can't load it") : "" }].concat(r.flags);
                                                                // made for the old SweetFX injector: not a ReShade preset
                                                                if (modelData.shader && modelData.shader !== "ReShade")
                                                                    return [{ t: win.t("OLD SWEETFX"), tone: "warn", why: win.t("Made for the old SweetFX injector, not ReShade: it can't be applied") }];
                                                                return [];
                                                            }
                                                            delegate: Rectangle {
                                                                required property var modelData
                                                                implicitWidth: rvTxt.implicitWidth + 10; implicitHeight: 14; radius: 3
                                                                color: "transparent"; border.width: 1; border.color: win.tagTone(modelData.tone)
                                                                Text { id: rvTxt; anchors.centerIn: parent; text: win.t(modelData.t); color: win.tagTone(modelData.tone); font.family: win.mono; font.pixelSize: 8; font.bold: true }
                                                                MouseArea { id: rvMa; anchors.fill: parent; hoverEnabled: true }
                                                                Tip { visible: rvMa.containsMouse && modelData.why !== ""; text: win.t(modelData.why) }
                                                            }
                                                        }
                                                        Text {
                                                            visible: !presetRow.rv && fxReviewsProc.running
                                                            text: win.t("checking what it does…"); color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                                        }
                                                    }
                                                }
                                                Chip { label: "↗"; tip: win.t("Open the preset's page"); onClicked: Qt.openUrlExternally("https://sfx.thelazy.net/games/preset/" + modelData.id + "/") }
                                                Chip {
                                                    label: win.fxConfirm === k ? win.t("CONFIRM?") : (win.fxActive && win.fxCur.id === modelData.id ? win.t("ACTIVE ✓") : win.t("APPLY"))
                                                    tint: pal.ok; on: !win.gameBusy && win.fxReady
                                                    tip: !win.fxReady ? win.t("Run INSTALL above first")
                                                         : (win.fxReshade ? win.t("Download it and fetch the shaders it needs; ReShade runs it as it is") : win.t("Download, fetch the shaders it needs and convert it for vkBasalt"))
                                                    onClicked: win.fxApply(k, win.t("APPLYING PRESET…"), ["fx", "set", win.selGame, k, win.fxGameId])
                                                }
                                            }
                                        }
                                    }
                                    Text {
                                        visible: false   // source details are in the PRESETS tooltip
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                        text: win.t("Presets: SweetFX Settings DB (sfx.thelazy.net), made for ReShade") + (win.fxReshade ? "" : win.t(" — in vkBasalt, effects that need the depth buffer are skipped")) + win.t(". Shaders: the packages the official ReShade installer lists.")
                                        color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                    }
                                }
                            }
                        }

                        // ---- MY LIBRARY: best preset + known settings for every game ----
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 8
                            visible: win.fxScope === "library"
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    color: pal.dim; font.family: win.mono; font.pixelSize: 10
                                    text: win.t("Every Steam game: the most downloaded ReShade preset on SweetFX Settings DB, the ReShade compatibility list (PCGamingWiki, which reshade.me links) and online/anti-cheat risk. SET UP installs ReShade with that preset — or SHARPEN + AA when there's none — and the depth settings the list gives. Anti-cheat games and games where ReShade is banned are never touched.")
                                }
                                Chip { label: fxScanProc.running ? win.t("SCANNING…") : win.t("SCAN"); on: !fxScanProc.running; onClicked: { fxScanProc.cached = false; fxScanProc.running = true; } }
                                MiniBtn {
                                    width: Math.max(150, implicitWidth); height: 32; label: win.t("SET UP ALL (") + win.fxEligible + ")"
                                    on: !win.gameBusy && win.fxEligible > 0
                                    onClicked: win.runGame(["fx", "autoinstall"].concat(win.fxScan.filter(function (r) { return r.eligible && !r.current; }).map(function (r) { return r.key; })), win.t("SETTING UP ") + win.fxEligible + win.t(" GAME(S)…"))
                                }
                            }
                            Repeater {
                                model: win.fxScan
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: libCol.implicitHeight + 16
                                    radius: 8; color: pal.card; border.width: 1
                                    border.color: modelData.blocked || (modelData.online && modelData.online.level === "anticheat") ? pal.bad
                                                  : (modelData.current ? pal.ok : pal.border)
                                    ColumnLayout {
                                        id: libCol
                                        anchors.fill: parent; anchors.margins: 8; spacing: 4
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.name; color: pal.text; font.family: win.mono; font.pixelSize: 12; font.bold: true }
                                            Text {
                                                visible: !!modelData.advice
                                                text: !modelData.advice ? "" : (modelData.advice.pick === "none" ? win.t("no shaders possible")
                                                      : "★ " + (modelData.advice.pick === "reshade" ? "ReShade" : "vkBasalt"))
                                                color: modelData.advice && modelData.advice.pick === "none" ? pal.dim : pal.amber
                                                font.family: win.mono; font.pixelSize: 10
                                                MouseArea { id: advMa; anchors.fill: parent; hoverEnabled: true }
                                                Tip { visible: advMa.containsMouse && !!modelData.advice; text: modelData.advice ? modelData.advice.reasons.map(win.t).join("\n") : "" }
                                            }
                                            Text {
                                                visible: !!modelData.current
                                                text: modelData.current ? "● " + (modelData.current.mode === "reshade" ? "ReShade" : "vkBasalt") + " · " + modelData.current.name : ""
                                                color: pal.ok; font.family: win.mono; font.pixelSize: 10; elide: Text.ElideRight; Layout.maximumWidth: 260
                                            }
                                            MiniBtn {
                                                width: Math.max(70, implicitWidth); height: 28; primary: false; label: win.t("OPEN")
                                                onClicked: {
                                                    var g = win.games.filter(function (x) { return x.key === modelData.key; })[0];
                                                    if (g) { win.selectGame(g); win.fxScope = "game"; win.openFx(); }
                                                }
                                            }
                                            MiniBtn {
                                                width: Math.max(80, implicitWidth); height: 28; label: win.t("SET UP")
                                                visible: modelData.eligible
                                                on: !win.gameBusy
                                                onClicked: win.runGame(["fx", "autoinstall", modelData.key], win.t("SETTING UP ") + modelData.name.toUpperCase() + "…")
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            font.family: win.mono; font.pixelSize: 10
                                            color: modelData.sfx && modelData.sfx.count > 0 ? pal.text : pal.dim
                                            visible: modelData.eligible || (modelData.sfx && modelData.sfx.count > 0)
                                            text: modelData.sfx && modelData.sfx.count > 0
                                                  ? "★ " + modelData.sfx.count + win.t(" presets · best: ") + modelData.sfx.best.name + " (" + modelData.sfx.best.downloads + win.t(" downloads)")
                                                  : win.t("No ReShade presets on SweetFX DB → SET UP uses SHARPEN + AA")
                                        }
                                        Text {
                                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            visible: !!modelData.pcgw
                                            font.family: win.mono; font.pixelSize: 9; color: modelData.blocked ? pal.bad : pal.dim
                                            text: modelData.pcgw ? "PCGamingWiki: " + modelData.pcgw.status + " · " + modelData.pcgw.api
                                                  + (modelData.defines.length ? win.t(" · depth: ") + modelData.defines.join(", ") + win.t(" (set automatically)") : "")
                                                  + (modelData.pcgw.notes ? " — " + modelData.pcgw.notes : "") : ""
                                            maximumLineCount: 3; elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            visible: modelData.blocked || (!!modelData.online && modelData.online.level !== "none")
                                            font.family: win.mono; font.pixelSize: 9
                                            color: modelData.blocked || modelData.online.level === "anticheat" ? pal.bad : pal.amber
                                            text: modelData.blocked ? win.t("✗ ReShade is banned or blocked in this game (PCGamingWiki): not touched")
                                                  : (modelData.online.level === "anticheat" ? win.t("✗ Anti-cheat (") + modelData.online.anticheats.join(", ") + win.t("): not touched")
                                                     : win.t("⚠ Has online multiplayer/co-op: fine for single-player, check the game's rules online"))
                                        }
                                        RowLayout {
                                            spacing: 6
                                            Chip {
                                                visible: !!modelData.sfx
                                                label: "PRESETS ↗"; onClicked: Qt.openUrlExternally("https://sfx.thelazy.net/games/game/" + modelData.sfx.id + "/")
                                            }
                                            Chip { label: win.t("SEARCH NEXUS ↗"); tip: win.t("Web search for ReShade presets of this game on Nexus Mods"); onClicked: Qt.openUrlExternally(modelData.nexus) }
                                            Chip {
                                                visible: !!modelData.pcgw
                                                label: "PCGW ↗"; onClicked: Qt.openUrlExternally("https://www.pcgamingwiki.com/wiki/ReShade#Compatibility_list")
                                            }
                                        }
                                    }
                                }
                            }
                            EmptyHint {
                                Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 30; anchors.centerIn: undefined
                                visible: win.fxScan.length === 0
                                title: fxScanProc.running ? win.t("SCANNING YOUR LIBRARY…") : win.t("PRESS SCAN")
                            }
                        }
                    }
                }

                // ---- HEALTH ----
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: win.gameView === "health"
                    spacing: 8

                    // summary + everything missing in one command
                    Rectangle {
                        Layout.fillWidth: true
                        visible: !!win.health.checks
                        implicitHeight: hSum.implicitHeight + 20
                        radius: 8; color: pal.card; border.width: 1
                        border.color: win.health.fail > 0 ? pal.bad : (win.health.warn > 0 ? pal.amber : pal.ok)
                        ColumnLayout {
                            id: hSum
                            anchors.fill: parent; anchors.margins: 10; spacing: 8
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    font.family: win.mono; font.pixelSize: 11; font.bold: true
                                    color: win.health.fail > 0 ? pal.bad : (win.health.warn > 0 ? pal.amber : pal.ok)
                                    text: win.health.fail > 0 || win.health.warn > 0
                                          ? [win.health.fail > 0 ? win.health.fail + win.t(" problem") + (win.health.fail > 1 ? "s" : "") : "",
                                             win.health.warn > 0 ? win.health.warn + win.t(" warning") + (win.health.warn > 1 ? "s" : "") : ""]
                                            .filter(function (x) { return x; }).join(" · ")
                                            + win.t("  —  nothing is changed from here: copy the command and run it in a terminal")
                                          : win.t("✓ Everything games need is in place (") + (win.health.vendors || []).join(", ").toUpperCase() + ")"
                                }
                                Chip { label: healthProc.running ? win.t("CHECKING…") : win.t("RECHECK"); on: !healthProc.running; onClicked: healthProc.running = true }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                visible: (win.health.installAll || "") !== ""
                                Text { text: win.t("ALL MISSING"); color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                FixLine { Layout.fillWidth: true; cmd: win.health.installAll || "" }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        radius: 8; color: pal.panel; border.color: pal.border; border.width: 1; clip: true
                        EmptyHint {
                            visible: !win.health.checks
                            title: healthProc.running ? win.t("CHECKING…") : win.t("NO DATA")
                        }
                        ListView {
                            id: healthList
                            anchors.fill: parent; anchors.margins: 6
                            clip: true; spacing: 4
                            model: win.health.checks || []
                            ScrollBar.vertical: ScrollBar {}
                            delegate: ColumnLayout {
                                required property var modelData
                                required property int index
                                width: healthList.width - 12; spacing: 4
                                property color stColor: modelData.status === "ok" ? pal.ok : (modelData.status === "fail" ? pal.bad
                                                        : (modelData.status === "warn" ? pal.amber : pal.sky))
                                Text {
                                    visible: index === 0 || healthList.model[index - 1].group !== modelData.group
                                    Layout.topMargin: index === 0 ? 2 : 8
                                    text: ({ system: win.t("SYSTEM"), driver: win.t("GPU DRIVER"), vulkan: "VULKAN", libs: win.t("32-BIT LIBRARIES"), tools: win.t("GAMING TOOLS") })[modelData.group] || modelData.group.toUpperCase()
                                    color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 2; font.bold: true
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: hRow.implicitHeight + 14
                                    radius: 6; color: pal.card; border.width: 1
                                    border.color: modelData.status === "ok" || modelData.status === "info" ? pal.border : stColor
                                    ColumnLayout {
                                        id: hRow
                                        anchors.fill: parent; anchors.margins: 7; spacing: 5
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text {
                                                text: ({ ok: "✓", fail: "✗", warn: "!", info: "i" })[modelData.status]
                                                color: stColor; font.family: win.mono; font.pixelSize: 12; font.bold: true
                                                Layout.preferredWidth: 12; horizontalAlignment: Text.AlignHCenter
                                            }
                                            Text {
                                                text: win.t(modelData.label); color: pal.text
                                                font.family: win.mono; font.pixelSize: 11
                                                Layout.preferredWidth: Math.min(implicitWidth, 260); elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                                text: win.t(modelData.detail)
                                                color: modelData.status === "ok" ? pal.dim : pal.text
                                                font.family: win.mono; font.pixelSize: 10
                                            }
                                        }
                                        FixLine {
                                            Layout.fillWidth: true; Layout.leftMargin: 20
                                            visible: modelData.fix !== ""
                                            cmd: modelData.fix
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- SHADERS ----
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: win.gameView === "shaders"
                    spacing: 8

                    Hint {
                        text: !win.shaders.drivers ? "" :
                              win.t("Drivers: ") + win.shaders.drivers.map(function (d) { return d.name + " " + d.version; }).join(" · ")
                              + (win.shaders.lastDriverUpdate ? win.t("  ·  last driver update ") + win.dateOfEpoch(win.shaders.lastDriverUpdate) : "")
                    }
                    // stale after a driver update / orphaned / Steam busy
                    Rectangle {
                        Layout.fillWidth: true
                        visible: (win.shaders.staleBytes || 0) > 0 || (win.shaders.orphanBytes || 0) > 0 || win.shaders.steamProcessing === true
                        implicitHeight: shBanner.implicitHeight + 16
                        radius: 8; color: "#1a150c"; border.color: pal.amber; border.width: 1
                        RowLayout {
                            id: shBanner
                            anchors.fill: parent; anchors.margins: 8; spacing: 8
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                color: pal.amber; font.family: win.mono; font.pixelSize: 10
                                text: (win.shaders.steamProcessing ? win.t("Steam is compiling shaders right now; cleaning waits until it finishes. ") : "")
                                      + ((win.shaders.staleBytes || 0) > 0 ? win.human(win.shaders.staleBytes) + win.t(" of driver caches weren't used since the last driver update: they are stale. ") : "")
                                      + ((win.shaders.orphanBytes || 0) > 0 ? win.human(win.shaders.orphanBytes) + win.t(" belong to games that are no longer installed.") : "")
                            }
                            MiniBtn {
                                visible: (win.shaders.staleBytes || 0) > 0
                                width: Math.max(104, implicitWidth); label: win.confirmShader === "stale" ? win.t("CONFIRM?") : win.t("CLEAN STALE")
                                on: !win.gameBusy && !win.shaders.steamProcessing
                                onClicked: win.shaderAction(["shaderclean", "stale"], "stale", win.t("CLEANING…"))
                            }
                            MiniBtn {
                                visible: (win.shaders.orphanBytes || 0) > 0
                                width: Math.max(112, implicitWidth); label: win.confirmShader === "orphans" ? win.t("CONFIRM?") : win.t("CLEAN ORPHANS")
                                on: !win.gameBusy && !win.shaders.steamProcessing
                                onClicked: win.shaderAction(["shaderclean", "orphans"], "orphans", win.t("CLEANING…"))
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        radius: 8; color: pal.panel; border.color: pal.border; border.width: 1; clip: true
                        EmptyHint {
                            visible: !win.shaders.games || (win.shaders.games.length === 0 && win.shaders.global.length === 0)
                            title: shaderProc.running ? win.t("MEASURING CACHES…") : win.t("NO SHADER CACHES")
                        }
                        ListView {
                            id: shaderList
                            anchors.fill: parent; anchors.margins: 4
                            clip: true; spacing: 3
                            model: (win.shaders.games || []).concat((win.shaders.global || []).map(function (g) {
                                return { global: true, id: g.id, name: g.label, total: g.size, stale: g.stale, path: g.path, installed: true };
                            }))
                            ScrollBar.vertical: ScrollBar {}
                            delegate: Rectangle {
                                required property var modelData
                                width: shaderList.width - 8; height: 50; radius: 8
                                color: pal.card; border.color: modelData.stale ? pal.amber : pal.border; border.width: 1
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        RowLayout {
                                            spacing: 8
                                            Text {
                                                text: modelData.global ? win.t("DRIVER") : (modelData.installed ? "STEAM" : win.t("ORPHAN"))
                                                color: modelData.global ? pal.sky : (modelData.installed ? pal.accent : pal.bad)
                                                font.family: win.mono; font.pixelSize: 8; font.bold: true; font.letterSpacing: 1
                                            }
                                            Text {
                                                text: modelData.name || (win.t("uninstalled app ") + modelData.id)
                                                color: pal.text; font.family: win.mono; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight
                                                Layout.maximumWidth: 330
                                            }
                                            Text { text: win.human(modelData.total); color: pal.amber; font.family: win.mono; font.pixelSize: 10 }
                                            Text { visible: modelData.stale === true; text: win.t("STALE"); color: pal.amber; font.family: win.mono; font.pixelSize: 8; font.bold: true }
                                            Text { visible: modelData.running === true; text: win.t("RUNNING"); color: pal.ok; font.family: win.mono; font.pixelSize: 8; font.bold: true }
                                        }
                                        Text {
                                            Layout.fillWidth: true; elide: Text.ElideRight
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                            text: modelData.global ? modelData.path
                                                  : ["pipelines " + (win.human(modelData.pipelines) || "0"),
                                                     "driver " + (win.human(modelData.driver) || "0"),
                                                     modelData.video > 0 ? "videos " + win.human(modelData.video) : "",
                                                     modelData.dxvk > 0 ? "dxvk " + win.human(modelData.dxvk) : "",
                                                     modelData.other > 0 ? win.t("other ") + win.human(modelData.other) : ""]
                                                    .filter(function (x) { return x !== ""; }).join("  ·  ")
                                        }
                                    }
                                    MiniBtn {
                                        visible: !modelData.global && modelData.driver > 0
                                        width: Math.max(92, implicitWidth); primary: false
                                        property string key: "steam:" + modelData.id + ":driver"
                                        label: win.confirmShader === key ? win.t("CONFIRM?") : win.t("DRIVER CACHE")
                                        on: !win.gameBusy && !modelData.running && !win.shaders.steamProcessing
                                        onClicked: win.shaderAction(["shaderclean", "steam:" + modelData.id, "driver"], key, win.t("CLEANING…"))
                                    }
                                    MiniBtn {
                                        width: Math.max(70, implicitWidth); tint: pal.bad
                                        property string key: (modelData.global ? "global:" + modelData.id : "steam:" + modelData.id + ":all")
                                        label: win.confirmShader === key ? win.t("CONFIRM?") : (modelData.global ? win.t("CLEAN") : win.t("ALL"))
                                        on: !win.gameBusy && !modelData.running && (modelData.global || !win.shaders.steamProcessing)
                                        onClicked: win.shaderAction(modelData.global ? ["shaderclean", "global:" + modelData.id]
                                                                                     : ["shaderclean", "steam:" + modelData.id, "all"], key, win.t("CLEANING…"))
                                    }
                                }
                            }
                        }
                    }
                    Hint {
                        text: win.t("pipelines = Steam's Fossilize recordings (driver-independent, used to pre-compile) · driver = the GPU driver's compiled cache (NVIDIA nvidiav1 / Mesa for AMD-Intel), rebuilt after every driver update. DRIVER CACHE clears only that; ALL clears the game's whole folder. Either way the next launches stutter a little while caches rebuild.")
                    }
                }

                // ---- STATUS ----
                ScrollView {
                    id: stScroll
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: win.gameView === "status"
                    contentWidth: availableWidth
                    clip: true

                    component StatRow: RowLayout {
                        property string label
                        property string value
                        property color tone: pal.text
                        property string note: ""
                        Layout.fillWidth: true; spacing: 8
                        Text { text: label; Layout.preferredWidth: 112; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                        Text { text: value; color: tone; font.family: win.mono; font.pixelSize: 11; elide: Text.ElideRight; Layout.maximumWidth: 260 }
                        Text { Layout.fillWidth: true; text: note; color: pal.dim; font.family: win.mono; font.pixelSize: 9; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                    }
                    component Meter: RowLayout {
                        property string label
                        property real value: 0
                        property real max: 1
                        property string text: ""
                        property real warnAt: 0.85
                        Layout.fillWidth: true; spacing: 8
                        Text { text: label; Layout.preferredWidth: 112; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                        Rectangle {
                            Layout.fillWidth: true; height: 8; radius: 4; color: pal.logBg; border.color: pal.border; border.width: 1
                            Rectangle {
                                height: parent.height; radius: 4
                                width: parent.width * Math.max(0, Math.min(1, max > 0 ? value / max : 0))
                                color: max > 0 && value / max >= warnAt ? pal.amber : pal.accent
                            }
                        }
                        Text { text: parent.text; Layout.preferredWidth: 150; horizontalAlignment: Text.AlignRight; color: pal.text; font.family: win.mono; font.pixelSize: 10 }
                    }
                    component Card: Rectangle {
                        property string title
                        property string sub: ""
                        default property alias content: cardCol.data
                        Layout.fillWidth: true
                        implicitHeight: cardCol.implicitHeight + 20
                        radius: 8; color: pal.card; border.color: pal.border; border.width: 1
                        ColumnLayout {
                            id: cardCol
                            anchors.fill: parent; anchors.margins: 10; spacing: 6
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text { text: title; color: pal.text; font.family: win.mono; font.pixelSize: 10; font.bold: true; font.letterSpacing: 2 }
                                Text { Layout.fillWidth: true; text: sub; color: pal.dim; font.family: win.mono; font.pixelSize: 10; elide: Text.ElideRight }
                            }
                        }
                    }
                    // one live series (last 5 minutes while STATUS is open)
                    component Spark: ColumnLayout {
                        id: spark
                        property string label
                        property var values: []
                        property real max: 100
                        property string current: ""
                        property color tint: pal.accent
                        // equal columns: same small preferred width, then fill
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 10; spacing: 2
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: spark.label; color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                            Item { Layout.fillWidth: true }
                            Text { text: spark.current; color: pal.text; font.family: win.mono; font.pixelSize: 10; font.bold: true }
                        }
                        Canvas {
                            id: cv
                            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 40
                            onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                            Connections { target: spark; function onValuesChanged() { cv.requestPaint(); } }
                            onPaint: {
                                var c = getContext("2d"); c.reset();
                                c.fillStyle = pal.logBg; c.fillRect(0, 0, width, height);
                                c.strokeStyle = pal.border; c.lineWidth = 1;
                                for (var g = 1; g < 4; g++) { var gy = Math.round(height * g / 4) + 0.5; c.beginPath(); c.moveTo(0, gy); c.lineTo(width, gy); c.stroke(); }
                                var v = spark.values, n = 100;
                                if (!v || v.length < 2) return;
                                var step = width / (n - 1), x0 = width - (v.length - 1) * step;
                                function yOf(val) { return height - 2 - (height - 4) * Math.max(0, Math.min(1, val / spark.max)); }
                                c.beginPath(); c.moveTo(x0, height);
                                for (var i = 0; i < v.length; i++) c.lineTo(x0 + i * step, yOf(v[i]));
                                c.lineTo(width, height); c.closePath();
                                c.fillStyle = Qt.rgba(spark.tint.r, spark.tint.g, spark.tint.b, 0.18); c.fill();
                                c.beginPath();
                                for (var j = 0; j < v.length; j++) { if (j === 0) c.moveTo(x0, yOf(v[0])); else c.lineTo(x0 + j * step, yOf(v[j])); }
                                c.strokeStyle = spark.tint; c.lineWidth = 1.5; c.stroke();
                            }
                        }
                    }

                    ColumnLayout {
                        width: stScroll.availableWidth
                        height: Math.max(implicitHeight, stScroll.availableHeight)
                        spacing: 8

                        // running game (left) · displays (right)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: runRow.implicitHeight + 16
                            radius: 8; color: pal.card; border.width: 1
                            border.color: (win.gstat.running || []).length ? pal.ok : pal.border
                            RowLayout {
                                id: runRow
                                anchors.fill: parent; anchors.margins: 8; spacing: 12
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 4
                                    RowLayout {
                                        spacing: 8
                                        Text { text: win.t("RUNNING NOW"); color: pal.text; font.family: win.mono; font.pixelSize: 10; font.bold: true; font.letterSpacing: 2 }
                                        Text {
                                            visible: !(win.gstat.running || []).length
                                            text: win.t("no game  ·  Steam ") + ((win.gstat.tools || {}).steam ? win.t("open") : win.t("closed"))
                                            color: pal.dim; font.family: win.mono; font.pixelSize: 10
                                        }
                                    }
                                    Repeater {
                                        model: win.gstat.running || []
                                        delegate: RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true; spacing: 10
                                            Text { text: "●"; color: pal.ok; font.pixelSize: 10 }
                                            Text { text: win.gameName(modelData.id); color: pal.text; font.family: win.mono; font.pixelSize: 12; font.bold: true }
                                            Text {
                                                Layout.fillWidth: true; elide: Text.ElideRight
                                                color: pal.dim; font.family: win.mono; font.pixelSize: 10
                                                text: [modelData.uptime != null ? win.durationText(modelData.uptime) : "",
                                                       modelData.proton ? modelData.proton : "",
                                                       modelData.fx ? modelData.fx + " on" : "",
                                                       win.gstat.gamemode && win.gstat.gamemode.active ? win.t("GameMode active") : "",
                                                       "pid " + modelData.pid].filter(function (x) { return x; }).join("  ·  ")
                                            }
                                            // Umbral 0.11+ closes its games on request (and their wineserver)
                                            MiniBtn {
                                                visible: modelData.key.indexOf("umbral:") === 0
                                                property string ck: "stop:" + modelData.key
                                                width: Math.max(70, implicitWidth); height: 26; tint: pal.bad
                                                primary: win.confirmShader === ck
                                                label: win.confirmShader === ck ? win.t("CONFIRM?") : win.t("■ STOP")
                                                on: !win.gameBusy
                                                onClicked: win.shaderAction(["gstop", modelData.key], ck, win.t("CLOSING…"))
                                            }
                                        }
                                    }
                                }
                                Rectangle { width: 1; Layout.fillHeight: true; color: pal.border; visible: (win.gstat.displays || []).length > 0 }
                                ColumnLayout {
                                    spacing: 2
                                    Repeater {
                                        model: win.gstat.displays || []
                                        delegate: RowLayout {
                                            required property var modelData
                                            spacing: 8
                                            Text { text: modelData.name + (modelData.focused ? " ●" : ""); color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1 }
                                            Text { text: modelData.width + "×" + modelData.height + " @ " + Math.round(modelData.hz) + " Hz"; color: pal.text; font.family: win.mono; font.pixelSize: 11 }
                                            Text {
                                                text: modelData.vrr ? "VRR on" : "VRR off"; color: modelData.vrr ? pal.ok : pal.dim
                                                font.family: win.mono; font.pixelSize: 10
                                                MouseArea { id: vrrMa; anchors.fill: parent; hoverEnabled: true }
                                                Tip { visible: vrrMa.containsMouse; text: modelData.vrr ? win.t("Variable refresh rate (FreeSync / G-Sync) is on.") : win.t("Variable refresh rate is off. In Hyprland, misc:vrr turns it on (2 = fullscreen apps only, good for games).") }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // row 1: GPU | CPU · memory (same height)
                        GridLayout {
                            id: stRow1
                            Layout.fillWidth: true
                            columns: stScroll.availableWidth > 780 ? 2 : 1
                            columnSpacing: 8; rowSpacing: 8
                            property real cardH: columns === 2 ? Math.max(gpuCard.implicitHeight, cpuCard.implicitHeight) : -1

                            Card {
                                id: gpuCard
                                Layout.preferredHeight: stRow1.cardH > 0 ? stRow1.cardH : implicitHeight
                                title: "GPU"; sub: win.shortGpu((win.gstat.gpu || {}).name)
                                StatRow { label: win.t("DRIVER"); value: (win.gstat.gpu || {}).driver || "?" }
                                Meter {
                                    label: win.t("LOAD"); value: (win.gstat.gpu || {}).load || 0; max: 100; warnAt: 2
                                    text: (win.gstat.gpu || {}).load != null ? win.gstat.gpu.load + " %" : "—"
                                }
                                Meter {
                                    label: "VRAM"; value: (win.gstat.gpu || {}).vramUsed || 0; max: (win.gstat.gpu || {}).vramTotal || 0
                                    text: (win.gstat.gpu || {}).vramTotal ? win.human(win.gstat.gpu.vramUsed) + " / " + win.human(win.gstat.gpu.vramTotal) : "—"
                                }
                                Meter {
                                    label: win.t("POWER"); value: (win.gstat.gpu || {}).power || 0; max: (win.gstat.gpu || {}).powerLimit || 0
                                    text: (win.gstat.gpu || {}).power != null ? Math.round(win.gstat.gpu.power) + " W"
                                          + ((win.gstat.gpu || {}).powerLimit ? " / " + Math.round(win.gstat.gpu.powerLimit) + " W" : "") : "—"
                                }
                                StatRow {
                                    label: win.t("TEMPERATURE"); value: (win.gstat.gpu || {}).temp != null ? win.gstat.gpu.temp + " °C" : "—"
                                    tone: (win.gstat.gpu || {}).temp >= 85 ? pal.bad : ((win.gstat.gpu || {}).temp >= 75 ? pal.amber : pal.text)
                                }
                                StatRow {
                                    label: win.t("CLOCK")
                                    value: (win.gstat.gpu || {}).clock != null ? win.gstat.gpu.clock + " MHz"
                                           + ((win.gstat.gpu || {}).clockMax ? " / " + win.gstat.gpu.clockMax : "") : "—"
                                    note: (win.gstat.gpu || {}).pstate ? win.t("state ") + win.gstat.gpu.pstate : ""
                                }
                                StatRow {
                                    visible: ((win.gstat.gpu || {}).limits || []).length > 0
                                    label: win.t("HELD BACK BY")
                                    value: ((win.gstat.gpu || {}).limits || []).join(", ")
                                    tone: ((win.gstat.gpu || {}).limits || []).some(function (x) { return /thermal|slowdown|brake/.test(x); }) ? pal.amber : pal.text
                                    note: ((win.gstat.gpu || {}).limits || []).indexOf("idle") >= 0 ? win.t("nothing heavy to render right now")
                                          : (((win.gstat.gpu || {}).limits || []).indexOf("power cap") >= 0 ? win.t("at its power limit: normal under load, odd at idle") : "")
                                }
                                Item { Layout.fillHeight: true }
                            }

                            Card {
                                id: cpuCard
                                Layout.preferredHeight: stRow1.cardH > 0 ? stRow1.cardH : implicitHeight
                                title: win.t("CPU · MEMORY"); sub: (win.gstat.system || {}).cpu || ""
                                StatRow {
                                    label: "CPU"
                                    value: ((win.gstat.system || {}).threads || "?") + win.t(" threads · ") + ((win.gstat.system || {}).mhz || "?") + " MHz"
                                           + ((win.gstat.system || {}).temp != null ? " · " + win.gstat.system.temp + " °C" : "")
                                    note: (win.gstat.system || {}).load != null ? win.t("load ") + win.gstat.system.load : ""
                                    tone: (win.gstat.system || {}).temp >= 85 ? pal.bad : ((win.gstat.system || {}).temp >= 75 ? pal.amber : pal.text)
                                }
                                StatRow {
                                    label: "GOVERNOR"
                                    value: (win.gstat.governor || "?") + " (" + (win.gstat.cpufreq_driver || "?") + ")"
                                    note: win.gstat.gamemode && win.gstat.gamemode.active ? win.t("GameMode has it on performance") : win.t("GameMode switches it to performance while you play")
                                }
                                Meter {
                                    label: "RAM"; value: (win.gstat.system || {}).memUsed || 0; max: (win.gstat.system || {}).memTotal || 0
                                    text: (win.gstat.system || {}).memTotal ? win.human(win.gstat.system.memUsed) + " / " + win.human(win.gstat.system.memTotal) : "—"
                                }
                                Meter {
                                    label: (win.gstat.system || {}).zram ? "SWAP (ZRAM)" : "SWAP"
                                    value: (win.gstat.system || {}).swapUsed || 0; max: (win.gstat.system || {}).swapTotal || 0
                                    text: (win.gstat.system || {}).swapTotal ? win.human(win.gstat.system.swapUsed) + " / " + win.human(win.gstat.system.swapTotal) : "none"
                                }
                                StatRow { label: "KERNEL"; value: (win.gstat.system || {}).kernel || "?" }
                                StatRow {
                                    property var sc: win.gstat.sched || {}
                                    label: win.t("SCHEDULER")
                                    value: sc.running && sc.current ? "sched-ext: " + sc.current : win.t("kernel default (EEVDF)")
                                    note: !win.gstat.sched ? win.t("scx-tools not installed")
                                          : [sc.whilePlaying ? win.t("while playing: ") + sc.whilePlaying.replace(":", " · ") : "",
                                             sc.bootDefault ? win.t("at boot: ") + sc.bootDefault + (sc.bootMode ? " · " + sc.bootMode : "") : ""]
                                            .filter(function (x) { return x; }).join("  ·  ")
                                }
                                // lavd's Gaming mode: now, only while a game runs, or at every boot
                                Flow {
                                    Layout.fillWidth: true; spacing: 6
                                    visible: !!win.gstat.sched
                                    property var sc: win.gstat.sched || {}
                                    Chip {
                                        label: parent.sc.running ? win.t("STOP") : win.t("LAVD GAMING NOW")
                                        on: !win.gameBusy
                                        tip: parent.sc.running ? win.t("Back to the kernel's scheduler (asks for your password)")
                                             : win.t("scx_lavd in Gaming mode until you stop it or reboot (asks for your password)")
                                        onClicked: win.runGame(parent.sc.running ? ["sched", "stop"] : ["sched", "start", "lavd", "gaming"], win.t("SCHEDULER…"))
                                    }
                                    Chip {
                                        label: win.t("WHILE PLAYING"); tint: pal.ok; active: parent.sc.whilePlaying === "lavd:gaming"
                                        on: !win.gameBusy
                                        tip: win.t("lavd Gaming starts with each game and stops when it closes (only if no scheduler was running)")
                                        onClicked: win.runGame(["sched", "playing", parent.sc.whilePlaying ? "off" : "lavd:gaming"], win.t("SAVING…"))
                                    }
                                    Chip {
                                        label: win.confirmSched === "boot" ? win.t("CONFIRM?") : win.t("AT BOOT")
                                        tint: pal.ok; active: parent.sc.bootDefault === "lavd"
                                        on: !win.gameBusy
                                        tip: win.t("Writes default_sched in /etc/scx_loader.toml (password): lavd Gaming from every boot")
                                        onClicked: {
                                            if (win.confirmSched !== "boot") { win.confirmSched = "boot"; return; }
                                            win.confirmSched = "";
                                            win.runGame(parent.sc.bootDefault === "lavd" ? ["sched", "boot", "none"] : ["sched", "boot", "lavd", "Gaming"], win.t("SCHEDULER…"));
                                        }
                                    }
                                    Chip {
                                        label: win.confirmSched === "nopass" ? win.t("CONFIRM?") : win.t("NO PASSWORD")
                                        tint: pal.ok; active: parent.sc.noPassword === true
                                        on: !win.gameBusy
                                        tip: win.t("A polkit rule so your user switches schedulers without a password (needed for WHILE PLAYING without prompts)")
                                        onClicked: {
                                            if (win.confirmSched !== "nopass") { win.confirmSched = "nopass"; return; }
                                            win.confirmSched = "";
                                            win.runGame(["sched", "nopassword", parent.sc.noPassword ? "off" : "on"], win.t("SCHEDULER…"));
                                        }
                                    }
                                }
                                StatRow {
                                    label: "MAX_MAP_COUNT"; value: String(win.gstat.max_map_count || "?")
                                    tone: win.gstat.max_map_count_ok ? pal.text : pal.amber
                                    note: win.gstat.max_map_count_ok ? win.t("≥ 1048576: enough for any game") : win.t("below 1048576: some games crash (see HEALTH)")
                                }
                                Item { Layout.fillHeight: true }
                            }
                        }

                        // while playing: notifications held, Hyprland without effects
                        Card {
                            Layout.fillWidth: true
                            title: win.t("WHILE PLAYING")
                            sub: win.t("from the first game that starts until the last one closes")
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                property var pl: win.gstat.playing || ({})
                                Chip {
                                    label: (parent.pl.quiet ? "✓ " : "") + win.t("HOLD NOTIFICATIONS")
                                    tint: pal.ok; active: !!parent.pl.quiet; on: !win.gameBusy && (!!parent.pl.notifier || !!parent.pl.quiet)
                                    tip: parent.pl.notifier === "swaync" ? win.t("Do Not Disturb in swaync while you play; notifications wait in its panel")
                                       : parent.pl.notifier === "dunst" ? win.t("Pauses dunst while you play; what arrived shows when the game closes")
                                       : win.t("Needs dunst or swaync running")
                                    onClicked: win.runGame(["playing", "quiet", parent.pl.quiet ? "off" : "on"], win.t("SAVING…"))
                                }
                                Chip {
                                    label: (parent.pl.lite ? "✓ " : "") + win.t("NO ANIMATIONS / BLUR")
                                    tint: pal.ok; active: !!parent.pl.lite; on: !win.gameBusy && (!!parent.pl.hyprland || !!parent.pl.lite)
                                    tip: parent.pl.hyprland ? win.t("Hyprland animations, blur and shadows off while you play, back as they were after")
                                                            : win.t("Only on Hyprland")
                                    onClicked: win.runGame(["playing", "lite", parent.pl.lite ? "off" : "on"], win.t("SAVING…"))
                                }
                                Text {
                                    Layout.fillWidth: true; color: pal.dim; font.family: win.mono; font.pixelSize: 9; elide: Text.ElideRight
                                    text: win.t("Games launched through the deck (Steam) or Umbral 0.10+.")
                                }
                            }
                        }
                        // last game sessions (recorded while each game ran)
                        Card {
                            Layout.fillWidth: true
                            title: win.t("LAST SESSIONS")
                            sub: (win.gstat.sessions || []).length ? "" : win.t("play a game: a summary appears here when it closes")
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text {
                                    Layout.fillWidth: true; color: pal.dim; font.family: win.mono; font.pixelSize: 9
                                    text: win.t("Temperatures, load and power are sampled every 5 s while a game runs (Steam through the deck, Umbral 0.10+).")
                                }
                                Chip {
                                    label: win.gstat.sessionSummary === false ? win.t("SUMMARY OFF") : win.t("✓ SUMMARY")
                                    tint: pal.ok; active: win.gstat.sessionSummary !== false; on: !win.gameBusy
                                    tip: win.t("Record each game session and notify a summary when it ends")
                                    onClicked: win.runGame(["sessions", win.gstat.sessionSummary === false ? "on" : "off"], win.t("SAVING…"))
                                }
                            }
                            Repeater {
                                model: win.gstat.sessions || []
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true; spacing: 10
                                    Text { text: modelData.name; color: pal.text; font.family: win.mono; font.pixelSize: 11; elide: Text.ElideRight; Layout.preferredWidth: 190 }
                                    Text {
                                        text: new Date(modelData.start * 1000).toLocaleString(Qt.locale(), "dd/MM HH:mm") + " · " + win.durationText(modelData.duration)
                                        color: pal.dim; font.family: win.mono; font.pixelSize: 10; Layout.preferredWidth: 150
                                    }
                                    Text {
                                        Layout.fillWidth: true; elide: Text.ElideRight
                                        font.family: win.mono; font.pixelSize: 10
                                        color: (modelData.gpuTempMax || 0) >= 85 || (modelData.cpuTempMax || 0) >= 90 ? pal.amber : pal.text
                                        text: [modelData.gpuTempMax != null ? "GPU " + modelData.gpuTempMax + "°" : "",
                                               modelData.cpuTempMax != null ? "CPU " + modelData.cpuTempMax + "°" : "",
                                               modelData.gpuLoadAvg != null ? win.t("load ") + Math.round(modelData.gpuLoadAvg) + "%" : "",
                                               modelData.gpuPowerMax != null ? Math.round(modelData.gpuPowerMax) + " W" : "",
                                               modelData.vramMax != null ? "VRAM " + (modelData.vramMax / 1024).toFixed(1) + " GB" : ""]
                                              .filter(function (x) { return x; }).join("  ·  ")
                                    }
                                    // GPU temperature over the session
                                    Canvas {
                                        width: 90; height: 18
                                        property var pts: modelData.gpuTempLine || []
                                        onPaint: {
                                            var c = getContext("2d"); c.reset();
                                            var v = pts.filter(function (x) { return x != null; });
                                            if (v.length < 2) return;
                                            var lo = Math.min.apply(null, v) - 2, hi = Math.max.apply(null, v) + 2;
                                            c.strokeStyle = pal.amber; c.lineWidth = 1.2; c.beginPath();
                                            for (var i = 0; i < v.length; i++) {
                                                var x = i * (width - 1) / (v.length - 1), y = height - 1 - (height - 2) * (v[i] - lo) / (hi - lo);
                                                if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
                                            }
                                            c.stroke();
                                        }
                                    }
                                }
                            }
                        }

                        // row 2: tools + library (left) | live history (fills the rest of the tab)
                        GridLayout {
                            id: stRow2
                            Layout.fillWidth: true; Layout.fillHeight: true
                            columns: stScroll.availableWidth > 780 ? 2 : 1
                            columnSpacing: 8; rowSpacing: 8

                            ColumnLayout {
                            Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                            Layout.fillHeight: stRow2.columns === 2
                            spacing: 8
                            Card {
                                title: win.t("GAMING TOOLS")
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    StatRow {
                                        label: "GAMEMODE"
                                        value: !win.gstat.gamemode ? "" : (!win.gstat.gamemode.installed ? win.t("not installed")
                                               : ((win.gstat.tools || {}).gamemode || "") + (win.gstat.gamemode.active ? win.t(" · active") : win.t(" · idle")))
                                        tone: win.gstat.gamemode && win.gstat.gamemode.installed ? pal.text : pal.amber
                                        note: !win.gstat.gamemode ? "" : (win.gstat.gamemode.ingroup ? win.t("in the gamemode group")
                                              : (win.gstat.gamemode.pending ? win.t("group added: log out and back in") : win.t("not in the gamemode group: it can't switch the governor")))
                                    }
                                    MiniBtn {
                                        visible: !!win.gstat.gamemode && !win.gstat.gamemode.ingroup && !win.gstat.gamemode.pending
                                        width: Math.max(96, implicitWidth); height: 26; label: win.confirmJoin ? win.t("CONFIRM?") : win.t("JOIN GROUP")
                                        on: !win.gameBusy
                                        onClicked: {
                                            if (!win.confirmJoin) { win.confirmJoin = true; return; }
                                            win.confirmJoin = false;
                                            win.runGame(["gamejoin"], win.t("JOINING…"));
                                        }
                                    }
                                }
                                StatRow { label: win.t("MANGOHUD"); value: win.gstat.mangohud ? ((win.gstat.tools || {}).mangohud || "installed") : win.t("not installed"); tone: win.gstat.mangohud ? pal.text : pal.amber }
                                StatRow { label: "GAMESCOPE"; value: win.gstat.gamescope ? ((win.gstat.tools || {}).gamescope || "installed") : win.t("not installed (optional)") }
                                StatRow { label: "STEAM"; value: (win.gstat.tools || {}).steam ? win.t("running") : win.t("closed"); note: ((win.gstat.tools || {}).protons || 0) + win.t(" Proton builds available") }
                                StatRow { label: "NTSYNC"; value: (win.gstat.tools || {}).ntsync ? win.t("available") : win.t("not available"); note: win.t("kernel sync for Wine/Proton") }
                                StatRow {
                                    label: "SHADERS"
                                    value: [(win.gstat.tools || {}).reshade ? "ReShade " + win.gstat.tools.reshade : "",
                                            (win.gstat.tools || {}).vkbasalt ? "vkBasalt " + win.gstat.tools.vkbasalt.replace(/-[^-]*$/, "") : ""]
                                           .filter(function (x) { return x; }).join(" · ") || win.t("none installed")
                                    note: "GAMING → FX"
                                }
                            }

                            Card {
                                Layout.fillHeight: stRow2.columns === 2
                                property var lib: win.gstat.library || {}
                                title: win.t("LIBRARY · STORAGE")
                                sub: lib.games ? lib.games.steam + " Steam · " + lib.games.umbral + " Umbral · " + lib.games.wrapped + win.t(" through the deck · ") + lib.games.fx + win.t(" with shaders") : ""
                                Repeater {
                                    model: (win.gstat.library || {}).disks || []
                                    delegate: Meter {
                                        required property var modelData
                                        label: win.t("DISK ") + modelData.mount
                                        value: modelData.size - modelData.free; max: modelData.size; warnAt: 0.9
                                        text: win.human(modelData.free) + win.t(" free of ") + win.human(modelData.size)
                                    }
                                }
                                StatRow {
                                    label: win.t("SHADER CACHES")
                                    value: (win.gstat.library || {}).shaders ? win.human(win.gstat.library.shaders.total) : "—"
                                    note: (win.gstat.library || {}).shaders && (win.gstat.library.shaders.stale + win.gstat.library.shaders.orphan) > 0
                                          ? win.human(win.gstat.library.shaders.stale + win.gstat.library.shaders.orphan) + win.t(" can be cleaned (SHADERS)") : win.t("nothing to clean")
                                }
                                StatRow {
                                    label: "PREFIXES"
                                    value: (win.gstat.library || {}).prefixes ? win.human(win.gstat.library.prefixes.total) + " · " + win.gstat.library.prefixes.count : "—"
                                    note: (win.gstat.library || {}).prefixes && win.gstat.library.prefixes.orphans > 0
                                          ? win.gstat.library.prefixes.orphans + win.t(" orphan(s) (PREFIXES)") : win.t("no orphans")
                                }
                                StatRow {
                                    label: win.t("GPU DRIVER")
                                    value: (win.gstat.library || {}).driverUpdate ? win.t("updated ") + win.dateOfEpoch(win.gstat.library.driverUpdate) : "—"
                                    note: (win.gstat.library || {}).driverPkgs || ""
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    StatRow {
                                        label: win.t("HEALTH")
                                        property var h: (win.gstat.library || {}).health || {}
                                        value: h.fail === undefined ? "—" : (h.fail === 0 && h.warn === 0 ? win.t("all good")
                                               : [h.fail ? h.fail + win.t(" problem(s)") : "", h.warn ? h.warn + win.t(" warning(s)") : ""].filter(function (x) { return x; }).join(" · "))
                                        tone: h.fail > 0 ? pal.bad : (h.warn > 0 ? pal.amber : pal.ok)
                                    }
                                    Chip { label: win.t("HEALTH →"); onClicked: { win.gameView = "health"; healthProc.running = true; } }
                                }
                                Text { text: win.t("RECENTLY PLAYED"); color: pal.dim; font.family: win.mono; font.pixelSize: 9; font.letterSpacing: 1; Layout.topMargin: 4 }
                                Repeater {
                                    model: (win.gstat.library || {}).recent || []
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true; spacing: 8
                                        Text { text: modelData.name; color: pal.text; font.family: win.mono; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                        Text { text: win.playtimeText(modelData.minutes * 60); color: pal.dim; font.family: win.mono; font.pixelSize: 10 }
                                        Text { text: win.dateOfEpoch(modelData.last); color: pal.dim; font.family: win.mono; font.pixelSize: 10; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
                                    }
                                }
                                Item { Layout.fillHeight: true }
                            }
                            }

                            Card {
                                Layout.fillHeight: true; Layout.minimumHeight: 230
                                title: win.t("LIVE"); sub: win.t("last 5 minutes while STATUS is open")
                                GridLayout {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    columns: 2; columnSpacing: 10; rowSpacing: 8
                                    Spark {
                                        label: win.t("GPU LOAD"); values: win.stHist.gpuLoad; max: 100
                                        current: (win.gstat.gpu || {}).load != null ? win.gstat.gpu.load + " %" : "—"
                                    }
                                    Spark {
                                        label: "GPU °C"; values: win.stHist.gpuTemp; max: 100; tint: pal.amber
                                        current: (win.gstat.gpu || {}).temp != null ? win.gstat.gpu.temp + " °C" : "—"
                                    }
                                    Spark {
                                        label: "CPU °C"; values: win.stHist.cpuTemp; max: 100; tint: pal.pink
                                        current: (win.gstat.system || {}).temp != null ? win.gstat.system.temp + " °C" : "—"
                                    }
                                    Spark {
                                        label: win.t("RAM · VRAM %"); values: win.stHist.ram; max: 100; tint: pal.sky
                                        current: Math.round(win.stHist.ram.length ? win.stHist.ram[win.stHist.ram.length - 1] : 0) + " % · "
                                                 + Math.round(win.stHist.vram.length ? win.stHist.vram[win.stHist.vram.length - 1] : 0) + " %"
                                    }
                                }
                            }
                        }
                    }
                }

                LogBox {
                    Layout.fillWidth: true; base: 150
                    visible: win.gameLog !== ""
                    content: win.gameLog
                }

                // ---- MAINTENANCE: GE-Proton · game clean-up · backup · Gaming Deck itself ----
                Flickable {
                    id: maintPage
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: win.gameView === "maint"
                    clip: true; contentWidth: width; contentHeight: maintCol.implicitHeight + 8
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    ColumnLayout {
                        id: maintCol
                        width: maintPage.width - 14; spacing: 14

                        // GE-Proton
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: geCol.implicitHeight + 28
                            radius: 12; color: pal.card; border.color: pal.border; border.width: 1
                            ColumnLayout {
                                id: geCol; anchors.fill: parent; anchors.margins: 14; spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    Text { text: "GE-PROTON"; color: pal.text; font.family: win.mono; font.pixelSize: 12; font.bold: true; font.letterSpacing: 3 }
                                    Text {
                                        Layout.fillWidth: true; color: pal.dim; font.family: win.mono; font.pixelSize: 11
                                        text: (win.proton.installed ? win.t("installed: ") + win.proton.installed : win.t("not installed"))
                                              + (win.proton.latest ? win.t("  ·  latest: ") + win.proton.latest : "")
                                    }
                                    MiniBtn {
                                        width: Math.max(110, implicitWidth); height: 32
                                        label: !win.proton.installed ? win.t("INSTALL") : (win.proton.update ? win.t("UPDATE") : win.t("UP TO DATE ✓"))
                                        on: !win.gameBusy && !!win.proton.latest && (!win.proton.installed || win.proton.update === true)
                                        onClicked: win.runGame(["proton", "install"], win.t("INSTALLING GE-PROTON…"))
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap; color: pal.dim; font.family: win.mono; font.pixelSize: 10
                                    text: win.t("Proton with extra game fixes, and the FSR 4 / DLSS / XeSS upgrades of UPSCALE. Checksum-verified; restart Steam to see it.")
                                }
                            }
                        }

                        // game clean-up
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: clCol.implicitHeight + 28
                            radius: 12; color: pal.card; border.color: pal.border; border.width: 1
                            ColumnLayout {
                                id: clCol; anchors.fill: parent; anchors.margins: 14; spacing: 8
                                Text { text: win.t("CLEAN"); color: pal.text; font.family: win.mono; font.pixelSize: 12; font.bold: true; font.letterSpacing: 3 }
                                Text {
                                    visible: win.gclean.length === 0
                                    text: gcleanProc.running ? win.t("SCANNING…") : ""; color: pal.dim; font.family: win.mono; font.pixelSize: 10
                                }
                                Repeater {
                                    model: win.gclean
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true; spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 2
                                            Text {
                                                text: win.t(modelData.title) + (modelData.count > 0 ? "  ·  " + modelData.count + (modelData.size ? "  ·  " + modelData.size : "") : "")
                                                color: modelData.count > 0 ? pal.text : pal.dim; font.family: win.mono; font.pixelSize: 12; font.bold: true
                                            }
                                            Text {
                                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                                text: modelData.details ? modelData.details : win.t(modelData.desc)
                                                color: pal.dim; font.family: win.mono; font.pixelSize: 10
                                            }
                                        }
                                        MiniBtn {
                                            width: Math.max(84, implicitWidth); height: 30
                                            label: modelData.count === 0 ? "OK ✓" : (win.confirmClean === modelData.id ? win.t("CONFIRM?") : win.t("CLEAN"))
                                            primary: modelData.count > 0; on: modelData.count > 0 && !win.gameBusy
                                            onClicked: {
                                                if (win.confirmClean !== modelData.id) { win.confirmClean = modelData.id; return; }
                                                win.confirmClean = ""; win.runGame(["clean", modelData.id], win.t("CLEANING…"));
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // backup of profiles, looks and settings
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: bkCol.implicitHeight + 28
                            radius: 12; color: pal.card; border.color: pal.border; border.width: 1
                            ColumnLayout {
                                id: bkCol; anchors.fill: parent; anchors.margins: 14; spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Text { Layout.fillWidth: true; text: win.t("BACKUP"); color: pal.text; font.family: win.mono; font.pixelSize: 12; font.bold: true; font.letterSpacing: 3 }
                                    MiniBtn { width: Math.max(96, implicitWidth); height: 32; label: win.t("EXPORT"); on: !win.gameBusy; onClicked: win.runGame(["export"], win.t("EXPORTING…")) }
                                    MiniBtn { width: Math.max(96, implicitWidth); height: 32; label: win.t("IMPORT…"); primary: false; on: !win.gameBusy; onClicked: importPickProc.running = true }
                                }
                                Text {
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap; color: pal.dim; font.family: win.mono; font.pixelSize: 10
                                    text: win.t("Game profiles, shader looks, saved preset pages, keys and the CPU scheduler setting, to ~/gaming-deck-backup-<date>.json. IMPORT adds what this PC lacks (a Control Deck backup works too); then CHECK FOR THIS PC in LIBRARY adapts it.")
                                }
                                // what the last EXPORT / IMPORT did
                                Rectangle {
                                    Layout.fillWidth: true; Layout.topMargin: 2
                                    visible: win.bkResult.what !== undefined
                                    implicitHeight: bkRes.implicitHeight + 20; radius: 8
                                    color: Qt.rgba(0, 0, 0, 0.18); border.width: 1
                                    border.color: win.bkResult.ok ? pal.ok : pal.bad
                                    RowLayout {
                                        id: bkRes; anchors.fill: parent; anchors.margins: 10; spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 3
                                            Text {
                                                Layout.fillWidth: true; font.family: win.mono; font.pixelSize: 11; font.bold: true
                                                color: win.bkResult.ok ? pal.ok : pal.bad
                                                text: !win.bkResult.ok ? win.t("✘ It didn't work") : (win.bkResult.what === "export" ? win.t("✔ Backup saved") : win.t("✔ Backup imported"))
                                            }
                                            Text {
                                                Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; color: pal.text; font.family: win.mono; font.pixelSize: 10
                                                visible: text !== ""; text: win.bkResult.file || ""
                                            }
                                            Text {
                                                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: pal.dim; font.family: win.mono; font.pixelSize: 10
                                                text: (win.bkResult.lines || []).filter(function (x) { return x.indexOf("Backup saved to") < 0; }).map(function (x) { return x.replace(/^\s*[✔→]?\s*/, ""); }).join("\n")
                                                visible: text !== ""
                                            }
                                        }
                                        MiniBtn {
                                            width: Math.max(110, implicitWidth); height: 30; primary: false
                                            visible: win.bkResult.ok === true && (win.bkResult.file || "") !== ""
                                            label: win.t("OPEN FOLDER")
                                            onClicked: Qt.openUrlExternally("file://" + String(win.bkResult.file).replace(/^~/, win.home).replace(/\/[^\/]*$/, ""))
                                        }
                                    }
                                }
                            }
                        }

                        // Gaming Deck itself
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: upCol.implicitHeight + 28
                            radius: 12; color: pal.card; border.width: 1; border.color: win.deckNew.new ? pal.amber : pal.border
                            ColumnLayout {
                                id: upCol; anchors.fill: parent; anchors.margins: 14; spacing: 8
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    Text { text: "GAMING DECK"; color: pal.text; font.family: win.mono; font.pixelSize: 12; font.bold: true; font.letterSpacing: 3 }
                                    Text {
                                        Layout.fillWidth: true; color: win.deckNew.new ? pal.amber : pal.dim; font.family: win.mono; font.pixelSize: 11
                                        text: win.deckVersion + (win.deckNew.new ? win.t("  →  new version ") + win.deckNew.new : win.t("  ·  up to date"))
                                    }
                                    MiniBtn {
                                        width: Math.max(96, implicitWidth); height: 32; label: win.t("UPDATE")
                                        on: !win.gameBusy && !!win.deckNew.new
                                        onClicked: win.runGame(["selfupdate"], win.t("UPDATING…"))
                                    }
                                }
                            }
                        }
                    }
                }

            }
        }
    }
}
