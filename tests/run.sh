#!/usr/bin/env bash
# Gaming Deck test suite.
#
# Runs the backend inside a throw-away $HOME with stubbed system tools
# (pacman, pkexec, flatpak, systemctl, curl, …): no root, no network, and
# nothing on the real system is touched.  Usage:  tests/run.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CD="$ROOT/bin/gaming-deck"
T="$(mktemp -d)"
trap 'pkill -f -- "$T/fake/" 2>/dev/null; rm -rf "$T"' EXIT

export HOME="$T/home"
export GAMING_DECK_UMBRAL_RUNNING="$T/umbral-running.json"   # never the real one
export GAMING_DECK_SCX_RULE_OLD="$T/no-old-rule"   # never this PC's /etc
export GAMING_DECK_WEB_PID="$T/web.pid"   # never the real guide browser
export GAMING_DECK_WEB_HELPER="$T/no-web-helper"   # …nor ever started (guides go to the xdg-open stub)
export GAMING_DECK_PANEL_QML="$T/no-panel.qml"   # never a real panel (install.sh puts one in the test $HOME)
export GAMING_DECK_FX_EXTRA_PACKAGES="$T/fx-extra.json"; echo "[]" > "$T/fx-extra.json"   # community packs: none unless a test adds one
# Nexus's list of games: a local one (never the network)
export GAMING_DECK_NEXUS_GAMES_URL="file://$T/nexus-games.json"
echo '[{"name":"Elden Ring","domain_name":"eldenring"},{"name":"Lords of the Fallen","domain_name":"lordsofthefallen"},{"name":"Lords of the Fallen (2023)","domain_name":"lordsofthefallen2023"},{"name":"Hogwarts Legacy","domain_name":"hogwartslegacy"}]' > "$T/nexus-games.json"
unset XDG_DATA_HOME XDG_CACHE_HOME XDG_CONFIG_HOME GAMING_DECK_APPS_DIR INSTALL_ANY_APPS_DIR GITHUB_TOKEN
export LC_ALL=C.UTF-8
mkdir -p "$HOME" "$T/bin" "$T/dl" "$T/fake" "$T/sys"
A="$HOME/.local/share/applications"

# ---------------------------------------------------------------- stubs ----
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/bin/$1"; chmod +x "$T/bin/$1"; }
stub pkexec 'echo "pkexec $*" >> "'"$T"'/pkexec.log"; exit 1'
stub notify-send 'echo "notify-send $*" >> "'"$T"'/notify.log"'
stub update-desktop-database 'exit 0'
stub curl 'out="" q="" prev=""; for a in "$@"; do
    case "$prev" in -o) out="$a" ;; --data-urlencode) q="${a#*=}" ;; esac
    case "$a" in file://*|http://*|https://*) url="$a" ;; esac; prev="$a"; done
[[ -z "${url:-}" ]] && for a in "$@"; do url="$a"; done
# -G --data-urlencode query=X on file:// → <path>q_<X>.json
[[ -n "$q" && "$url" == file://* ]] && url="${url}q_${q// /_}.json"
url="${url%%#*}"; [[ "$url" == file://*/ ]] && url="${url}index.html"
[[ -n "$out" ]] && exec > "$out"
case "$url" in
    file://*)    cat "${url#file://}" ;;
    */compare/*) [[ -n "${FAKE_COMPARE:-}" ]] && cat "$FAKE_COMPARE" || exit 22 ;;
    *)           exit 7 ;;
esac'
stub yay 'exit 0'
stub paru 'exit 0'
stub gio 'exit 0'
stub snapper 'echo "snapper $*" >> "'"$T"'/snapper.log"
case "$*" in
    *"--jsonout list"*) [[ -n "${FAKE_SNAPLIST:-}" ]] && cat "$FAKE_SNAPLIST" ;;
esac'
stub gtk-update-icon-cache 'exit 0'
stub steam 'echo "steam $*" >> "'"$T"'/steam.log"'
stub mangohud 'exec "$@"'
stub umbral 'echo "umbral $*" >> "'"$T"'/umbral.log"'
stub pgrep '[[ -n "${FAKE_FOSSILIZE:-}" && "$*" == *fossilize* ]] && exit 0; exit 1'
stub xdg-open 'exit 0'
stub checkupdates 'printf "%s" "${FAKE_UPDATES:-}"'
stub ldconfig '[[ "${FAKE_FUSE2:-1}" == 1 ]] && echo "	libfuse.so.2 (libc6,x86-64) => /usr/lib/libfuse.so.2"; exit 0'
stub pacman 'case "$1" in
    -Q)  [[ "$2" == snap-pac && "${FAKE_SNAPPAC:-1}" == 1 ]]; exit $? ;;
    -Fq) [[ "$2" == libgtk-3.so.0 ]] && echo extra/gtk3 ;;
    -Si) [[ "$2" == python-requests ]] && exit 0; exit 1 ;;
    -Qoq) exit 1 ;;
    -R)  [[ "$2" == --print && "$3" == bundled-app ]] && { echo "error: failed to prepare transaction (could not satisfy dependencies)" >&2
             echo ":: removing bundled-app breaks dependency '"'"'bundled-app'"'"' required by some-bundle"; exit 1; } ;;
esac
exit 0'
stub flatpak 'case "$1" in
    info) [[ "$2" == --show-permissions ]] && cat "'"$T"'/fp-perms" ;;
    override) echo "flatpak $*" >> "'"$T"'/flatpak.log" ;;
esac
exit 0'
stub systemctl 'echo "systemctl $*" >> "'"$T"'/systemctl.log"
case "$*" in
    *"enable --now"*)  touch "'"$T"'/timer-on" ;;
    *"disable --now"*) rm -f "'"$T"'/timer-on" ;;
    *is-enabled*)      [[ -f "'"$T"'/timer-on" ]] ;;
    *is-active*)       exit 0 ;;
esac'
export PATH="$T/bin:$PATH"

# -------------------------------------------------------------- helpers ----
pass=0 failed=0
ok()  { pass=$((pass + 1)); printf '  \e[32m✔\e[0m %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf '  \e[31m✘ %s\e[0m\n' "$1"; [[ -n "${2:-}" ]] && printf '      %s\n' "${2:0:400}"; }
eq()  { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected «$3», got «$2»"; fi; }
has() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "«$3» not in: $2"; fi; }
hasnt() { if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1" "«$3» should not be in: $2"; fi; }
yes() { if eval "$2"; then ok "$1"; else bad "$1" "failed: $2"; fi; }
section() { printf '\n\e[1m%s\e[0m\n' "$1"; }
key() { awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$1"; }
# shellcheck source=bin/gaming-deck
fn() { ( source "$CD"; "$@" ); }   # call an internal function

# 1x1 PNG
PNG_B64='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='

# fake AppImage: answers --appimage-extract like the real runtime does
# make_appimage <path> <name> [fuse2]
make_appimage() {
    cat > "$1" <<EOF
#!/usr/bin/env bash
# fake AppImage runtime for tests ${3:+(dlopen libfuse.so.2)}
if [[ "\$1" == --appimage-extract ]]; then
    r=squashfs-root; mkdir -p "\$r/usr/share/icons/hicolor/256x256/apps" "\$r/usr/share/applications"
    printf '[Desktop Entry]\nType=Application\nName=$2\nExec=AppRun --no-sandbox %%U\nIcon=fakeapp\nCategories=Development;\nStartupWMClass=FakeApp\n' \
        > "\$r/usr/share/applications/fakeapp.desktop"
    ln -sf usr/share/applications/fakeapp.desktop "\$r/fakeapp.desktop"
    echo '$PNG_B64' | base64 -d > "\$r/usr/share/icons/hicolor/256x256/apps/fakeapp.png"
    exit 0
fi
exec sleep 30
EOF
    chmod +x "$1"
}

desktop() {   # desktop <file> <name> <exec>
    mkdir -p "$(dirname "$1")"
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n' "$2" "$3" > "$1"
}

# ==========================================================================
section "CLI"
"$CD" help >/dev/null; eq "help exits 0" "$?" 0
"$CD" nope >/dev/null 2>&1; eq "unknown command exits 2" "$?" 2

section "Version & self-update"
PATH="$T/bin:$PATH" "$ROOT/install.sh" --no-deps >/dev/null 2>&1; eq "install.sh works in a clean HOME" "$?" 0
HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)"
yes "the test checkout is a readable git repo" "[[ -n '$HEAD_SHA' ]]"
eq "installed commit recorded" "$("$CD" version | key /dev/stdin COMMIT)" "$HEAD_SHA"
eq "source repo recorded" "$("$CD" version | key /dev/stdin SRC)" "$ROOT"
yes "GUI is installed last" "[[ \"$(grep -n 'shell.qml\" \"\$HOME' "$ROOT/install.sh" | cut -d: -f1)\" -gt \"$(grep -n 'install.env\"$' "$ROOT/install.sh" | cut -d: -f1)\" ]]"
printf '{"status":"ahead","ahead_by":2,"commits":[{"sha":"aaaaaaa111"},{"sha":"bbbbbbb222"}]}' > "$T/compare.json"
eq "newer version on GitHub is offered" "$(FAKE_COMPARE="$T/compare.json" "$CD" selfcheck | jq -r .new)" "bbbbbbb (+2)"
printf '{"status":"identical","ahead_by":0,"commits":[]}' > "$T/compare.json"
eq "nothing offered when up to date" "$(FAKE_COMPARE="$T/compare.json" "$CD" selfcheck)" '{}'

section "Gaming: Steam library"
ST="$T/steam"; export GAMING_DECK_STEAM_ROOT="$ST" GAMING_DECK_STEAM_RUNNING=0
mkdir -p "$ST/steamapps/compatdata/100" "$ST/steamapps/common/Proton - Experimental" \
         "$ST/userdata/42/config" "$ST/config" "$ST/compatibilitytools.d/GE-Proton9-1"
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' "$ST" > "$ST/steamapps/libraryfolders.vdf"
man() { printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n\t"installdir"\t\t"%s"\n\t"SizeOnDisk"\t\t"%s"\n}\n' "$1" "$2" "$3" "$4" > "$ST/steamapps/appmanifest_$1.acf"; }
man 100 "Game \"Quoted\" One" GameOne 1000
man 200 "Second Game" SecondGame 2000
man 1493710 "Proton Experimental" "Proton - Experimental" 5
cat > "$ST/userdata/42/config/localconfig.vdf" <<'EOF'
"UserLocalConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"apps"
				{
					"100"
					{
						"LastPlayed"		"1790758987"
						"LaunchOptions"		"PROTON_ENABLE_WAYLAND=0 mangohud gamemoderun %command% -novid +fps_max 120"
						"BadgeData"		"0200"
					}
					"200"
					{
						"Playtime"		"5"
					}
				}
			}
		}
	}
}
EOF
cat > "$ST/config/config.vdf" <<'EOF'
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"AutoUpdateWindowEnabled"		"0"
			}
		}
	}
}
EOF
cat > "$ST/compatibilitytools.d/GE-Proton9-1/compatibilitytool.vdf" <<'EOF'
"compatibilitytools"
{
  "compat_tools"
  {
    "GE-Proton9-1" // Internal name of this tool
    {
      "install_path" "."
      "display_name" "GE-Proton9-1"
    }
  }
}
EOF
LC="$ST/userdata/42/config/localconfig.vdf"; CFG="$ST/config/config.vdf"
G="$("$CD" games)"
eq "tools (Proton) are not listed as games" "$(jq length <<<"$G")" 2
eq "escaped quotes in names are decoded" "$(jq -r '.[] | select(.id == "100") | .name' <<<"$G")" 'Game "Quoted" One'
eq "launch options read" "$(jq -r '.[] | select(.id == "100") | .launch' <<<"$G")" "PROTON_ENABLE_WAYLAND=0 mangohud gamemoderun %command% -novid +fps_max 120"
eq "prefix detected" "$(jq -r '.[] | select(.id == "100") | .prefix' <<<"$G")" true
TOOLS="$("$CD" compattools)"
eq "Proton tools: Experimental + GE (comment after the name ignored)" "$(jq -r 'map(.name) | join(",")' <<<"$TOOLS")" "proton_experimental,GE-Proton9-1"

section "Gaming: Steam launch options through the wrapper"
GAMING_DECK_STEAM_RUNNING=1 "$CD" steamwrap 100 on >/dev/null 2>&1; eq "refuses while Steam is running" "$?" 3
"$CD" steamwrap 100 on >/dev/null
has "Steam launches it through the deck" "$(bash -c 'source "$1"; vdf_get "$2" UserLocalConfigStore/Software/Valve/Steam/apps/100 LaunchOptions' _ "$CD" "$LC")" "gaming-deck run %command%"
eq "other keys untouched" "$(bash -c 'source "$1"; vdf_get "$2" UserLocalConfigStore/Software/Valve/Steam/apps/100 BadgeData' _ "$CD" "$LC")" "0200"
yes "backup written" "[[ -f '$LC.gaming-deck.bak' ]]"
PR="$("$CD" gprofile get steam:100)"
eq "old options adopted: env"      "$(jq -r '.env.PROTON_ENABLE_WAYLAND' <<<"$PR")" 0
eq "old options adopted: mangohud" "$(jq -r '.mangohud' <<<"$PR")" true
eq "old options adopted: args"     "$(jq -r '.args' <<<"$PR")" "-novid +fps_max 120"
"$CD" steamwrap 100 off >/dev/null
# a profile saved BEFORE wrapping must still get the old options merged in
"$CD" gprofile reset steam:100 >/dev/null
has "messages name the game, not its key" "$("$CD" gprofile set steam:100 mangohud=false 'env=MY_VAR=1')" 'Profile of Game "Quoted" One saved'
"$CD" steamwrap 100 on >/dev/null
PR="$("$CD" gprofile get steam:100)"
eq "pre-existing profile: old env merged in" "$(jq -r '.env.PROTON_ENABLE_WAYLAND' <<<"$PR")" 0
eq "pre-existing profile: its own env kept"  "$(jq -r '.env.MY_VAR' <<<"$PR")" 1
eq "pre-existing profile: empty args filled" "$(jq -r '.args' <<<"$PR")" "-novid +fps_max 120"
eq "pre-existing profile: mangohud from the old line" "$(jq -r '.mangohud' <<<"$PR")" true
"$CD" steamwrap 200 on >/dev/null
has "missing LaunchOptions key is created" "$(bash -c 'source "$1"; vdf_get "$2" UserLocalConfigStore/Software/Valve/Steam/apps/200 LaunchOptions' _ "$CD" "$LC")" "gaming-deck run"
eq "…next to the existing keys" "$(bash -c 'source "$1"; vdf_get "$2" UserLocalConfigStore/Software/Valve/Steam/apps/200 Playtime' _ "$CD" "$LC")" 5
"$CD" steamwrap 100 off >/dev/null
eq "off restores the original options" "$(bash -c 'source "$1"; vdf_get "$2" UserLocalConfigStore/Software/Valve/Steam/apps/100 LaunchOptions' _ "$CD" "$LC")" "PROTON_ENABLE_WAYLAND=0 mangohud gamemoderun %command% -novid +fps_max 120"
"$CD" steamwrap 200 off >/dev/null
hasnt "off removes options that weren't there" "$(cat "$LC")" "gaming-deck run"
eq "file still has balanced braces" "$(grep -c '{' "$LC")" "$(grep -c '}' "$LC")"

section "Gaming: Proton version per game"
"$CD" steamcompat 200 GE-Proton9-1 >/dev/null
eq "mapping block created" "$(bash -c 'source "$1"; vdf_get "$2" InstallConfigStore/Software/Valve/Steam/CompatToolMapping/200 name' _ "$CD" "$CFG")" GE-Proton9-1
eq "games shows it" "$("$CD" games | jq -r '.[] | select(.id == "200") | .compat')" GE-Proton9-1
"$CD" steamcompat 200 NotAProton >/dev/null 2>&1; eq "unknown tool refused" "$?" 2
"$CD" steamcompat 200 default >/dev/null
hasnt "default removes the mapping" "$(cat "$CFG")" '"200"'
eq "config braces balanced" "$(grep -c '{' "$CFG")" "$(grep -c '}' "$CFG")"

section "Gaming: profiles + run wrapper"
"$CD" gprofile set steam:200 nice=5 >/dev/null 2>&1;            eq "nice out of range refused" "$?" 2
"$CD" gprofile set steam:200 'env=BAD-NAME=1' >/dev/null 2>&1;  eq "bad env name refused" "$?" 2
"$CD" gprofile set steam:200 'prefix=gamescope; rm' >/dev/null 2>&1; eq "shell syntax in prefix refused" "$?" 2
"$CD" gprofile set steam:200 gamemode=true mangohud=false 'env=FOO=bar DXVK_HUD=fps' 'args=-windowed' >/dev/null
stub gamemoderun 'echo "gamemoderun" >> "'"$T"'/wrap.log"; exec "$@"'
printf '#!/bin/sh\necho "FOO=$FOO HUD=$DXVK_HUD args=$*"\n' > "$T/fake/game"; chmod +x "$T/fake/game"
O="$(SteamAppId=200 "$CD" run "$T/fake/game" -launcher)"
eq "wrapper applies env and appends args" "$O" "FOO=bar HUD=fps args=-launcher -windowed"
has "wrapper goes through gamemoderun" "$(cat "$T/wrap.log")" gamemoderun
O="$("$CD" run --profile default -- "$T/fake/game")"
eq "no Steam id → default profile" "$O" "FOO= HUD= args="
"$CD" gprofile set steam:200 'prefix=er-patcher-missing --' >/dev/null
O="$(SteamAppId=200 "$CD" run "$T/fake/game" 2>&1)"
eq "a PREFIX program that isn't installed is skipped: the game still starts" "$O" "FOO=bar HUD=fps args=-windowed"
"$CD" gprofile reset steam:200 >/dev/null
eq "reset drops the custom profile" "$("$CD" gprofile get steam:200 | jq -r .custom)" false

section "Gaming: status + ProtonDB"
mkdir -p "$T/proc/4242" "$T/proc/4243" "$T/proc/99"
printf 'HOME=/x\0SteamAppId=100\0' > "$T/proc/4243/environ"; printf 'SteamAppId=100\0' > "$T/proc/4242/environ"
printf 'SteamAppId=0\0' > "$T/proc/99/environ"
eq "running game found once (lowest pid), id 0 ignored" "$(PROC_ROOT="$T/proc" bash -c 'source "$1"; running_games' _ "$CD")" "$(printf '100\t4242')"
yes "gstatus is valid JSON" "\"$CD\" gstatus | jq -e '.gamemode | has(\"ingroup\") and has(\"pending\")' >/dev/null"
mkdir -p "$T/pdb"; printf '{"tier":"platinum","score":0.9,"total":10,"trendingTier":"gold","confidence":"strong"}' > "$T/pdb/100.json"
export GAMING_DECK_PROTONDB_API="file://$T/pdb"
eq "ProtonDB tier" "$("$CD" protondb 100 200 | jq -r '."100".tier')" platinum
eq "missing summary → unknown" "$("$CD" protondb 200 | jq -r '."200".tier')" unknown
rm "$T/pdb/100.json"
eq "cached for a day" "$("$CD" protondb 100 | jq -r '."100".tier')" platinum
unset GAMING_DECK_PROTONDB_API GAMING_DECK_STEAM_ROOT GAMING_DECK_STEAM_RUNNING

section "Gaming: launch-option suggestions (ProtonDB open data)"
NOW=$(date +%s); OLD=$(( NOW - 5 * 365 * 86400 ))
rep() { printf '{"app":{"steam":{"appId":"%s"}},"timestamp":%s,"responses":{"verdict":"%s","launchOptions":%s},"systemInfo":{"gpu":"%s"}}' "$1" "$2" "$3" "$4" "$5"; }
{
    echo '['
    for i in 1 2 3 4 5 6 7 8; do rep 100 "$NOW" yes '"%command% -vulkan +fps_max 120"' "NVIDIA GeForce RTX 2070"; echo ,; done
    rep 100 "$NOW" yes '"PROTON_ENABLE_WAYLAND=1 gamemoderun %command% -vulkan +fps_max 120"' "NVIDIA GeForce RTX 3080"; echo ,
    rep 100 "$NOW" yes '"PROTON_ENABLE_WAYLAND=1 gamemoderun %command% -vulkan"' "AMD Radeon RX 6800"; echo ,
    rep 100 "$NOW" yes '"RADV_PERFTEST=\"gpl,nggc\" %command% -vulkan"' "AMD Radeon RX 7900"; echo ,
    rep 100 "$NOW" yes '"RADV_PERFTEST=\"gpl,nggc\" ~/lsfg %command%"' "AMD Radeon RX 7900"; echo ,
    rep 100 "$NOW" no  '"-dx11 %command%"' "NVIDIA GeForce GTX 1060"; echo ,
    rep 100 "$NOW" no  '"-dx11 %command%"' "NVIDIA GeForce GTX 1060"; echo ,
    rep 100 "$OLD" yes '"-oldflag %command%"' "NVIDIA GeForce GTX 970"; echo ,
    rep 100 "$OLD" yes '"-oldflag %command%"' "NVIDIA GeForce GTX 970"; echo ,
    rep 300 "$NOW" yes '"%command% -windowed"' "Intel Arc"; echo ,
    rep 300 "$NOW" yes '"%command% -windowed"' "Intel Arc"; echo ,
    rep 200 "$NOW" yes '""' "NVIDIA"
    echo ']'
} > "$T/reports_piiremoved.json"
mkdir -p "$T/pdbdump"; (cd "$T" && tar czf "$T/pdbdump/reports_sep1_2026.tar.gz" reports_piiremoved.json)
export GAMING_DECK_GPU_VENDOR=nvidia GAMING_DECK_GPU_NAME="NVIDIA GeForce RTX 2070" GAMING_DECK_SCREEN="" GAMING_DECK_SCREEN_HZ=""   # never this PC's screen
eq "no index → says so" "$("$CD" gsuggest 100 | jq -r .index)" false
GAMING_DECK_PDB_RAW="file://$T/pdbdump" GAMING_DECK_PDB_DUMP=reports_sep1_2026.tar.gz "$CD" pdbindex update >/dev/null 2>&1
eq "index built (reports with launch options only)" "$("$CD" pdbindex status | jq -r .reports)" 18
eq "games counted" "$("$CD" pdbindex status | jq -r .games)" 2
S="$("$CD" gsuggest 100)"
sug() { jq -r --arg t "$1" '[.suggestions[] | select(.token == $t)] | first | if . == null then "none" else "\(.share)/\(.vshare)/\(.foryou)" end' <<<"$S"; }
eq "only working, recent reports (12 of 16)" "$(jq -r .reports <<<"$S")" 12
eq "-vulkan: share / NVIDIA share / fits" "$(sug -vulkan)" "91/100/true"
eq "+cvar value kept as one option" "$(sug '+fps_max 120')" "75/100/true"
eq "env var suggested" "$(sug PROTON_ENABLE_WAYLAND=1)" "16/11/true"
has "each option says what it does" "$(jq -r '.suggestions[] | select(.token == "PROTON_ENABLE_WAYLAND=1") | .what' <<<"$S")" "native Wayland window"
eq "…an unknown launch option gets the generic text" "$(jq -r '.suggestions[] | select(.token == "-vulkan") | .what' <<<"$S")" "A launch option passed to the game itself: what it does depends on the game."
eq "suggested programs say whether they are installed" "$(bash -c 'source "$1"; sug_mark_installed' _ "$CD" <<<'{"suggestions":[{"kind":"wrapper","token":"bash"},{"kind":"wrapper","token":"er-patcher-missing --x"},{"kind":"env","token":"A=1"}]}' | jq -c '[.suggestions[].installed]')" '[true,false,null]'
eq "AMD-only variable hidden on NVIDIA (0 % of NVIDIA players)" "$(sug RADV_PERFTEST=gpl,nggc)" none
eq "…and shown on AMD, quotes stripped" "$(GAMING_DECK_GPU_VENDOR=amd GAMING_DECK_GPU_NAME="AMD Radeon RX 7900 XTX" "$CD" gsuggest 100 | jq -r '.suggestions[] | select(.token == "RADV_PERFTEST=gpl,nggc") | .foryou')" true
# shellcheck disable=SC2088  # a literal "~/lsfg" token, as players write it
eq "personal paths never suggested" "$(sug '~/lsfg')" none
eq "reports saying it doesn't work are ignored" "$(sug -dx11)" none
eq "reports older than 3 years ignored when there are enough recent ones" "$(sug -oldflag)" none
eq "wrapper suggested" "$(sug gamemoderun)" "16/11/true"
eq "few reports → all-time window" "$("$CD" gsuggest 300 | jq -r '.window + " " + (.suggestions[0].token)')" "all -windowed"
unset GAMING_DECK_GPU_VENDOR GAMING_DECK_GPU_NAME GAMING_DECK_SCREEN GAMING_DECK_SCREEN_HZ

section "Gaming: suggestions adapt to this PC's hardware"
gen() { bash -c 'source "$1"; jq -Rr "$JQ_GPU_GEN"" gpu_gen" <<<"$2"' _ "$CD" "$1"; }
eq "RTX 2070 → NVIDIA gen 3"            "$(gen 'NVIDIA GeForce RTX 2070')" nvidia:3
eq "GTX 1660 = same gen as RTX 20"      "$(gen 'NVIDIA GeForce GTX 1660 SUPER')" nvidia:3
eq "RX 9070 XT → AMD gen 5 (RDNA4)"     "$(gen 'AMD Radeon RX 9070 XT')" amd:5
eq "Steam Deck = RDNA2 like RX 6000"    "$(gen 'AMD Custom GPU 0405 (vangogh)')" amd:3
eq "unknown GPU → no generation"        "$(gen 'Intel UHD Graphics 630')" ""
# a game where the right option depends on the GPU generation and on the CPU
{
    echo '['
    for i in 1 2 3 4 5 6; do rep 400 "$NOW" yes '"%command% -vulkan -threads 32"' "NVIDIA GeForce RTX 2080"; echo ,; done
    for i in 1 2 3 4 5 6; do rep 400 "$NOW" yes '"%command% -dx11 -w 1770 -h 996"' "NVIDIA GeForce RTX 4090"; echo ,; done
    for i in 1 2 3 4 5 6; do rep 400 "$NOW" yes '"RADV_PERFTEST=gpl mangohud %command%"' "AMD Radeon RX 9070 XT"; echo ,; done
    rep 400 "$NOW" yes '"%command% -threads 6"' "AMD Radeon RX 7800 XT"
    echo ']'
} > "$T/reports_piiremoved.json"
(cd "$T" && tar czf "$T/pdbdump/reports_oct1_2026.tar.gz" reports_piiremoved.json)
GAMING_DECK_PDB_RAW="file://$T/pdbdump" GAMING_DECK_PDB_DUMP=reports_oct1_2026.tar.gz "$CD" pdbindex update >/dev/null 2>&1
hw() { GAMING_DECK_GPU_NAME="$1" GAMING_DECK_GPU_VENDOR="$2" GAMING_DECK_SCREEN="$3" "$CD" gsuggest 400; }
R="$(jq -r '[.suggestions[] | select(.recommended) | .token] | join(",")' <<<"$(hw 'NVIDIA GeForce RTX 2070' nvidia 1920x1080)")"
has   "RTX 2070: -vulkan recommended (RTX 20-30 players)" "$R" "-vulkan"
hasnt "RTX 2070: RTX 40 players' -dx11 not recommended"   "$R" "-dx11"
eq    "RTX 2070: -threads adapted to this CPU" "$(hw 'NVIDIA GeForce RTX 2070' nvidia 1920x1080 | jq -r '.suggestions[] | select(.key == "-threads #") | .token')" "-threads $(nproc)"
R="$(jq -r '[.suggestions[] | select(.recommended) | .token] | join(",")' <<<"$(hw 'NVIDIA GeForce RTX 4090' nvidia 2560x1440)")"
has   "RTX 4090: -dx11 recommended" "$R" "-dx11"
eq    "resolution adapted to this screen" "$(hw 'NVIDIA GeForce RTX 4090' nvidia 2560x1440 | jq -r '[.suggestions[] | select(.key == "-w #" or .key == "-h #") | .token] | sort | join(" ")')" "-h 1440 -w 2560"
eq    "no screen known → resolution options dropped" "$(hw 'NVIDIA GeForce RTX 4090' nvidia '' | jq '[.suggestions[] | select(.key == "-w #")] | length')" 0
R="$(jq -r '[.suggestions[] | select(.recommended) | .token] | join(",")' <<<"$(hw 'AMD Radeon RX 9070 XT' amd 1920x1080)")"
has   "RX 9070 XT: AMD-only variable recommended there" "$R" "RADV_PERFTEST=gpl"
hasnt "RX 9070 XT: NVIDIA players' -vulkan not recommended" "$R" "-vulkan"
eq    "…and hidden on NVIDIA" "$(hw 'NVIDIA GeForce RTX 2070' nvidia 1920x1080 | jq '[.suggestions[] | select(.token == "RADV_PERFTEST=gpl")] | length')" 0
eq    "similar-hardware label" "$(hw 'NVIDIA GeForce RTX 2070' nvidia 1920x1080 | jq -r .similarLabel)" "GTX 10, RTX 20 / GTX 16, RTX 30"
eq    "library badge counts recommended options" "$(GAMING_DECK_GPU_NAME='NVIDIA GeForce RTX 2070' GAMING_DECK_GPU_VENDOR=nvidia GAMING_DECK_SCREEN=1920x1080 "$CD" gtips 400 | jq -r '."400"')" 2
# env vars vs their default, numeric options grouped, fps cap → refresh rate
{
    echo '['
    for i in 1 2 3 4; do rep 500 "$NOW" yes '"PROTON_ENABLE_WAYLAND=1 %command%"' "NVIDIA GeForce RTX 2070"; echo ,; done
    for f in 144 60 240 144 144; do rep 500 "$NOW" yes "\"%command% +fps_max $f\"" "NVIDIA GeForce RTX 2080"; echo ,; done
    rep 500 "$NOW" yes '"%command% -foo"' "NVIDIA GeForce RTX 3070"; echo ,
    rep 500 "$NOW" yes '"%command% -foo"' "NVIDIA GeForce RTX 3070"; echo ,
    for i in 1 2 3 4 5 6; do rep 600 "$NOW" yes '"DXVK_ASYNC=1 %command%"' "NVIDIA GeForce RTX 2070"; echo ,; done
    for i in 1 2 3 4; do rep 600 "$NOW" yes '"%command% -bar"' "NVIDIA GeForce RTX 2070"; echo ,; done
    rep 600 "$NOW" yes '"%command% -bar"' "NVIDIA GeForce RTX 2070"
    echo ']'
} > "$T/reports_piiremoved.json"
(cd "$T" && tar czf "$T/pdbdump/reports_nov1_2026.tar.gz" reports_piiremoved.json)
GAMING_DECK_PDB_RAW="file://$T/pdbdump" GAMING_DECK_PDB_DUMP=reports_nov1_2026.tar.gz "$CD" pdbindex update >/dev/null 2>&1
g5() { GAMING_DECK_GPU_NAME='NVIDIA GeForce RTX 2070' GAMING_DECK_GPU_VENDOR=nvidia GAMING_DECK_SCREEN=1920x1080 GAMING_DECK_SCREEN_HZ="$2" "$CD" gsuggest "$1"; }
eq "env var set by a minority: not recommended (most keep the default)" "$(g5 500 120 | jq -r '.suggestions[] | select(.var == "PROTON_ENABLE_WAYLAND") | "\(.pct)/\(.unset)/\(.recommended)"')" "36/63/false"
eq "env var set by most players: recommended" "$(g5 600 120 | jq -r '.suggestions[] | select(.var == "DXVK_ASYNC") | "\(.pct)/\(.recommended)"')" "54/true"
eq "+fps_max values grouped and set to this monitor's refresh rate" "$(g5 500 120 | jq -r '.suggestions[] | select(.key == "+fps_max #") | "\(.token) \(.pct)% \(.recommended)"')" "+fps_max 120 45% true"
eq "refresh rate unknown → the most common value" "$(g5 500 '' | jq -r '.suggestions[] | select(.key == "+fps_max #") | .token')" "+fps_max 144"

section "Gaming: new games are recognised"
export GAMING_DECK_STEAM_ROOT="$ST" GAMING_DECK_STEAM_RUNNING=0
rm -f "$HOME/.local/share/gaming-deck/gaming/known-games.txt"
"$CD" games >/dev/null; sleep 0.3
eq "first run: nothing is new" "$("$CD" games | jq '[.[] | select(.new)] | length')" 0
man 300 "Fresh Install" FreshInstall 10
eq "a game installed later is flagged new" "$("$CD" games | jq -r '.[] | select(.id == "300") | .new')" true
"$CD" gseen steam:300
eq "opening it clears the flag" "$("$CD" games | jq -r '.[] | select(.id == "300") | .new')" false
unset GAMING_DECK_STEAM_ROOT GAMING_DECK_STEAM_RUNNING

section "Gaming: shader caches"
export GAMING_DECK_STEAM_ROOT="$ST" GAMING_DECK_STEAM_RUNNING=0 GAMING_DECK_PACMAN_LOG="$T/pacman-drv.log"
SCD="$ST/steamapps/shadercache"
mkdir -p "$SCD/100/fozpipelinesv6" "$SCD/100/nvidiav1/GLCache" "$SCD/200/nvidiav1/GLCache" "$SCD/999/fozpipelinesv6" "$HOME/.cache/nvidia/GLCache"
head -c 3000 /dev/zero > "$SCD/100/fozpipelinesv6/steam_pipeline_cache.foz"
head -c 2000 /dev/zero > "$SCD/100/nvidiav1/GLCache/old.bin"
head -c 1000 /dev/zero > "$SCD/200/nvidiav1/GLCache/fresh.bin"
head -c 500  /dev/zero > "$SCD/999/fozpipelinesv6/x.foz"
head -c 700  /dev/zero > "$HOME/.cache/nvidia/GLCache/g.bin"
touch -d '2026-01-01' "$SCD/100/nvidiav1/GLCache/old.bin" "$HOME/.cache/nvidia/GLCache/g.bin"
touch -d '2026-06-01' "$SCD/200/nvidiav1/GLCache/fresh.bin"
echo '[2026-03-10T10:00:00+0100] [ALPM] upgraded nvidia-utils (600.1-1 -> 610.2-1)' > "$T/pacman-drv.log"
echo '[2026-03-11T10:00:00+0100] [ALPM] upgraded firefox (1-1 -> 2-1)' >> "$T/pacman-drv.log"
SC="$("$CD" shadercache)"
eq "last driver update read from pacman.log (other packages ignored)" "$(jq -r '.lastDriverUpdate | strftime("%Y-%m-%d")' <<<"$SC")" 2026-03-10
eq "parts split: pipelines / driver" "$(jq -r '.games[] | select(.id == "100") | "\(.pipelines)/\(.driver)"' <<<"$SC")" "3000/2000"
eq "driver cache untouched since the update → stale" "$(jq -r '.games[] | select(.id == "100") | .stale' <<<"$SC")" true
eq "driver cache used since the update → not stale" "$(jq -r '.games[] | select(.id == "200") | .stale' <<<"$SC")" false
eq "cache of an uninstalled game is an orphan" "$(jq -r '.games[] | select(.id == "999") | .installed' <<<"$SC")" false
eq "global NVIDIA cache found and stale" "$(jq -r '.global[] | select(.id == "nvidia") | .stale' <<<"$SC")" true
eq "stale bytes (game driver cache + global)" "$(jq -r .staleBytes <<<"$SC")" 2700
FAKE_FOSSILIZE=1 "$CD" shaderclean orphans >/dev/null 2>&1; eq "refuses while Steam compiles shaders" "$?" 3
PROC_ROOT="$T/proc" "$CD" shaderclean steam:100 driver >/dev/null 2>&1; eq "refuses while that game runs" "$?" 3
mkdir -p "$T/noproc"; PROC_ROOT="$T/noproc" "$CD" shaderclean steam:100 driver >/dev/null   # never this PC's running games
yes "driver part emptied, pipelines kept" "[[ -z \"\$(ls -A '$SCD/100/nvidiav1')\" && -f '$SCD/100/fozpipelinesv6/steam_pipeline_cache.foz' ]]"
PROC_ROOT="$T/noproc" "$CD" shaderclean orphans >/dev/null
yes "orphan cache removed" "[[ ! -e '$SCD/999' ]]"
PROC_ROOT="$T/noproc" "$CD" shaderclean stale >/dev/null
yes "stale global cache emptied, folder kept" "[[ -d '$HOME/.cache/nvidia/GLCache' && -z \"\$(ls -A '$HOME/.cache/nvidia/GLCache')\" ]]"
yes "fresh driver cache kept" "[[ -f '$SCD/200/nvidiav1/GLCache/fresh.bin' ]]"
PROC_ROOT="$T/noproc" "$CD" shaderclean steam:200 all >/dev/null
yes "all: every part of that game gone" "[[ -d '$SCD/200' && -z \"\$(ls -A '$SCD/200')\" ]]"
"$CD" shaderclean 'steam:../x' >/dev/null 2>&1; eq "bad target refused" "$?" 2
unset GAMING_DECK_STEAM_ROOT GAMING_DECK_STEAM_RUNNING GAMING_DECK_PACMAN_LOG

section "Gaming: A/B benchmark"
export GAMING_DECK_STEAM_ROOT="$ST" GAMING_DECK_STEAM_RUNNING=0
mh_csv() {   # file frametime… — a MangoHud 0.8 per-frame log
    local out="$1" ft; shift
    mkdir -p "$(dirname "$out")"
    { echo "os,cpu,gpu,ram,kernel,driver,cpuscheduler"; echo "Arch,CPU,GPU,16,6.x,,schedutil"
      echo "fps,frametime,cpu_load,cpu_power,gpu_load,cpu_temp,gpu_temp,gpu_core_clock,gpu_mem_clock,gpu_vram_used,gpu_power,ram_used,swap_used,process_rss,cpu_mhz,elapsed"
      for ft in "$@"; do echo "0,$ft,20,0,90,60,70,0,0,0,0,0,0,0,0,0"; done; } > "$out"
}
fts=(); for i in $(seq 990); do fts+=(10); done; for i in $(seq 10); do fts+=(40); done; fts+=(99999)
mh_csv "$T/bench.csv" "${fts[@]}"
BS="$(bash -c 'source "$1"; bench_stats "$2"' _ "$CD" "$T/bench.csv")"
eq "frames (pause over 5 s dropped)" "$(jq -r .frames <<<"$BS")" 1000
eq "average FPS"  "$(jq -r .avgFps <<<"$BS")" 97.1
eq "1 % low"      "$(jq -r .low1 <<<"$BS")" 25
eq "p99 frametime" "$(jq -r .p99ms <<<"$BS")" 10
eq "spikes counted" "$(jq -r .spikes <<<"$BS")" 10
eq "loads averaged" "$(jq -r '"\(.cpuLoad)/\(.gpuLoad)"' <<<"$BS")" "20/90"
"$CD" bench set steam:100 duration=3 >/dev/null 2>&1; eq "duration below 5 s refused" "$?" 2
"$CD" bench set steam:100 A 'env=X=1' >/dev/null
"$CD" bench set steam:100 duration=30 delay=10 A label=stock B label=wayland 'env=PROTON_ENABLE_WAYLAND=1' 'args=-vulkan' >/dev/null
eq "variants saved" "$("$CD" bench get steam:100 | jq -r '"\(.A.label)/\(.B.label)/\(.B.env)/\(.duration)"')" "stock/wayland/PROTON_ENABLE_WAYLAND=1/30"
"$CD" steamwrap 100 off >/dev/null 2>&1
"$CD" bench run steam:100 B >/dev/null 2>&1; eq "run refused unless Steam launches it through the deck" "$?" 3
"$CD" steamwrap 100 on >/dev/null
rm -f "$T/steam.log"
"$CD" bench run steam:100 B >/dev/null
has "run launches the game through Steam" "$(cat "$T/steam.log" 2>/dev/null)" "steam://rungameid/100"
printf '#!/bin/sh\necho "MH=$MANGOHUD_CONFIG W=$PROTON_ENABLE_WAYLAND args=$*"\n' > "$T/fake/bgame"; chmod +x "$T/fake/bgame"
O="$(SteamAppId=100 "$CD" run "$T/fake/bgame")"
has "armed launch logs frames into the variant folder" "$O" "output_folder=$HOME/.local/share/gaming-deck/gaming/bench/steam_100/B,autostart_log=10,log_duration=30"
has "variant env applied" "$O" "W=1"
has "variant args applied" "$O" "args=-vulkan"
O="$(SteamAppId=100 "$CD" run "$T/fake/bgame")"
hasnt "armed only once: the next launch is normal" "$O" "output_folder="
mapfile -t fts < <(for i in $(seq 100); do echo 20; done)
mh_csv "$HOME/.local/share/gaming-deck/gaming/bench/steam_100/A/game_1.csv" "${fts[@]}"
mapfile -t fts < <(for i in $(seq 100); do echo 10; done)
mh_csv "$HOME/.local/share/gaming-deck/gaming/bench/steam_100/B/game_2.csv" "${fts[@]}"
BG="$("$CD" bench get steam:100)"
eq "A vs B compared (B doubles the FPS)" "$(jq -r '"\(.results.A.avgFps) \(.results.B.avgFps) \(.compare.avgFps)%"' <<<"$BG")" "50 100 100%"
"$CD" bench set steam:100 B proton=NotAProton >/dev/null 2>&1; eq "unknown Proton refused" "$?" 2
"$CD" bench set steam:100 B proton=GE-Proton9-1 >/dev/null
GAMING_DECK_STEAM_RUNNING=1 "$CD" bench run steam:100 B >/dev/null 2>&1; eq "Proton variant needs Steam closed" "$?" 3
"$CD" bench run steam:100 B >/dev/null
eq "Proton switched for the run" "$(bash -c 'source "$1"; vdf_get "$2" InstallConfigStore/Software/Valve/Steam/CompatToolMapping/100 name' _ "$CD" "$ST/config/config.vdf")" GE-Proton9-1
eq "original Proton remembered" "$("$CD" bench get steam:100 | jq -r .originalProton)" default
"$CD" bench restore steam:100 >/dev/null
hasnt "restore puts the default back" "$(cat "$ST/config/config.vdf")" '"100"'
"$CD" bench clear steam:100 >/dev/null
eq "clear drops the results" "$("$CD" bench get steam:100 | jq -r '.results.A')" null
unset GAMING_DECK_STEAM_ROOT GAMING_DECK_STEAM_RUNNING

section "Gaming: Wine/Proton prefixes"
export GAMING_DECK_STEAM_ROOT="$ST" GAMING_DECK_STEAM_RUNNING=0
mkpfx() { mkdir -p "$1/drive_c/windows"; printf 'WINE REGISTRY Version 2\n#arch=win64\n' > "$1/system.reg"; head -c 1000 /dev/zero > "$1/drive_c/file"; [[ -n "${2:-}" ]] && echo "$2" > "$1/../version" || true; }
CD_=$ST/steamapps/compatdata
mkpfx "$CD_/100/pfx" GE-Proton9-1; mkpfx "$CD_/777/pfx"; mkpfx "$CD_/1493710/pfx"; mkpfx "$CD_/0/pfx"
mkdir -p "$CD_/888/pfx"   # incomplete: not a prefix
mkpfx "$HOME/Games/umbral/battlenet"; mkpfx "$HOME/.wine"
PX="$("$CD" prefixes)"
k() { jq -r --arg n "$1" '.prefixes[] | select(.name == $n) | .'"$2" <<<"$PX"; }
eq "Steam prefix named after its game" "$(jq -r '.prefixes[] | select(.id == "100") | .name' <<<"$PX")" 'Game "Quoted" One'
eq "Proton version read" "$(jq -r '.prefixes[] | select(.id == "100") | .version' <<<"$PX")" GE-Proton9-1
eq "uninstalled game's prefix is an orphan" "$(jq -r '.prefixes[] | select(.id == "777") | .orphan' <<<"$PX")" true
eq "a tool's prefix is not an orphan" "$(jq -r '.prefixes[] | select(.id == "1493710") | .kind' <<<"$PX")" tool
eq "compatdata/0 is Steam's shared prefix" "$(jq -r '.prefixes[] | select(.id == "0") | .kind' <<<"$PX")" shared
eq "folders without system.reg/drive_c ignored" "$(jq '[.prefixes[] | select(.id == "888")] | length' <<<"$PX")" 0
eq "standalone prefixes in ~/Games and ~/.wine found" "$(k battlenet owner)/$(k .wine owner)" "wine/wine"
eq "architecture read" "$(k battlenet arch)" win64
mkdir -p "$T/proc/5000"; printf 'WINEPREFIX=%s\0' "$HOME/Games/umbral/battlenet" > "$T/proc/5000/environ"
eq "prefix in use detected" "$(PROC_ROOT="$T/proc" "$CD" prefixes | jq -r '.prefixes[] | select(.name == "battlenet") | .running')" true
PROC_ROOT="$T/proc" "$CD" prefix delete "$HOME/Games/umbral/battlenet" >/dev/null 2>&1; eq "busy prefix can't be deleted" "$?" 3
"$CD" prefix delete "$HOME" >/dev/null 2>&1; eq "arbitrary folders refused" "$?" 2
export GAMING_DECK_PREFIX_BACKUPS="$T/pbak"
"$CD" prefix backup "$HOME/Games/umbral/battlenet" >/dev/null
B="$(ls "$T/pbak"/wine-battlenet-*.tar.* 2>/dev/null | head -1)"
yes "backup archive written" "[[ -s '$B' ]]"
"$CD" prefix clone "$HOME/Games/umbral/battlenet" "$HOME/Games/clone1" >/dev/null
yes "clone is a full prefix" "[[ -f '$HOME/Games/clone1/system.reg' && -f '$HOME/Games/clone1/drive_c/file' ]]"
"$CD" prefix clone "$HOME/Games/umbral/battlenet" "$HOME/Games/clone1" >/dev/null 2>&1; eq "clone onto an existing folder refused" "$?" 2
"$CD" prefix restore "$B" "$HOME/Games/restored" >/dev/null
yes "restore recreates the prefix" "[[ -f '$HOME/Games/restored/system.reg' ]]"
"$CD" prefix restore /etc/passwd "$HOME/Games/x" >/dev/null 2>&1; eq "restore only from the deck's backups" "$?" 2
"$CD" prefix delete "$CD_/777" >/dev/null
yes "Steam orphan deleted as a whole compatdata folder" "[[ ! -e '$CD_/777' ]]"
yes "…after an automatic backup" "ls '$T/pbak'/steam-uninstalled_app_777-* >/dev/null"
eq "backups listed" "$("$CD" prefix backups | jq length)" 2
unset GAMING_DECK_STEAM_ROOT GAMING_DECK_STEAM_RUNNING GAMING_DECK_PREFIX_BACKUPS

section "Gaming: Umbral games"
export GAMING_DECK_STEAM_ROOT="$ST" GAMING_DECK_STEAM_RUNNING=0 GAMING_DECK_UMBRAL_CONFIG="$T/umbral.json"
mkpfx "$HOME/Games/umbral/game-2"; mkdir -p "$HOME/Games/umbral/games/Poke"; head -c 5000 /dev/zero > "$HOME/Games/umbral/games/Poke/Game.exe"
cat > "$T/umbral.json" <<EOF
{"prefixes":[{"id":"battlenet","name":"Battle.net","path":"$HOME/Games/umbral/battlenet","runner":"UMU-Proton-10.0-4"},
             {"id":"p-game-2","name":"Game","path":"$HOME/Games/umbral/game-2/","runner":"GE-Proton"}],
 "games":[{"id":"battlenet","name":"Battle.net","kind":"battlenet","prefix_id":"battlenet","exe":""},
          {"id":"battlenet:wow","name":"WoW","kind":"blizzard","prefix_id":"battlenet","exe":"/nope/WowB.exe","playtime":29},
          {"id":"1484d426be","name":"Pokemon Iberia","kind":"custom","prefix_id":"p-game-2","exe":"$HOME/Games/umbral/games/Poke/Game.exe","playtime":145,"last_played":"2026-09-30T11:34:25"},
          {"id":"hid","name":"Hidden one","kind":"custom","prefix_id":"p-game-2","exe":"","hidden":true}]}
EOF
G="$("$CD" games)"
HF="$HOME/.local/share/gaming-deck/history.tsv"; cp "$HF" "$HF.bak" 2>/dev/null || :
printf '%s\t%s\t%s\t%s\t%s\n' "2026-10-01 10:00:00" play umbral "umbral:1484d426be" ok "2026-10-01 10:01:00" "reshade on" gaming "steam:100 dxgi" ok \
    "2026-10-01 10:02:00" "steam launch on" steam 100 ok "2026-10-01 10:03:00" install appimage "steam:x.AppImage" ok >> "$HF"
eq "history: game keys show the game's name (Umbral, Steam key + extra, bare Steam id)" \
   "$("$CD" history | jq -c '[.[0:4][] | .name]')" '["steam:x.AppImage","Game \"Quoted\" One","Game \"Quoted\" One dxgi","Pokemon Iberia"]'
mv "$HF.bak" "$HF" 2>/dev/null || rm -f "$HF"
eq "Umbral games listed next to Steam's (hidden ones skipped)" "$(jq '[.[] | select(.source == "umbral")] | length' <<<"$G")" 3
eq "key keeps Umbral's id (with colons)" "$(jq -r '.[] | select(.name == "WoW") | .key' <<<"$G")" "umbral:battlenet:wow"
eq "prefix and Proton from Umbral's config" "$(jq -r '.[] | select(.name == "Pokemon Iberia") | "\(.prefixName)/\(.compat)"' <<<"$G")" "Game/GE-Proton"
eq "game folder size" "$(jq -r '.[] | select(.name == "Pokemon Iberia") | .size' <<<"$G")" 5000
BN="$HOME/Games/umbral/battlenet/drive_c/Program Files (x86)/Battle.net"; mkdir -p "$BN"; head -c 3000 /dev/zero > "$BN/Battle.net.exe"
eq "Battle.net (no .exe in Umbral): its client folder's size" "$("$CD" games | jq -r '.[] | select(.name == "Battle.net") | .size')" 3000
rm -rf "$BN"
mkdir -p "$HOME/Games/umbral/games/Scumm"; head -c 4000 /dev/zero > "$HOME/Games/umbral/games/Scumm/data.001"; cp "$T/umbral.json" "$T/umbral.json.bak"
jq --arg d "$HOME/Games/umbral/games/Scumm" '.games += [{id:"sc", name:"Scumm Game", kind:"scummvm", prefix_id:"", exe:$d}]' "$T/umbral.json.bak" > "$T/umbral.json"
eq "ScummVM game (Umbral keeps its folder): the folder's size" "$("$CD" games | jq -r '.[] | select(.name == "Scumm Game") | .size')" 4000
mv "$T/umbral.json.bak" "$T/umbral.json"
eq "playtime and last play" "$(jq -r '.[] | select(.name == "Pokemon Iberia") | "\(.playtime) \(.lastPlayed)"' <<<"$G")" "145 2026-09-30T11:34:25"
eq "Umbral prefix shown with the game using it (its own name was the .exe's)" "$("$CD" prefixes | jq -r --arg p "$HOME/Games/umbral/game-2" '.prefixes[] | select(.path == $p) | "\(.owner)/\(.name)/\(.orphan)"')" "umbral/Pokemon Iberia/false"
mkpfx "$HOME/Games/umbral/old"; cp "$T/umbral.json" "$T/umbral.json.bak"
jq --arg p "$HOME/Games/umbral/old" '.prefixes += [{id:"p-old", name:"Old", path:$p, runner:"GE-Proton"}]' "$T/umbral.json.bak" > "$T/umbral.json"
eq "Umbral prefix no game uses → orphan" "$("$CD" prefixes | jq -r --arg p "$HOME/Games/umbral/old" '.prefixes[] | select(.path == $p) | "\(.name)/\(.orphan)"')" "Old/true"
eq "…but CLEAN leaves it (Umbral still lists it): only Steam orphans" "$("$CD" cleanscan | jq -r '.[] | select(.id == "prefixes") | .details' | grep -c Old)" 0
mv "$T/umbral.json.bak" "$T/umbral.json"; rm -rf "$HOME/Games/umbral/old"
mkdir -p "$T/proc2/6000" "$T/proc2/6001"
printf '%s\0%s\0' "/usr/bin/umu-run" 'C:\games\Poke\Game.exe' > "$T/proc2/6000/cmdline"
printf '%s\0%s\0' "grep" "WowB.exe.bak" > "$T/proc2/6001/cmdline"
eq "running Umbral game found by its .exe (Windows path too), no partial matches" "$(PROC_ROOT="$T/proc2" "$CD" gstatus | jq -c '[.running[] | .key]')" '["umbral:1484d426be"]'
# Umbral ≥ 0.11: running.json with exact pids + start times (field 22 of /proc/<pid>/stat)
mkstat() { mkdir -p "$T/proc3/$1"; printf '%s (%s) S 1 %s 0 0 0 0 0 0 0 0 0 0 0 0 20 0 1 0 %s 0 0\n' "$1" "$2" "$1" "$3" > "$T/proc3/$1/stat"; }
mkstat 7000 "Game.exe" 555; mkstat 7001 "umu run (x)" 500; mkstat 7100 "Other.exe" 999
cat > "$T/umbral-running.json" <<EOF
{"version":1,"umbral_pid":1,"games":[
 {"id":"1484d426be","name":"Pokemon Iberia","launched_by":"umbral","pid":7001,"pid_starttime":500,
  "game_pids":[{"pid":7000,"starttime":555}],"proton":"GE-Proton11-7-x86_64","started":1790000000.0},
 {"id":"battlenet:wow","name":"WoW","launched_by":"battlenet","pid":7100,"pid_starttime":111,"game_pids":[{"pid":7100,"starttime":111}]}]}
EOF
GS3="$(PROC_ROOT="$T/proc3" "$CD" gstatus)"
eq "running.json: the game's own pid, its Proton from Umbral" "$(jq -c '[.running[] | [.key, .pid, .proton]]' <<<"$GS3")" '[["umbral:1484d426be",7000,"GE-Proton11-7-x86_64"]]'
yes "…a reused pid (start time differs) isn't taken for the game" "! jq -e '.running[] | select(.key == \"umbral:battlenet:wow\")' <<<'$GS3' >/dev/null"
echo '{"version":1,"games":[]}' > "$T/umbral-running.json"
eq "running.json says nothing runs → no name guessing" "$(PROC_ROOT="$T/proc2" "$CD" gstatus | jq -c '[.running[] | .key]')" '[]'
rm -f "$T/umbral-running.json"
stub umbral 'echo "umbral $*" >> "'"$T"'/umbral.log"; [ "$1" = --stop ] && [ "$2" = 1484d426be ] && exit 0; [ "$1" = --stop ] && exit 1; exit 0'
rm -f "$T/umbral.log"; "$CD" gstop umbral:1484d426be >/dev/null
has "STOP closes an Umbral game through Umbral" "$(cat "$T/umbral.log")" "umbral --stop 1484d426be"
"$CD" gstop umbral:other >/dev/null 2>&1; eq "…not running → 3" "$?" 3
"$CD" gstop steam:100 >/dev/null 2>&1; eq "…Steam games aren't stopped from here" "$?" 2
# Umbral ≥ 0.12: a game's options from outside (--get / --set)
stub umbral 'echo "umbral $*" >> "'"$T"'/umbral.log"
case "$1" in
  --get) [ "$2" = 1484d426be ] || exit 1
         echo "{\"options\":{\"gamemode\":null,\"fps_limit\":60},\"env\":{\"A\":\"1\"},\"effective\":{\"gamemode\":true,\"fps_limit\":60},\"effective_env\":{\"A\":\"1\"},\"prefix\":{\"id\":\"p-game-2\"},\"keys\":[]}" ;;
  --set) case "$*" in *maybe*) echo "«gamemode» espera on, off o default" >&2; exit 2;; esac; exit 0 ;;
esac'
eq "uopts: Umbral's options, set and effective" "$("$CD" uopts umbral:1484d426be | jq -c '[.options.gamemode, .effective.gamemode, .env.A]')" '[null,true,"1"]'
rm -f "$T/umbral.log"; "$CD" uset umbral:1484d426be gamemode=on env.DXVK_HUD=fps >/dev/null
has "uset passes the options to umbral --set" "$(cat "$T/umbral.log")" "umbral --set 1484d426be gamemode=on env.DXVK_HUD=fps"
"$CD" uset umbral:1484d426be gamemode=maybe >/dev/null 2>&1; eq "…a value Umbral refuses → 2" "$?" 2
"$CD" uset umbral:1484d426be 'bad key=1' >/dev/null 2>&1; eq "…a key that isn't an option is refused before Umbral" "$?" 2
stub umbral 'exit 2'
"$CD" uopts umbral:1484d426be >/dev/null 2>&1; eq "older Umbral (no --get) → 4, the GUI stays read-only" "$?" 4
# Crisol (mod manager): a game's mods, open it there, play with mods
eq "mods without Crisol → {}" "$(GAMING_DECK_CRISOL=crisol-missing "$CD" mods steam:100)" '{}'
stub crisol 'echo "crisol $*" >> "'"$T"'/crisol.log"
case "$1" in
  --list) echo "[{\"key\":\"steam:100\",\"name\":\"G\",\"mods\":2,\"enabled\":1,\"profile\":\"Main\",\"applied\":true,\"pending_changes\":false,\"updates\":1,\"layout\":\"me3\",\"loader\":{\"name\":\"ME3\",\"level\":\"required\",\"installed\":true}}]" ;;
  --play) [ "$2" = steam:100 ] || { echo "No existe el juego $2" >&2; exit 2; } ;;
esac'
eq "mods: the game's mods in Crisol" "$("$CD" mods steam:100 | jq -c '[.mods, .enabled, .updates, .loader.name]')" '[2,1,1,"ME3"]'
eq "…a game Crisol doesn't have → {}" "$("$CD" mods steam:999)" '{}'
"$CD" mods foo >/dev/null 2>&1; eq "…not a game key → 2" "$?" 2
rm -f "$T/crisol.log"; "$CD" mplay steam:100 >/dev/null
has "mplay plays through Crisol" "$(cat "$T/crisol.log")" "crisol --play steam:100"
"$CD" mplay steam:5 >/dev/null 2>&1; eq "…Crisol refuses → 3" "$?" 3
GAMING_DECK_CRISOL=crisol-missing "$CD" mopen steam:100 >/dev/null 2>&1; eq "mopen without Crisol → 4" "$?" 4
rm -f "$T/bin/crisol"
# CHECK FOR THIS PC: an Umbral game's other-vendor variable is removed through Umbral
stub umbral 'echo "umbral $*" >> "'"$T"'/umbral.log"; exit 0'
cp "$T/umbral.json" "$T/umbral.json.bak"
jq '(.games[] | select(.id == "1484d426be") | .options) = {env:{RADV_PERFTEST:"gpl", DXVK_HUD:"fps"}}' "$T/umbral.json.bak" > "$T/umbral.json"
eq "gaudit flags an AMD-only variable of an Umbral game on NVIDIA" "$(GAMING_DECK_GPU_VENDOR=nvidia "$CD" gaudit | jq -c '[.issues[] | select(.key == "umbral:1484d426be") | .var]')" '["RADV_PERFTEST"]'
rm -f "$T/umbral.log"; GAMING_DECK_GPU_VENDOR=nvidia "$CD" gaudit fix all >/dev/null
has "…and FIX ALL removes it through umbral --set" "$(cat "$T/umbral.log")" "umbral --set 1484d426be env.RADV_PERFTEST="
mv "$T/umbral.json.bak" "$T/umbral.json"
rm -f "$T/umbral.log" "$T/steam.log"
"$CD" gplay umbral:1484d426be >/dev/null
has "PLAY starts an Umbral game through Umbral" "$(cat "$T/umbral.log")" "umbral --launch 1484d426be"
"$CD" gplay steam:100 >/dev/null
has "PLAY starts a Steam game through Steam" "$(cat "$T/steam.log")" "steam://rungameid/100"
"$CD" gplay umbral:nope >/dev/null 2>&1; eq "unknown Umbral game refused" "$?" 2
"$CD" gplay 'steam:1;rm' >/dev/null 2>&1; eq "bad key refused" "$?" 2
unset GAMING_DECK_STEAM_ROOT GAMING_DECK_STEAM_RUNNING GAMING_DECK_UMBRAL_CONFIG
# ---------------------------------------------------------- 2.9 health ----
section "gaming health"
H="$T/health"; mkdir -p "$H/db" "$H/sys/class/drm/card1/device" "$H/sys/drivers/amdgpu" "$H/proc/sys/vm"
fakepkg() { mkdir -p "$H/db/$1-$2"; }
echo 0x1002 > "$H/sys/class/drm/card1/device/vendor"
ln -s ../../../../drivers/amdgpu "$H/sys/class/drm/card1/device/driver"
mkdir -p "$H/sys/class/drm/card1-DP-1"; echo 65536 > "$H/proc/sys/vm/max_map_count"
printf '[options]\n#[multilib]\n#Include = /etc/pacman.d/mirrorlist\n' > "$H/pacman.conf"
fakepkg mesa 1:26.2.3-1; fakepkg vulkan-radeon 1:26.2.3-1; fakepkg amdvlk 2025.Q2.1-1
fakepkg vulkan-icd-loader 1.4.357-1; fakepkg lib32-vulkan-icd-loader 1.4.357-1; fakepkg lib32-gnutls 3.8-1
fakepkg lib32-mesa-git 26.3-1        # a prefix of lib32-mesa must not count as it
stub vulkaninfo 'printf "Devices:\n=======\nGPU0:\n\tdeviceType = PHYSICAL_DEVICE_TYPE_CPU\n\tdeviceName = llvmpipe\n\tdriverName = llvmpipe\n"'
stub modinfo 'exit ${FAKE_NTSYNC_MOD:-1}'
hrun() { GAMING_DECK_PACMAN_DB="$H/db" GAMING_DECK_SYSFS="$H/sys" GAMING_DECK_PROCFS="$H/proc" \
         GAMING_DECK_PACMAN_CONF="$H/pacman.conf" GAMING_DECK_NTSYNC_DEV="$H/ntsync" "$CD" health; }
HJ="$(hrun)"
st() { jq -r --arg id "$1" '.checks[] | select(.id == $id) | .status' <<<"$HJ"; }
fx() { jq -r --arg id "$1" '.checks[] | select(.id == $id) | .fix' <<<"$HJ"; }
eq "AMD card found from sysfs (connector entries ignored)" "$(jq -c .vendors <<<"$HJ")" '["amd"]'
eq "commented [multilib] is disabled" "$(st multilib)" fail
eq "low vm.max_map_count warned" "$(st max_map_count)" warn
eq "no ntsync module → info only" "$(st ntsync)" info
eq "amdgpu driver in use" "$(st amd:module)" ok
eq "missing 32-bit Mesa/RADV fails" "$(st pkg:mesa)" fail
eq "fix installs exactly what is missing" "$(fx pkg:mesa)" "sudo pacman -S --needed lib32-mesa lib32-vulkan-radeon"
eq "AMDVLK flagged for removal" "$(fx amd:amdvlk)" "sudo pacman -Rns amdvlk"
eq "Vulkan with only a software renderer fails" "$(st vulkan:device)" fail
eq "no 32-bit audio warned" "$(st lib32:audio)" warn
eq "one command for everything missing" "$(jq -r .installAll <<<"$HJ")" "sudo pacman -S --needed lib32-mesa lib32-pipewire lib32-vulkan-radeon"
eq "counts" "$(jq -c '[.fail, .warn]' <<<"$HJ")" "[3,3]"
HJ="$(FAKE_NTSYNC_MOD=0 hrun)"; eq "ntsync module present but not loaded → load command" "$(st ntsync)" warn
# NVIDIA, updated without a reboot
rm -rf "$H/sys" "$H/db"; mkdir -p "$H/sys/class/drm/card0/device" "$H/sys/drivers/nvidia" "$H/sys/module/nvidia" "$H/sys/module/nvidia_drm/parameters"
echo 0x10de > "$H/sys/class/drm/card0/device/vendor"; ln -s ../../../../drivers/nvidia "$H/sys/class/drm/card0/device/driver"
echo 610.10 > "$H/sys/module/nvidia/version"; echo Y > "$H/sys/module/nvidia_drm/parameters/modeset"
echo 1048576 > "$H/proc/sys/vm/max_map_count"; touch "$H/ntsync"; printf '[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' > "$H/pacman.conf"
fakepkg nvidia-utils 615.71.09-1; fakepkg lib32-nvidia-utils 615.71.09-1
fakepkg vulkan-icd-loader 1-1; fakepkg lib32-vulkan-icd-loader 1-1; fakepkg lib32-pipewire 1-1; fakepkg lib32-gnutls 1-1
stub vulkaninfo 'printf "GPU0:\n\tdeviceType = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU\n\tdeviceName = NVIDIA GeForce RTX 2070\n\tdriverName = NVIDIA\n"'
HJ="$(hrun)"
eq "multilib, max_map_count, ntsync ok" "$(st multilib)$(st max_map_count)$(st ntsync)" okokok
eq "driver updated but kernel module old → reboot" "$(fx nvidia:sync)" reboot
has "…and says which versions" "$(jq -r '.checks[] | select(.id == "nvidia:sync") | .detail' <<<"$HJ")" "615.71.09 but the loaded kernel module is 610.10"
eq "Vulkan sees the GPU" "$(jq -r '.checks[] | select(.id == "vulkan:device") | .detail' <<<"$HJ")" "NVIDIA GeForce RTX 2070 · NVIDIA"
echo 615.71.09 > "$H/sys/module/nvidia/version"; rm -rf "$H/db/lib32-nvidia-utils-615.71.09-1"; fakepkg lib32-nvidia-utils 610.10-1
HJ="$(hrun)"; eq "32-bit driver out of sync → full update" "$(fx nvidia:sync)" "sudo pacman -Syu"
rm -rf "$H/db/lib32-nvidia-utils-610.10-1"; fakepkg lib32-nvidia-utils 615.71.09-1; echo N > "$H/sys/module/nvidia_drm/parameters/modeset"
HJ="$(hrun)"
eq "all in sync" "$(st nvidia:sync)" ok
has "modeset off → modprobe option" "$(fx nvidia:modeset)" "options nvidia_drm modeset=1"
eq "nothing to install" "$(jq -r .installAll <<<"$HJ")" ""
rm -f "$T/bin/vulkaninfo" "$T/bin/modinfo"
# ------------------------------------------------ CLEAN: gaming rows ----
section "clean: unused Proton versions"
PT="$HOME/steam-pt"; mkdir -p "$PT/config" "$PT/steamapps"
cat > "$PT/config/config.vdf" <<'EOF'
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"CompatToolMapping"
				{
					"570"
					{
						"name"		"steam_mapped"
						"config"		""
						"priority"		"250"
					}
				}
			}
		}
	}
}
EOF
mktool() {   # dir internal-name version
    mkdir -p "$PT/compatibilitytools.d/$1"; touch "$PT/compatibilitytools.d/$1/proton"
    printf '"compatibilitytools"\n{\n  "compat_tools"\n  {\n    "%s" // internal name\n    {\n    }\n  }\n}\n' "$2" \
        > "$PT/compatibilitytools.d/$1/compatibilitytool.vdf"
    echo "1700000000 $3" > "$PT/compatibilitytools.d/$1/version"
    head -c 4096 /dev/zero > "$PT/compatibilitytools.d/$1/files.bin"
}
mktool "Mapped Dir" steam_mapped Mapped-1
mktool GE-Proton9-1 GE-Proton9-1 GE-Proton9-1
mktool GE-Proton10-3 GE-Proton10-3 GE-Proton10-3
mktool OldPfx OldPfx Old-7
mktool "Busy One" busy Busy-1
mktool "Spare Tool" spare Spare-2
mkdir -p "$HOME/Games/umbral/pfx/drive_c"; touch "$HOME/Games/umbral/pfx/system.reg"; echo Old-7 > "$HOME/Games/umbral/pfx/version"
echo '{"prefixes":[{"id":"p","name":"P","path":"'"$HOME"'/Games/umbral/pfx","runner":"GE-Proton"}],"games":[]}' > "$T/umbral-pt.json"
mkdir -p "$T/proc-pt/7000"; printf '%s\0%s\0' "$PT/compatibilitytools.d/Busy One/files/bin/wine" game.exe > "$T/proc-pt/7000/cmdline"
ptrun() { GAMING_DECK_STEAM_ROOT="$PT" GAMING_DECK_STEAM_RUNNING=0 GAMING_DECK_UMBRAL_CONFIG="$T/umbral-pt.json" PROC_ROOT="$T/proc-pt" "$CD" "$@"; }
CS="$(ptrun cleanscan)"
eq "tools nothing uses (Steam-mapped, Umbral's newest GE, a prefix's Proton and a running one are kept)" \
   "$(jq -r '.[] | select(.id == "protons") | .details' <<<"$CS")" "GE-Proton9-1 · spare"
yes "its size is measured (folder name with spaces)" "(( $(jq '.[] | select(.id == "protons") | .bytes' <<<"$CS") >= 4096 ))"
echo '{"prefixes":[{"id":"p","name":"P","path":"'"$HOME"'/Games/umbral/pfx","runner":"GE-Proton9-1"}],"games":[]}' > "$T/umbral-pt.json"
eq "an explicit Umbral runner keeps that one and frees the newest GE" \
   "$(ptrun cleanscan | jq -r '.[] | select(.id == "protons") | .details')" "GE-Proton10-3 · spare"
echo '{"prefixes":[],"games":[]}' > "$T/umbral-pt.json"; rm -rf "$PT/compatibilitytools.d/GE-Proton10-3"
ptrun clean protons >/dev/null 2>&1
eq "clean removes exactly the unused ones" "$(ls "$PT/compatibilitytools.d" | paste -sd ,)" "Busy One,Mapped Dir,OldPfx"
eq "shader and prefix rows present" "$(ptrun cleanscan | jq -c '[.[] | select(.id == "shaders" or .id == "prefixes") | .count]')" "[0,0]"
rm -rf "$HOME/Games/umbral/pfx" "$PT"
# ------------------------------------------------ temperature overlay ----
section "temperature overlay"
TS="$T/tsys/class/hwmon"; mkdir -p "$TS/hwmon0" "$TS/hwmon1" "$TS/hwmon2"
echo acpitz > "$TS/hwmon0/name"; echo 27000 > "$TS/hwmon0/temp1_input"
echo coretemp > "$TS/hwmon1/name"
echo "Core 0" > "$TS/hwmon1/temp2_label"; echo 44000 > "$TS/hwmon1/temp2_input"
echo "Package id 0" > "$TS/hwmon1/temp1_label"; echo 48500 > "$TS/hwmon1/temp1_input"
echo amdgpu > "$TS/hwmon2/name"
echo junction > "$TS/hwmon2/temp2_label"; echo 80000 > "$TS/hwmon2/temp2_input"
echo edge > "$TS/hwmon2/temp1_label"; echo 61000 > "$TS/hwmon2/temp1_input"
eq "Intel package temp + AMD GPU edge temp" "$(GAMING_DECK_SYSFS="$T/tsys" GAMING_DECK_GPU_VENDOR=amd "$CD" temps | paste -sd ' ')" "CPU=48 GPU=61"
echo k10temp > "$TS/hwmon1/name"; echo Tctl > "$TS/hwmon1/temp1_label"
eq "AMD CPU (k10temp Tctl)" "$(GAMING_DECK_SYSFS="$T/tsys" GAMING_DECK_GPU_VENDOR=amd "$CD" temps | head -1)" "CPU=48"
rm -rf "$TS/hwmon1"
eq "no CPU chip → ACPI fallback" "$(GAMING_DECK_SYSFS="$T/tsys" GAMING_DECK_GPU_VENDOR=amd "$CD" temps | head -1)" "CPU=27"
eq "pid alive" "$(GAMING_DECK_SYSFS="$T/tsys" "$CD" temps $$ | tail -1)" "ALIVE=1"
eq "pid gone" "$(GAMING_DECK_SYSFS="$T/tsys" "$CD" temps 99999999 | tail -1)" "ALIVE=0"
stub qs 'echo "qs $* pid=$CD_OVERLAY_PID ldp=${LD_LIBRARY_PATH:-none} pre=${LD_PRELOAD:-none}" >> "'"$T"'/qs.log"'
touch "$T/overlay.qml"; export GAMING_DECK_OVERLAY_QML="$T/overlay.qml"
"$CD" gprofile set steam:300 overlay=maybe >/dev/null 2>&1; eq "overlay must be true/false" "$?" 2
"$CD" gprofile set steam:300 overlay=true gamemode=false >/dev/null
printf '#!/bin/sh\necho "pid=$PPID"\n' > "$T/fake/ogame"; chmod +x "$T/fake/ogame"
rm -f "$T/qs.log"; O="$(SteamAppId=300 "$CD" run "$T/fake/ogame")"
for _ in $(seq 25); do [[ -s "$T/qs.log" ]] && break; sleep 0.2; done
eq "overlay follows the wrapper, which lives exactly as long as the game (its parent)" "$(grep -o 'pid=[0-9]*' "$T/qs.log")" "$O"
has "…from the overlay config" "$(cat "$T/qs.log")" "qs -p $T/overlay.qml"
rm -f "$T/qs.log"; LD_LIBRARY_PATH=/steam/pinned_libs LD_PRELOAD=/steam/gameoverlayrenderer.so SteamAppId=300 "$CD" run "$T/fake/ogame" >/dev/null
for _ in $(seq 25); do [[ -s "$T/qs.log" ]] && break; sleep 0.2; done
has "Steam's LD_LIBRARY_PATH / LD_PRELOAD don't reach the overlay (they break Qt)" "$(cat "$T/qs.log")" "ldp=none pre=none"
rm -f "$T/qs.log"; SteamAppId=301 "$CD" run "$T/fake/ogame" >/dev/null; sleep 0.3
yes "no overlay when the profile doesn't ask for it" "[[ ! -e '$T/qs.log' ]]"
unset GAMING_DECK_OVERLAY_QML; "$CD" gprofile reset steam:300 >/dev/null
# ------------------------------------------------------ visual shaders ----
section "visual shaders (vkBasalt)"
FXS="$T/fxsrc"; mkdir -p "$FXS/pkgA/Pack-main/Shaders" "$FXS/pkgA/Pack-main/Textures" "$FXS/sfx/games/game/7" "$FXS/sfx/games/preset/501/download" "$FXS/sfx/games/game/search"
cat > "$FXS/pkgA/Pack-main/Shaders/Vibrance.fx" <<'EOF'
uniform float Vibrance < ui_type = "slider"; > = 0.15;
uniform float3 VibranceRGBBalance < ui_type = "drag"; > = float3(1.0, 1.0, 1.0);
technique Vibrance { pass { } }
EOF
cat > "$FXS/pkgA/Pack-main/Shaders/Multi.fx" <<'EOF'
uniform float Amount < > = 1.0;
technique First { pass { } }
technique Second { pass { } }
EOF
cat > "$FXS/pkgA/Pack-main/Shaders/DOF.fx" <<'EOF'
float d = ReShade::GetLinearizedDepth(uv);
technique DOF { pass { } }
EOF
echo 'template' > "$FXS/pkgA/Pack-main/Shaders/Template.fx"
echo png > "$FXS/pkgA/Pack-main/Textures/lut.png"
( cd "$FXS/pkgA" && bsdtar -a -cf "$FXS/pack.zip" Pack-main )
cat > "$FXS/EffectPackages.ini" <<EOF
[00]
Enabled=1
Required=1
PackageName=Test pack
PackageDescription=test
InstallPath=.\reshade-shaders\Shaders\Sub
DownloadUrl=file://$FXS/pack.zip
EffectFiles=Vibrance.fx,Multi.fx,DOF.fx
DenyEffectFiles=Template.fx
EOF
echo '{"Games": [{"title": "Test Game", "url": "/games/game/7/"}]}' > "$FXS/sfx/games/game/search/q_Test_Game.json"
sfxrow() { printf '<tr>\n<td><a href="/games/preset/%s/">%s</a></td>\n\n<td>Jan. 1, 2026</td>\n<td><a href="/users/u/x/">x</a>\n</td>\n<td>1</td>\n<td>%s</td>\n<td><a href="/games/shader/%s/">%s</a></td>\n</tr>\n' "$@"; }
{ sfxrow 499 "Old one" 900 5 SweetFX; sfxrow 501 "Nice &amp; sharp" 40 21 ReShade; sfxrow 502 "Popular" 300 21 ReShade; } > "$FXS/sfx/games/game/7/index.html"
printf -- '--> Nice preset\r\nTechniques=Vibrance@Vibrance.fx,Second@Multi.fx,DOF@DOF.fx,Missing@Missing.fx\r\n\r\n[Vibrance.fx]\r\nVibrance=0.300000\r\nVibranceRGBBalance=1.000000,0.900000,1.000000\r\n' > "$FXS/sfx/games/preset/501/download/index.html"
cat > "$FXS/awacy.json" <<'EOF'
[{"name":"Shooter","anticheats":["Easy Anti-Cheat"],"status":"Denied","storeIds":{"steam":"4000"}}]
EOF
echo '{"4000":{"success":true,"data":{"categories":[{"id":1}]}}}' > "$FXS/store-4000.json"
echo '{"4001":{"success":true,"data":{"categories":[{"id":2},{"id":36}]}}}' > "$FXS/store-4001.json"
echo '{"4002":{"success":true,"data":{"categories":[{"id":2}]}}}' > "$FXS/store-4002.json"
export GAMING_DECK_FX_PACKAGES_URL="file://$FXS/EffectPackages.ini" GAMING_DECK_SFX_URL="file://$FXS/sfx" \
       GAMING_DECK_AWACY_URL="file://$FXS/awacy.json"
# the store API URL carries ?appids=…: serve per-id files through a tiny wrapper URL
fxon() { GAMING_DECK_STEAM_STORE_API="file://$FXS/store-$1.json#" "$CD" fx status "steam:$1" | jq -c '.online | [.level, .anticheats]'; }
eq "anti-cheat game (AreWeAntiCheatYet)" "$(fxon 4000)" '["anticheat",["Easy Anti-Cheat"]]'
eq "online PvP without anti-cheat" "$(fxon 4001)" '["online",[]]'
eq "single-player" "$(fxon 4002)" '["none",[]]'
eq "packages parsed from the official list" "$("$CD" fx packages | jq -c '.[0] | [.name, .default, .sub, (.files | length), .installed]')" '["Test pack",true,"Sub",3,false]'
"$CD" fx package 00 >/dev/null
FXD="$HOME/.local/share/gaming-deck/reshade"
yes "shaders keep the package folder" "[[ -f '$FXD/Shaders/Sub/Vibrance.fx' ]]"
yes "textures are flattened (one folder for vkBasalt)" "[[ -f '$FXD/Textures/lut.png' ]]"
yes "DenyEffectFiles removed" "[[ ! -e '$FXD/Shaders/Sub/Template.fx' ]]"
eq "marked installed" "$("$CD" fx packages | jq '.[0].installed')" true
eq "search on SweetFX DB" "$("$CD" fx search Test Game)" '[{"title":"Test Game","id":"7"}]'
RVS="$("$CD" fx reviews 7)"
eq "preset reviews: a ReShade preset is analysed" "$(jq -c '."501" | [.verdict, .effects]' <<<"$RVS")" '["light",4]'
eq "…one that can't be read (old format) is marked so" "$(jq -r '."499".verdict' <<<"$RVS")" old
eq "presets of a game, newest first, entities decoded, downloads and type" "$("$CD" fx presets 7 | jq -c '[.[] | [.id, .name, .downloads, .shader]]')" '[["502","Popular",300,"ReShade"],["501","Nice & sharp",40,"ReShade"],["499","Old one",900,"SweetFX"]]'
"$CD" fx set steam:4002 builtin:nope >/dev/null 2>&1; eq "unknown look refused" "$?" 2
"$CD" fx set steam:4002 sfx:501 >/dev/null 2>&1
FXC="$HOME/.local/share/gaming-deck/gaming/fx/steam_4002"
R="$(cat "$FXC/report.json")"
eq "only the effect vkBasalt can run is applied" "$(jq -c .effects <<<"$R")" '["Vibrance.fx"]'
has "second technique of a file skipped" "$(jq -r '.skipped[] | select(.effect == "Second") | .why' <<<"$R")" "only runs the first technique"
has "depth effect skipped" "$(jq -r '.skipped[] | select(.effect == "DOF") | .why' <<<"$R")" "depth buffer"
has "missing shader skipped" "$(jq -r '.skipped[] | select(.effect == "Missing") | .why' <<<"$R")" "not found"
eq "vector with different components left at default" "$(jq -c .partial <<<"$R")" '[{"file":"Vibrance.fx","value":"VibranceRGBBalance"}]'
has "config points at the shader" "$(cat "$FXC/vkBasalt.conf")" "fx1 = \"$FXD/Shaders/Sub/Vibrance.fx\""
has "preset value carried over" "$(cat "$FXC/vkBasalt.conf")" "Vibrance = 0.300000"
eq "profile flag on" "$("$CD" gprofile get steam:4002 | jq .fx)" true
printf '#!/bin/sh\necho "vkb=$ENABLE_VKBASALT conf=$VKBASALT_CONFIG_FILE"\n' > "$T/fake/fxgame"; chmod +x "$T/fake/fxgame"
eq "wrapper enables vkBasalt with the game's config" "$(SteamAppId=4002 "$CD" run "$T/fake/fxgame")" "vkb=1 conf=$FXC/vkBasalt.conf"
"$CD" fx set steam:4002 builtin:sharpen-aa >/dev/null
eq "built-in look" "$(grep '^effects' "$FXC/vkBasalt.conf")" "effects = smaa:cas"
"$CD" fx set steam:4002 off >/dev/null
eq "off: wrapper leaves vkBasalt alone" "$(SteamAppId=4002 "$CD" run "$T/fake/fxgame")" "vkb= conf="
printf 'https://www.nexusmods.com/x/mods/1' > "$FXS/sfx/games/preset/501/download/index.html"
O="$("$CD" fx set steam:4002 sfx:501 2>&1)"; eq "a link instead of a preset is refused" "$?" 4
has "…saying what it is" "$O" "not a ReShade preset"
unset GAMING_DECK_FX_PACKAGES_URL GAMING_DECK_SFX_URL GAMING_DECK_AWACY_URL
# ------------------------------------------------ ReShade under Proton ----
section "ReShade (DLL) under Proton"
RS="$T/rs"; mkdir -p "$RS/web/downloads" "$RS/zip" "$RS/ff/win64/ach" "$RS/ff/win32/ach" "$RS/7z/core"
echo '<a href="/downloads/ReShade_Setup_6.9.1_Addon.exe">addon</a> <a href="/downloads/ReShade_Setup_6.9.1.exe">get</a>' > "$RS/web/index.html"
echo dll64 > "$RS/zip/ReShade64.dll"; echo dll32 > "$RS/zip/ReShade32.dll"
( cd "$RS/zip" && bsdtar -a -cf ../r.zip ReShade64.dll ReShade32.dll )
{ printf 'MZ'; head -c 512 /dev/zero; cat "$RS/r.zip"; } > "$RS/web/downloads/ReShade_Setup_6.9.1.exe"
echo d3dc > "$RS/7z/core/d3dcompiler_47.dll"
( cd "$RS/7z" && bsdtar --format 7zip -cf "$RS/ff.7z" core )
cp "$RS/ff.7z" "$RS/ff/win64/ach/Firefox%20Setup%2062.0.3.exe"; cp "$RS/ff.7z" "$RS/ff/win32/ach/Firefox%20Setup%2062.0.3.exe"
FFSHA="$(sha256sum "$RS/ff.7z" | cut -d' ' -f1)"
# a minimal 64-bit PE that imports dxgi.dll
mkpe() {   # out dllname machine(0x8664|0x14c)
    python3 - "$@" <<'PYPE'
import struct, sys
out, dll, mach = sys.argv[1], sys.argv[2].encode(), int(sys.argv[3], 16)
pe64 = mach == 0x8664; optsz = 240 if pe64 else 224
d = bytearray(0x400)
d[0:2] = b'MZ'; struct.pack_into('<I', d, 0x3C, 0x40)
d[0x40:0x44] = b'PE\0\0'; struct.pack_into('<HH', d, 0x44, mach, 1); struct.pack_into('<H', d, 0x54, optsz)
opt = 0x58; struct.pack_into('<H', d, opt, 0x20b if pe64 else 0x10b)
ddir = opt + (112 if pe64 else 96); struct.pack_into('<II', d, ddir + 8, 0x1000, 40)
sec = opt + optsz; d[sec:sec+8] = b'.idata\0\0'; struct.pack_into('<IIII', d, sec + 8, 0x200, 0x1000, 0x200, 0x200)
struct.pack_into('<I', d, 0x200 + 12, 0x1000 + 40); d[0x200 + 40:0x200 + 40 + len(dll)] = dll
open(out, 'wb').write(bytes(d) + b'\0' * 200000)
PYPE
}
export GAMING_DECK_STEAM_ROOT="$ST" GAMING_DECK_STEAM_RUNNING=0 GAMING_DECK_RESHADE_URL="file://$RS/web" \
       GAMING_DECK_FF_D3DC_URL="file://$RS/ff" GAMING_DECK_FF_D3DC_SHA64="$FFSHA" GAMING_DECK_FF_D3DC_SHA32="$FFSHA" \
       GAMING_DECK_FX_PACKAGES_URL="file://$FXS/EffectPackages.ini" GAMING_DECK_SFX_URL="file://$FXS/sfx" \
       GAMING_DECK_AWACY_URL="file://$FXS/awacy.json" GAMING_DECK_STEAM_STORE_API="file://$FXS/store-4002.json#"
mkdir -p "$HOME/Pictures"; export GAMING_DECK_PICTURES="$HOME/Pictures"
man 5000 "Story Game" StoryGame 100
SG="$ST/steamapps/common/StoryGame"; mkdir -p "$SG/Binaries/Win64" "$SG/Redist"
mkpe "$SG/StoryGame.exe" kernel32.dll 0x8664
mkpe "$SG/Binaries/Win64/StoryGame-Win64-Shipping.exe" dxgi.dll 0x8664
mkpe "$SG/Binaries/Win64/CrashReportClient.exe" kernel32.dll 0x8664
mkpe "$SG/Redist/vcredist_x64.exe" kernel32.dll 0x8664
mkpe "$SG/Binaries/Win64/Old9.exe" d3d9.dll 0x14c
EX="$("$CD" fx exes steam:5000)"
eq "Unreal Shipping exe first, crash reporter and redist left out" "$(jq -c '[.[] | .rel]' <<<"$EX")" '["Binaries/Win64/StoryGame-Win64-Shipping.exe","StoryGame.exe","Binaries/Win64/Old9.exe"]'
eq "arch and API from the PE imports (DLLs beside it count)" "$(jq -c '[.[] | [.arch, .api]]' <<<"$EX")" '[[64,"dxgi"],[64,"unknown"],[32,"dxgi"]]'
"$CD" fx reshade install >/dev/null 2>&1
FXB="$HOME/.local/share/gaming-deck/reshade/bin"
eq "latest non-addon ReShade from the site" "$(readlink "$FXB/current")" "ReShade-6.9.1"
eq "DLLs pulled out of the installer" "$(cat "$FXB/current/ReShade64.dll")" dll64
eq "d3dcompiler_47 from the (checksummed) Firefox installer" "$(cat "$FXB/d3dcompiler_47.dll.64")" d3dc
rm -f "$FXB/d3dcompiler_47.dll.32"
GAMING_DECK_FF_D3DC_SHA32=0000 "$CD" fx reshade install >/dev/null 2>&1; eq "checksum mismatch refused" "$?" 4
yes "…and nothing kept" "[[ ! -e '$FXB/d3dcompiler_47.dll.32' ]]"
"$CD" fx reshade install >/dev/null 2>&1
BEFORE="$(ls -A "$SG/Binaries/Win64" | paste -sd ,)"
"$CD" fx mode steam:5000 reshade >/dev/null 2>&1
W="$SG/Binaries/Win64"
eq "dxgi.dll → ReShade64 beside the Shipping exe" "$(readlink "$W/dxgi.dll")" "$FXB/current/ReShade64.dll"
eq "d3dcompiler_47 linked (64-bit)" "$(readlink "$W/d3dcompiler_47.dll")" "$FXB/d3dcompiler_47.dll.64"
has "ReShade.ini: shaders searched recursively (Windows path)" "$(cat "$W/ReShade.ini")" 'EffectSearchPaths=Z:'"${HOME//\//\\}"'\.local\share\gaming-deck\reshade\Shaders\**'
has "…preset kept in the deck's folder" "$(cat "$W/ReShade.ini")" 'PresetPath=Z:'"${HOME//\//\\}"'\.local\share\gaming-deck\gaming\fx\steam_5000\ReShadePreset.ini'
has "screenshots go to Pictures/ReShade/<game>" "$(cat "$W/ReShade.ini")" 'SavePath=Z:'"${HOME//\//\\}"'\Pictures\ReShade\Story Game'
has "only the preset's effects are compiled (a quick start)" "$(cat "$W/ReShade.ini")" "SkipLoadingDisabledEffects=1"
yes "…folder created" "[[ -d '$HOME/Pictures/ReShade/Story Game' ]]"
printf '#!/bin/sh\necho "o=$WINEDLLOVERRIDES vkb=$ENABLE_VKBASALT"\n' > "$T/fake/rsgame"; chmod +x "$T/fake/rsgame"
"$CD" fx set steam:5000 sfx:501 >/dev/null 2>&1 || true
printf -- '--> Nice preset\r\nTechniques=Vibrance@Vibrance.fx,DOF@DOF.fx,Missing@Missing.fx\r\n\r\n[Vibrance.fx]\r\nVibrance=0.300000\r\n' > "$FXS/sfx/games/preset/501/download/index.html"
"$CD" fx set steam:5000 sfx:501 >/dev/null 2>&1
RP="$HOME/.local/share/gaming-deck/gaming/fx/steam_5000"
has "preset used as it is (depth effects too)" "$(cat "$RP/ReShadePreset.ini")" "Techniques=Vibrance@Vibrance.fx,DOF@DOF.fx"
eq "report: only the missing shader is flagged" "$(jq -c '[.mode, .effects, [.skipped[].effect]]' "$RP/report.json")" '["reshade",["DOF.fx","Vibrance.fx"],["Missing"]]'
eq "wrapper: DLL overrides, no vkBasalt" "$(WINEDLLOVERRIDES=foo=b SteamAppId=5000 "$CD" run "$T/fake/rsgame")" "o=foo=b;d3dcompiler_47=n;dxgi=n,b vkb="
has "menu key defaults to HOME (VK 36)" "$(cat "$W/ReShade.ini")" "KeyOverlay=36,0,0,0"
"$CD" fx key F13 >/dev/null 2>&1; eq "unknown key refused" "$?" 2
"$CD" fx key F11 >/dev/null
has "key change reaches games already set up (VK 122)" "$(cat "$W/ReShade.ini")" "KeyOverlay=122,0,0,0"
"$CD" fx mode steam:4002 vkbasalt >/dev/null 2>&1; "$CD" fx set steam:4002 builtin:sharpen >/dev/null 2>&1
eq "…and vkBasalt configs" "$(grep '^toggleKey' "$HOME/.local/share/gaming-deck/gaming/fx/steam_4002/vkBasalt.conf")" "toggleKey = F11"
eq "status reports it" "$("$CD" fx status | jq -r .key)" F11
has "effects on/off key defaults to END (VK 35)" "$(cat "$W/ReShade.ini")" "KeyEffects=35,0,0,0"
"$CD" fx effectskey F9 >/dev/null; has "…changeable, pushed to games" "$(cat "$W/ReShade.ini")" "KeyEffects=120,0,0,0"
"$CD" fx effectskey None >/dev/null; has "…or none" "$(cat "$W/ReShade.ini")" "KeyEffects=0,0,0,0"
eq "menu key kept when changing it" "$("$CD" fx status | jq -c '[.key, .effectsKey]')" '["F11","None"]'
"$CD" fx effectskey End >/dev/null
"$CD" fx link add steam:1771300 "https://www.nexusmods.com/kingdomcomedeliverance2/mods/144" >/dev/null
eq "preset page saved for a game not installed yet, labelled from the URL" "$("$CD" fx link get steam:1771300 | jq -c '[.[] | .label]')" '["Nexus #144"]'
"$CD" fx link add steam:1771300 "javascript:alert(1)" >/dev/null 2>&1; eq "only https links" "$?" 2
"$CD" fx link note steam:1771300 "https://www.nexusmods.com/kingdomcomedeliverance2/mods/144" "Use END" >/dev/null
eq "notes kept with the link" "$("$CD" fx link get steam:1771300 | jq -r '.[0].notes')" "Use END"
"$CD" fx link note steam:1771300 "https://example.org/x" "n" >/dev/null 2>&1; eq "notes only for a saved link" "$?" 2
"$CD" fx link rm steam:1771300 "https://www.nexusmods.com/kingdomcomedeliverance2/mods/144" >/dev/null
eq "removed" "$("$CD" fx link get steam:1771300)" "[]"
"$CD" fx mode steam:5000 reshade "$W/Old9.exe" d3d9 >/dev/null 2>&1
eq "switching exe/API moves the links" "$(readlink "$W/d3d9.dll") $([[ -e "$W/dxgi.dll" ]] && echo left || echo gone)" "$FXB/current/ReShade32.dll gone"
eq "32-bit d3dcompiler for a 32-bit exe" "$(readlink "$W/d3dcompiler_47.dll")" "$FXB/d3dcompiler_47.dll.32"
echo real > "$SG/dxgi.dll"
O="$("$CD" fx mode steam:5000 reshade "$SG/StoryGame.exe" dxgi 2>&1)"; eq "a game's own dxgi.dll is never replaced" "$?" 3
eq "…left untouched" "$(cat "$SG/dxgi.dll")" real
rm -f "$SG/dxgi.dll"
"$CD" fx mode steam:5000 reshade "$W/StoryGame-Win64-Shipping.exe" >/dev/null 2>&1
"$CD" fx set steam:5000 off >/dev/null
eq "OFF leaves the game folder as it was" "$(ls -A "$W" | paste -sd ,)" "$BEFORE"
eq "profile off" "$("$CD" gprofile get steam:5000 | jq -c '[.fx]')" '[false]'
"$CD" fx mode steam:5000 reshade /etc/passwd >/dev/null 2>&1; eq "only the game's own executables" "$?" 2
unset GAMING_DECK_RESHADE_URL GAMING_DECK_FF_D3DC_URL GAMING_DECK_FF_D3DC_SHA64 GAMING_DECK_FF_D3DC_SHA32 GAMING_DECK_STEAM_ROOT \
      GAMING_DECK_STEAM_RUNNING GAMING_DECK_FX_PACKAGES_URL GAMING_DECK_SFX_URL GAMING_DECK_AWACY_URL GAMING_DECK_STEAM_STORE_API
section "FX: my library (scan + set up)"
PW="$T/pcgw"; mkdir -p "$PW"
pcgw() { jq -nc --arg w "$2" '{parse:{wikitext:{"*":$w}}}' > "$PW/api.php?action=parse&page=ReShade&prop=wikitext&section=$1&format=json"; }
pcgw 15 $'===Online games to avoid===\n{|\n|-\n| [[Second Game]] || Direct3D 10+ || <span style="color: #ff0000; font-weight: bold">Banned</span> || EAC bans.\n|}'
pcgw 16 $'===Compatibility list===\n{|\n|-\n| [[Story Game|Story Game™]] || Direct3D 10+ || <span style="color: #10ab00; font-weight: bold">Perfect</span> || Game uses a reversed depth buffer. See {{Code|Copy depth}} and [https://example.org the guide].\n|}'
echo '{"Games": [{"title": "Story Game", "url": "/games/game/7/"}]}' > "$FXS/sfx/games/game/search/?query=Story%20Game"
mkdir -p "$FXS/sfx/games/preset/502/download"
printf -- '--> Popular preset\r\nTechniques=Vibrance@Vibrance.fx\r\n\r\n[Vibrance.fx]\r\nVibrance=0.200000\r\n' > "$FXS/sfx/games/preset/502/download/index.html"
export GAMING_DECK_STEAM_ROOT="$ST" GAMING_DECK_STEAM_RUNNING=0 GAMING_DECK_PCGW_API="file://$PW/api.php" \
       GAMING_DECK_RESHADE_URL="file://$RS/web" GAMING_DECK_FF_D3DC_URL="file://$RS/ff" \
       GAMING_DECK_FF_D3DC_SHA64="$FFSHA" GAMING_DECK_FF_D3DC_SHA32="$FFSHA" \
       GAMING_DECK_FX_PACKAGES_URL="file://$FXS/EffectPackages.ini" GAMING_DECK_SFX_URL="file://$FXS/sfx" \
       GAMING_DECK_AWACY_URL="file://$FXS/awacy.json" GAMING_DECK_STEAM_STORE_API="file://$FXS/store-4002.json#"
SC="$("$CD" fx scan)"
row() { jq -c --arg k "$1" '.[] | select(.key == $k)' <<<"$SC"; }
eq "best ReShade preset by downloads (old SweetFX ones ignored)" "$(row steam:5000 | jq -c '[.sfx.count, .sfx.best.id]')" '[2,"502"]'
eq "PCGamingWiki row matched (™ and link label ignored), notes cleaned" "$(row steam:5000 | jq -r '"\(.pcgw.status) | \(.pcgw.notes)"')" "Perfect | Game uses a reversed depth buffer. See Copy depth and the guide."
eq "depth note → ReShade definition" "$(row steam:5000 | jq -c .defines)" '["RESHADE_DEPTH_INPUT_IS_REVERSED=1"]'
eq "\"Online games to avoid\" → blocked, not eligible" "$(row steam:200 | jq -c '[.blocked, .eligible]')" '[true,false]'
eq "single-player game eligible" "$(row steam:5000 | jq .eligible)" true
has "a game Nexus doesn't have → a web search of Nexus" "$(row steam:5000 | jq -r .nexus)" "site%3Anexusmods.com%20Story%20Game%20reshade%20preset"
NXU() { bash -c 'source "$1"; nexus_reshade_url "$2" "$3"' _ "$CD" "$@"; }
eq "a game on Nexus → its own ReShade search" "$(NXU steam:1 'ELDEN RING')" "https://www.nexusmods.com/games/eldenring/search?keyword=RESHADE"
eq "…™ and a subtitle in brackets don't get in the way" "$(NXU steam:2 'Hogwarts Legacy™ (Deluxe)')" "https://www.nexusmods.com/games/hogwartslegacy/search?keyword=RESHADE"
eq "…Lords of the Fallen (Steam 1501750) is the 2023 one, not the 2014 one" "$(NXU steam:1501750 'Lords of the Fallen')" "https://www.nexusmods.com/games/lordsofthefallen2023/search?keyword=RESHADE"
eq "cached copy for the GUI" "$("$CD" fx scan --cached | jq length)" "$(jq length <<<"$SC")"
O="$("$CD" fx autoinstall steam:5000 steam:200 2>&1)"
has "blocked game skipped, with the reason" "$O" "Second Game: skipped (ReShade is banned"
RP="$HOME/.local/share/gaming-deck/gaming/fx/steam_5000"
eq "Story Game: ReShade with the most downloaded preset" "$(jq -c '[.mode, .source, .id]' "$RP/report.json")" '["reshade","sfx","502"]'
has "depth definition written to its ReShade.ini" "$(cat "$SG/Binaries/Win64/ReShade.ini")" "PreprocessorDefinitions=RESHADE_DEPTH_INPUT_IS_REVERSED=1"
bash -c 'source "$1"; reshade_defines steam:5000 RESHADE_DEPTH_INPUT_IS_REVERSED=1 FOO=2' _ "$CD"
has "definitions merged, no duplicates" "$(grep PreprocessorDefinitions "$SG/Binaries/Win64/ReShade.ini")" "=RESHADE_DEPTH_INPUT_IS_REVERSED=1,FOO=2"
"$CD" fx set steam:5000 off >/dev/null
unset GAMING_DECK_PCGW_API GAMING_DECK_RESHADE_URL GAMING_DECK_FF_D3DC_URL GAMING_DECK_FF_D3DC_SHA64 GAMING_DECK_FF_D3DC_SHA32 \
      GAMING_DECK_STEAM_ROOT GAMING_DECK_STEAM_RUNNING GAMING_DECK_FX_PACKAGES_URL GAMING_DECK_SFX_URL GAMING_DECK_AWACY_URL GAMING_DECK_STEAM_STORE_API

section "FX: import a downloaded preset (Nexus…)"
export GAMING_DECK_STEAM_ROOT="$ST" GAMING_DECK_STEAM_RUNNING=0 \
       GAMING_DECK_RESHADE_URL="file://$RS/web" GAMING_DECK_FF_D3DC_URL="file://$RS/ff" \
       GAMING_DECK_FF_D3DC_SHA64="$FFSHA" GAMING_DECK_FF_D3DC_SHA32="$FFSHA" \
       GAMING_DECK_FX_PACKAGES_URL="file://$FXS/EffectPackages.ini" GAMING_DECK_SFX_URL="file://$FXS/sfx" \
       GAMING_DECK_AWACY_URL="file://$FXS/awacy.json" GAMING_DECK_STEAM_STORE_API="file://$FXS/store-4002.json#"
NX="$T/nexus/Realistica ReShade"; mkdir -p "$NX/reshade-shaders/Shaders" "$NX/reshade-shaders/Textures" "$NX/Alt"
printf 'Techniques=Vibrance@Vibrance.fx,Grain@MyGrain.fx\r\n[MyGrain.fx]\r\nAmount=0.5\r\n' > "$NX/Realistica.ini"
printf 'Techniques=Vibrance@Vibrance.fx\r\n' > "$NX/Alt/Soft.ini"
printf '[GENERAL]\nEffectSearchPaths=.\\reshade-shaders\\Shaders\n' > "$NX/ReShade.ini"
echo 'technique Grain { pass { } }' > "$NX/reshade-shaders/Shaders/MyGrain.fx"
echo 'technique Vibrance { pass { } }' > "$NX/reshade-shaders/Shaders/Vibrance.fx"
echo png > "$NX/reshade-shaders/Textures/grain.png"; echo MZ > "$NX/dxgi.dll"
( cd "$T/nexus" && bsdtar -a -cf "$T/nexus/Realistica.zip" "Realistica ReShade" )
eq "presets found in the archive, the bigger one first (ReShade.ini isn't one)" \
   "$("$CD" fx importlist "$T/nexus/Realistica.zip" | jq -c '[.[] | [.path, .effects]]')" \
   '[["Realistica ReShade/Realistica.ini",2],["Realistica ReShade/Alt/Soft.ini",1]]'
"$CD" fx mode steam:5000 reshade >/dev/null 2>&1
O="$("$CD" fx import steam:5000 "$T/nexus/Realistica.zip" 2>&1)"; eq "import succeeds" "$?" 0
RP="$HOME/.local/share/gaming-deck/gaming/fx/steam_5000"; FXD="$HOME/.local/share/gaming-deck/reshade"
eq "applied as the game's preset, named after the file" "$(jq -c '[.source, .name, .mode, .effects]' "$RP/report.json")" '["file","Realistica","reshade",["MyGrain.fx","Vibrance.fx"]]'
has "preset content kept as is" "$(cat "$RP/ReShadePreset.ini")" "Amount=0.5"
eq "import records the archive it came from" "$(jq -r '.archive' "$RP/report.json")" "Realistica.zip"
yes "the archive's own shader copied" "[[ -f '$FXD/Shaders/imported/Realistica/MyGrain.fx' ]]"
yes "a shader we already have isn't duplicated" "[[ ! -e '$FXD/Shaders/imported/Realistica/Vibrance.fx' ]]"
yes "texture copied" "[[ -f '$FXD/Textures/grain.png' ]]"
eq "its ReShade.ini / dxgi.dll are not used" "$(readlink "$SG/Binaries/Win64/dxgi.dll")" "$HOME/.local/share/gaming-deck/reshade/bin/current/ReShade64.dll"
"$CD" fx import steam:5000 "$T/nexus/Realistica.zip" "Realistica ReShade/Alt/Soft.ini" >/dev/null 2>&1
eq "a chosen preset from the archive" "$(jq -r .name "$RP/report.json")" "Soft"
"$CD" fx mode steam:5000 vkbasalt >/dev/null 2>&1
eq "switching route keeps an imported look" "$(jq -c '[.source, .name, .mode]' "$RP/report.json")" '["file","Soft","vkbasalt"]'
LK() { "$CD" fx looks steam:5000 | jq -c 'map(select(.source == "file"))'; }   # (the SweetFX looks of earlier tests are there too)
eq "MY LOOKS keeps both imported presets, the one on now first" "$(LK | jq -c '[.[] | [.name, .current]]')" '[["Soft",true],["Realistica",false]]'
"$CD" fx look use steam:5000 "$(LK | jq -r '.[] | select(.name == "Realistica") | .slug')" >/dev/null 2>&1
eq "…one click puts an earlier one back, without its archive" "$(jq -c '[.name, .source, .archive]' "$RP/report.json")" '["Realistica","file","Realistica.zip"]'
eq "…and it stays one entry, not a new one" "$(LK | jq -c '[.[] | [.name, .current]]')" '[["Realistica",true],["Soft",false]]'
"$CD" fx look rm steam:5000 "$(LK | jq -r '.[] | select(.name == "Soft") | .slug')" >/dev/null
eq "✕ takes one off the list" "$(LK | jq -c '[.[].name]')" '["Realistica"]'
"$CD" fx look use steam:5000 'file-../x' >/dev/null 2>&1; eq "a bad look id is refused" "$?" 2
"$CD" fx mode steam:5000 reshade >/dev/null 2>&1
printf '10:00:00:001 [ 1] | INFO  | Initializing\r\n10:00:01:000 [ 2] | ERROR | Failed to compile '"'"'Z:\\x\\Shaders\\MyGrain.fx'"'"':\r\nZ:\\x\\MyGrain.fx(3, 1): preprocessor error: could not open included file '"'"'Lib/A.fxh'"'"'\r\n10:00:01:500 [ 2] | ERROR | Failed to compile '"'"'Z:\\x\\Other.fx'"'"':\r\nZ:\\x\\Other.fx(1, 1): error X3000: syntax error\r\n10:00:02:000 [ 2] | INFO  | done\r\n' > "$SG/Binaries/Win64/ReShade.log"
eq "ReShade.log: what didn't build, why, and whether this look uses it" "$("$CD" fx status steam:5000 | jq -c '[.logErrors.errors[] | [.file, .inLook, .why]]')" \
   '[["MyGrain.fx",true,"preprocessor error: could not open included file '"'"'Lib/A.fxh'"'"'"],["Other.fx",false,"error X3000: syntax error"]]'
echo 'nothing' > "$T/nexus/readme.txt"
"$CD" fx import steam:5000 "$T/nexus/readme.txt" >/dev/null 2>&1; eq "a file without a preset is refused" "$?" 4
mkdir -p "$T/nexus/onlyfx"; echo 'technique Sharp2 { pass { } }' > "$T/nexus/onlyfx/Sharp2.fx"; cp "$NX/reshade-shaders/Shaders/Vibrance.fx" "$T/nexus/onlyfx/"
( cd "$T/nexus/onlyfx" && bsdtar -a -cf "$T/nexus/onlyfx.zip" Sharp2.fx Vibrance.fx )
eq "an archive of shaders only: no presets…" "$("$CD" fx importlist "$T/nexus/onlyfx.zip")" "[]"
eq "…addshaders keeps the new ones and names the ones already there" "$("$CD" fx addshaders "$T/nexus/onlyfx.zip" | jq -c .)" '{"added":["Sharp2.fx"],"had":["Vibrance.fx"]}'
mkdir -p "$T/nexus/deep/pack/reshade-shaders/Shaders/Include/Lib"
printf '#include "Include/Lib/Common.fxh"\ntechnique Deep { pass { } }\n' > "$T/nexus/deep/pack/reshade-shaders/Shaders/DeepFX.fx"
echo '// another pack' > "$T/nexus/deep/pack/reshade-shaders/Shaders/Include/Lib/Common.fxh"
( cd "$T/nexus/deep" && bsdtar -a -cf "$T/nexus/deep.zip" pack )
"$CD" fx addshaders "$T/nexus/deep.zip" >/dev/null
yes "the folders under Shaders are kept, so relative includes still work" "[[ -f '$HOME/.local/share/gaming-deck/reshade/Shaders/imported/deep/DeepFX.fx' && -f '$HOME/.local/share/gaming-deck/reshade/Shaders/imported/deep/Include/Lib/Common.fxh' ]]"
"$CD" fx set steam:5000 off >/dev/null
unset GAMING_DECK_RESHADE_URL GAMING_DECK_FF_D3DC_URL GAMING_DECK_FF_D3DC_SHA64 GAMING_DECK_FF_D3DC_SHA32 \
      GAMING_DECK_STEAM_ROOT GAMING_DECK_STEAM_RUNNING GAMING_DECK_FX_PACKAGES_URL GAMING_DECK_SFX_URL GAMING_DECK_AWACY_URL GAMING_DECK_STEAM_STORE_API
section "STATUS: live details"
GS="$(GAMING_DECK_GPU_VENDOR=intel "$CD" gstatus)"
eq "system block (kernel, threads, RAM)" "$(jq -c '[(.system.kernel | length > 0), (.system.threads > 0), (.system.memTotal > 0)]' <<<"$GS")" '[true,true,true]'
eq "GPU block even without vendor tools" "$(jq -r .gpu.vendor <<<"$GS")" intel
eq "displays list (no hyprctl → empty)" "$(jq -c '.displays | type' <<<"$GS")" '"array"'
eq "tools block" "$(jq -c '.tools | has("steam") and has("ntsync") and has("protons")' <<<"$GS")" true
eq "library block (games, disks, caches, health)" "$(jq -c '.library | [has("games"), (.disks | type), has("shaders"), has("prefixes"), has("health"), (.recent | type)]' <<<"$GS")" '[true,"array",true,true,true,"array"]'
eq "NVIDIA clock reasons decoded" "$(bash -c 'source "$1"; nv_reasons 0x0000000000000044' _ "$CD")" '["power cap","thermal (hw)"]'
mkdir -p "$T/proc3/7100" "$T/proc3/7101"
printf 'SteamAppId=300\0WINEDLLOVERRIDES=d3dcompiler_47=n;dxgi=n,b\0' > "$T/proc3/7100/environ"; printf 'game.exe\0' > "$T/proc3/7100/cmdline"
printf 'SteamAppId=300\0' > "$T/proc3/7101/environ"
printf '/usr/bin/python3\0%s\0waitforexitandrun\0game.exe\0' "$HOME/.steam/compatibilitytools.d/GE-Proton10-3/proton" > "$T/proc3/7101/cmdline"
D="$(PROC_ROOT="$T/proc3" bash -c 'source "$1"; gs_running_detail steam:300 7100' _ "$CD")"
eq "running game: Proton build and shaders in use" "$(jq -c '[.proton, .fx]' <<<"$D")" '["GE-Proton10-3","ReShade"]'
section "GE-Proton updates"
GE="$T/ge"; GA="$GE/api/repos/GloriousEggroll/proton-ge-custom/releases"; mkdir -p "$GA/tags" "$GE/dl/GE-Proton12-1-x86_64/files"
echo "script" > "$GE/dl/GE-Proton12-1-x86_64/proton"; echo "1 GE-Proton12-1" > "$GE/dl/GE-Proton12-1-x86_64/version"
( cd "$GE/dl" && bsdtar -czf GE-Proton12-1-x86_64.tar.gz GE-Proton12-1-x86_64 && sha512sum GE-Proton12-1-x86_64.tar.gz > GE-Proton12-1-x86_64.sha512sum )
cat > "$GA/latest" <<EOF
{"tag_name":"GE-Proton12-1","assets":[
 {"name":"GE-Proton12-1-aarch64.tar.gz","size":1,"browser_download_url":"file://$GE/dl/nope.tar.gz"},
 {"name":"GE-Proton12-1-x86_64.tar.gz","size":100,"browser_download_url":"file://$GE/dl/GE-Proton12-1-x86_64.tar.gz"},
 {"name":"GE-Proton12-1-x86_64.sha512sum","size":1,"browser_download_url":"file://$GE/dl/GE-Proton12-1-x86_64.sha512sum"}]}
EOF
cp "$GA/latest" "$GA/tags/GE-Proton12-1"
GST="$HOME/ge-steam"; mkdir -p "$GST/compatibilitytools.d/GE-Proton11-7-x86_64"
export GAMING_DECK_STEAM_ROOT="$GST" GAMING_DECK_GH_API="file://$GE/api"
eq "no GE installed → nothing offered" "$(GAMING_DECK_STEAM_ROOT="$HOME/none" bash -c 'source "$1"; upd_proton' _ "$CD")" ""
eq "newer GE offered" "$(bash -c 'source "$1"; upd_proton' _ "$CD" | paste -sd '|')" "proton|GE-Proton12-1|GE-Proton|GE-Proton11-7|GE-Proton12-1"
eq "proton status: installed, latest, update" "$("$CD" proton status | jq -c '[.installed, .latest, .update]')" '["GE-Proton11-7","GE-Proton12-1",true]'
"$CD" proton install GE-Proton12-1 >/dev/null 2>&1
yes "installed next to the old one (x86_64 build, checksum ok)" "[[ -f '$GST/compatibilitytools.d/GE-Proton12-1-x86_64/proton' && -d '$GST/compatibilitytools.d/GE-Proton11-7-x86_64' ]]"
eq "…then up to date" "$(bash -c 'source "$1"; upd_proton' _ "$CD")" ""
rm -rf "$GST/compatibilitytools.d/GE-Proton12-1-x86_64"; echo "0000  GE-Proton12-1-x86_64.tar.gz" > "$GE/dl/GE-Proton12-1-x86_64.sha512sum"
"$CD" proton install GE-Proton12-1 >/dev/null 2>&1; eq "bad checksum refused" "$?" 4
yes "…nothing left behind" "[[ ! -e '$GST/compatibilitytools.d/GE-Proton12-1-x86_64' ]]"
"$CD" proton install 'x;rm' >/dev/null 2>&1; eq "bad tag refused" "$?" 2
unset GAMING_DECK_STEAM_ROOT GAMING_DECK_GH_API
section "Umbral games: FX + TEMPS through the hook"
UG="$HOME/Games/umbral/games/StoryU"; mkdir -p "$UG" "$HOME/Games/umbral/games/Rpg"
mkpe "$UG/StoryU.exe" dxgi.dll 0x8664
mkpe "$HOME/Games/umbral/games/Rpg/Game.exe" kernel32.dll 0x14c; touch "$HOME/Games/umbral/games/Rpg/RGSS102E.dll"
cat > "$T/umbral-fx.json" <<EOF
{"prefixes":[{"id":"p","name":"P","path":"$HOME/Games/umbral/pfx","runner":"GE-Proton"}],
 "games":[{"id":"story","name":"Story U","kind":"custom","prefix_id":"p","exe":"$UG/StoryU.exe"},
          {"id":"rpg","name":"Rpg Game","kind":"custom","prefix_id":"p","exe":"$HOME/Games/umbral/games/Rpg/Game.exe"},
          {"id":"battlenet:wow","name":"World of Warcraft: Forever (beta)","kind":"blizzard","prefix_id":"p","exe":"$UG/StoryU.exe"}]}
EOF
echo '[{"name":"World of Warcraft","anticheats":["Warden"],"status":"Running","storeIds":{}},{"name":"Doom","anticheats":["X"],"status":"Running","storeIds":{}}]' > "$T/awacy-u.json"
export GAMING_DECK_UMBRAL_CONFIG="$T/umbral-fx.json" GAMING_DECK_AWACY_URL="file://$T/awacy-u.json" \
       GAMING_DECK_RESHADE_URL="file://$RS/web" GAMING_DECK_FF_D3DC_URL="file://$RS/ff" GAMING_DECK_FF_D3DC_SHA64="$FFSHA" GAMING_DECK_FF_D3DC_SHA32="$FFSHA"
rm -f "$HOME/.cache/gaming-deck/fx/awacy.json"
eq "Umbral game: its own .exe, API from imports" "$("$CD" fx exes umbral:story | jq -c '.[0] | [.rel, .arch, .api]')" '["StoryU.exe",64,"dxgi"]'
eq "tiny RPG Maker Game.exe kept, marked GDI" "$("$CD" fx exes umbral:rpg | jq -c '.[0] | [.rel, .api]')" '["Game.exe","gdi"]'
eq "…nothing recommended for it" "$("$CD" fx status umbral:rpg | jq -r .recommended)" none
"$CD" fx mode umbral:rpg reshade >/dev/null 2>&1; eq "…and ReShade refused" "$?" 3
eq "anti-cheat by name prefix (AreWeAntiCheatYet)" "$("$CD" fx status umbral:battlenet:wow | jq -c '.online | [.level, .anticheats]')" '["anticheat",["Warden"]]'
eq "short names don't match loosely" "$("$CD" fx status umbral:story | jq -r .online.level)" none
"$CD" fx mode umbral:story reshade >/dev/null 2>&1
eq "ReShade next to the Umbral game's exe" "$(readlink "$UG/dxgi.dll")" "$HOME/.local/share/gaming-deck/reshade/bin/current/ReShade64.dll"
"$CD" fx set umbral:story builtin:sharpen >/dev/null 2>&1
"$CD" gprofile set umbral:story overlay=true >/dev/null
eq "hook: DLL overrides + TEMPS for Umbral" "$("$CD" hook umbral:story)" '{"env":{"WINEDLLOVERRIDES":"d3dcompiler_47=n;dxgi=n,b"},"overlay":true,"session":true}'
eq "hook: nothing set → no env, no TEMPS (session on for the summary)" "$("$CD" hook umbral:rpg)" '{"env":{},"overlay":false,"session":true}'
"$CD" fx set umbral:story off >/dev/null
yes "OFF cleans the Umbral game's folder" "[[ ! -e '$UG/dxgi.dll' ]]"
unset GAMING_DECK_UMBRAL_CONFIG GAMING_DECK_AWACY_URL GAMING_DECK_RESHADE_URL GAMING_DECK_FF_D3DC_URL GAMING_DECK_FF_D3DC_SHA64 GAMING_DECK_FF_D3DC_SHA32
section "CPU scheduler + game session + crash notice"
stub scxctl 'echo "scxctl $*" >> "'"$T"'/scx.log"; case "$1" in start|switch) echo enabled > "'"$T"'/scxsys/kernel/sched_ext/state";; stop) echo disabled > "'"$T"'/scxsys/kernel/sched_ext/state";; esac'
mkdir -p "$T/scxsys/kernel/sched_ext"; echo disabled > "$T/scxsys/kernel/sched_ext/state"
export GAMING_DECK_SYSFS="$T/scxsys" GAMING_DECK_SCX_TOML="$T/scx_loader.toml"
eq "status: nothing running, nothing set" "$("$CD" sched status | jq -c '[.running, .whilePlaying, .bootDefault]')" '[false,null,null]'
"$CD" sched start lavd gaming >/dev/null; has "start → scxctl start" "$(cat "$T/scx.log")" "scxctl start --sched lavd --mode gaming"
"$CD" sched start bpfland auto >/dev/null; has "already running → switch" "$(cat "$T/scx.log")" "scxctl switch --sched bpfland --mode auto"
"$CD" sched stop >/dev/null; has "stop" "$(cat "$T/scx.log")" "scxctl stop"
"$CD" sched start 'x;y' >/dev/null 2>&1; eq "bad name refused" "$?" 2
"$CD" sched playing lavd:gaming >/dev/null
eq "while-playing setting saved" "$("$CD" sched status | jq -r .whilePlaying)" "lavd:gaming"
rm -f "$T/scx.log"; printf '#!/bin/sh\nexit 0\n' > "$T/fake/okgame"; chmod +x "$T/fake/okgame"
SteamAppId=100 "$CD" run "$T/fake/okgame" >/dev/null 2>&1
eq "game session: started lavd, stopped it at exit" "$(grep -o 'scxctl [a-z]*' "$T/scx.log" | paste -sd ,)" "scxctl start,scxctl stop"
echo enabled > "$T/scxsys/kernel/sched_ext/state"; rm -f "$T/scx.log"
SteamAppId=100 "$CD" run "$T/fake/okgame" >/dev/null 2>&1
yes "a scheduler you already run is left alone" "[[ ! -s '$T/scx.log' ]]"
echo disabled > "$T/scxsys/kernel/sched_ext/state"; "$CD" sched playing off >/dev/null
rm -f "$T/scx.log"; SteamAppId=100 "$CD" run "$T/fake/okgame" >/dev/null 2>&1
yes "setting off → scheduler untouched" "[[ ! -s '$T/scx.log' ]]"
# exit code and crash notice
stub notify-send 'echo "notify $*" >> "'"$T"'/notify.log"'
printf '#!/bin/sh\nexit 3\n' > "$T/fake/badgame"; chmod +x "$T/fake/badgame"
rm -f "$T/notify.log"; SteamAppId=100 "$CD" run "$T/fake/badgame" >/dev/null 2>&1; eq "the game's exit code is kept" "$?" 3
has "crash notice with the game's name and code" "$(cat "$T/notify.log")" "closed with an error"
has "…suggesting PROTON_LOG when there's no log" "$(cat "$T/notify.log")" "PROTON_LOG=1"
rm -f "$T/notify.log"; printf '#!/bin/sh\nkill -TERM $$\n' > "$T/fake/killed"; chmod +x "$T/fake/killed"
SteamAppId=100 "$CD" run "$T/fake/killed" >/dev/null 2>&1
yes "killed by a signal (Steam's STOP) isn't a crash" "[[ ! -s '$T/notify.log' ]]"
unset GAMING_DECK_SYSFS GAMING_DECK_SCX_TOML
section "Profiles between PCs (backup + check for this PC)"
"$CD" gprofile set steam:600 'env=__GL_SHADER_DISK_CACHE_SIZE=1000 RADV_PERFTEST=gpl DXVK_ASYNC=1' >/dev/null
BK="$T/bk.json"; "$CD" export "$BK" >/dev/null 2>&1
eq "backup carries game profiles" "$(jq -r '.gaming.profiles["steam:600"].env.DXVK_ASYNC' "$BK")" 1
A="$(GAMING_DECK_GPU_VENDOR=amd "$CD" gaudit)"
eq "on AMD: NVIDIA-only variable flagged, AMD and neutral ones not" "$(jq -c '[.issues[] | select(.key == "steam:600") | .var]' <<<"$A")" '["__GL_SHADER_DISK_CACHE_SIZE"]'
N="$(GAMING_DECK_GPU_VENDOR=nvidia "$CD" gaudit)"
eq "on NVIDIA: the AMD one flagged" "$(jq -c '[.issues[] | select(.key == "steam:600") | .var]' <<<"$N")" '["RADV_PERFTEST"]'
GAMING_DECK_GPU_VENDOR=amd "$CD" gaudit fix steam:600 >/dev/null
eq "fix drops only what does nothing on this GPU" "$("$CD" gprofile get steam:600 | jq -c '.env | keys')" '["DXVK_ASYNC","RADV_PERFTEST"]'
"$CD" gprofile reset steam:600 >/dev/null; "$CD" gprofile set steam:601 'env=A=1' >/dev/null
"$CD" gaming-import "$BK" >/dev/null 2>&1
eq "import adds what's missing here" "$("$CD" gprofile get steam:600 | jq -r '.env.__GL_SHADER_DISK_CACHE_SIZE')" 1000
eq "…and keeps what's already here" "$("$CD" gprofile get steam:601 | jq -r '.env.A')" 1
"$CD" gprofile reset steam:600 >/dev/null
jq '.app = "control-deck"' "$BK" > "$T/bk-cd.json"
"$CD" gaming-import "$T/bk-cd.json" >/dev/null 2>&1; eq "a Control Deck backup imports too" "$?" 0
eq "…with its profiles" "$("$CD" gprofile get steam:600 | jq -r '.env.__GL_SHADER_DISK_CACHE_SIZE')" 1000
jq '.app = "system-deck"' "$BK" > "$T/bk-sd.json"
"$CD" gaming-import "$T/bk-sd.json" >/dev/null 2>&1; eq "another app's backup is refused" "$?" 2
has "export says where it saved (the BACKUP card reads that line)" "$("$CD" export "$T/bk2.json" 2>&1)" "Backup saved to $T/bk2.json"
section "FX: which route for which game"
ADV() { bash -c 'source "$1"; fx_advice "$2" "$3" "$4" "$5"' _ "$CD" "$@"; }
eq "DirectX single-player → ReShade" "$(ADV steam:1 '[{"api":"dxgi"}]' '{"level":"none"}' null | jq -r .pick)" reshade
eq "Vulkan → vkBasalt" "$(ADV steam:1 '[{"api":"vulkan"}]' '{"level":"none"}' null | jq -r .pick)" vkbasalt
eq "GDI → none" "$(ADV steam:1 '[{"api":"gdi"}]' null null | jq -r .pick)" none
eq "anti-cheat → vkBasalt, saying neither is safe" "$(ADV steam:1 '[{"api":"dxgi"}]' '{"level":"anticheat","anticheats":["EAC"]}' null | jq -r '.pick + " | " + .reasons[0]')" "vkbasalt | Online game with anti-cheat (EAC): neither is safe there."
eq "anti-cheat that accepts ReShade (Elden Ring) → ReShade" "$(ADV steam:1245620 '[{"api":"dxgi"}]' '{"level":"anticheat","anticheats":["EAC"]}' null | jq -r .pick)" reshade
has "a preset with depth effects is a reason for ReShade" "$(ADV steam:1 '[{"api":"dxgi"}]' '{"level":"none"}' '{"skipped":[{"why":"uses the depth buffer"}]}' | jq -r '.reasons | join(" ")')" "1 depth effect(s)"
NG="$ST/steamapps/common/NativeGame"; mkdir -p "$NG"; man 7000 "Native Game" NativeGame 1
{ printf '\x7fELF'; head -c 600000 /dev/zero; printf 'libvulkan.so.1'; } > "$NG/game.x86_64"; chmod +x "$NG/game.x86_64"
eq "native Linux + Vulkan → vkBasalt" "$(GAMING_DECK_STEAM_ROOT="$ST" ADV steam:7000 '[]' null null | jq -r .pick)" vkbasalt
{ printf '\x7fELF'; head -c 600000 /dev/zero; printf 'libGL.so.1'; } > "$NG/game.x86_64"
eq "native Linux + OpenGL → none" "$(GAMING_DECK_STEAM_ROOT="$ST" ADV steam:7000 '[]' null null | jq -r .pick)" none
section "Upscaler upgrades (FSR 4 / DLSS / XeSS)"
UP="$HOME/up-steam"; mkdir -p "$UP/steamapps/common/Up/bin" "$UP/compatibilitytools.d/GE-Test" "$UP/config"
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' "$UP" > "$UP/steamapps/libraryfolders.vdf"
printf '"AppState"\n{\n\t"appid"\t\t"8000"\n\t"name"\t\t"Up Game"\n\t"installdir"\t\t"Up"\n}\n' > "$UP/steamapps/appmanifest_8000.acf"
touch "$UP/steamapps/common/Up/bin/amd_fidelityfx_dx12.dll" "$UP/steamapps/common/Up/bin/nvngx_dlss.dll"
printf '"compatibilitytools"\n{\n  "compat_tools"\n  {\n    "GE-Test"\n    {\n    }\n  }\n}\n' > "$UP/compatibilitytools.d/GE-Test/compatibilitytool.vdf"
printf 'check_environment("PROTON_FSR4_UPGRADE", "fsr4")\ncheck_environment("PROTON_DLSS_UPGRADE", "dlss")\ncheck_environment("PROTON_XESS_UPGRADE", "xess")\ncheck_environment("PROTON_FSR4_INDICATOR", "fsr4hud")\n' > "$UP/compatibilitytools.d/GE-Test/proton"
UPS() { GAMING_DECK_STEAM_ROOT="$UP" GAMING_DECK_GPU_VENDOR="$1" GAMING_DECK_GPU_NAME="$2" "$CD" upscale steam:8000; }
eq "detects what the game ships" "$(UPS amd 'AMD Radeon RX 9070 XT' | jq -c .ships)" '{"fsr31dx12":true,"fsr31vk":false,"dlss":true,"xess":false,"fsr2":false}'
# FidelityFX SDK 2 (FSR 3.1.4+) names its DLLs differently (Kingdom Come: Deliverance II ships these)
mv "$UP/steamapps/common/Up/bin/amd_fidelityfx_dx12.dll" "$UP/steamapps/common/Up/bin/amd_fidelityfx_upscaler_dx12.dll"
touch "$UP/steamapps/common/Up/bin/amd_fidelityfx_loader_dx12.dll"
eq "…FidelityFX SDK 2 DLLs count as FSR 3.1 DX12 too" "$(UPS amd 'AMD Radeon RX 9070 XT' | jq -r .ships.fsr31dx12)" true
rm "$UP/steamapps/common/Up/bin/amd_fidelityfx_loader_dx12.dll"; mv "$UP/steamapps/common/Up/bin/amd_fidelityfx_upscaler_dx12.dll" "$UP/steamapps/common/Up/bin/amd_fidelityfx_dx12.dll"
eq "Steam default Proton → no upgrades" "$(UPS amd 'AMD Radeon RX 9070 XT' | jq -r '.options[] | select(.id == "fsr4") | .why')" "This game's Proton can't do it: pick GE-Proton or Proton-CachyOS in PROTON."
printf '"InstallConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t\t"CompatToolMapping"\n\t\t\t\t{\n\t\t\t\t\t"8000"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"GE-Test"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n' > "$UP/config/config.vdf"
eq "RX 9070 XT + GE: FSR 4 available" "$(UPS amd 'AMD Radeon RX 9070 XT' | jq -c '[.options[] | select(.id == "fsr4") | .available, .var]')" '[true,"PROTON_FSR4_UPGRADE"]'
eq "…DLSS not (needs RTX)" "$(UPS amd 'AMD Radeon RX 9070 XT' | jq -r '.options[] | select(.id == "dlss") | .why')" "DLSS needs an NVIDIA RTX card."
eq "RTX 2070: DLSS yes, FSR 4 no" "$(UPS nvidia 'NVIDIA GeForce RTX 2070' | jq -c '[.options[] | select(.id == "fsr4" or .id == "dlss") | .available]')" '[false,true]'
eq "RX 7900 without GE's RDNA3 switch → explained" "$(UPS amd 'AMD Radeon RX 7900 XTX' | jq -r '.options[] | select(.id == "fsr4") | .why')" "RX 7000 (RDNA3) needs GE-Proton's RDNA3 variant."
eq "XeSS: game doesn't ship it" "$(UPS amd 'AMD Radeon RX 9070 XT' | jq -r '.options[] | select(.id == "xess") | .why')" "The game doesn't ship XeSS."
GAMING_DECK_STEAM_ROOT="$UP" "$CD" gprofile set steam:8000 'env=PROTON_FSR4_UPGRADE=1' >/dev/null
eq "turned on → reported on" "$(UPS amd 'AMD Radeon RX 9070 XT' | jq -r '.options[] | select(.id == "fsr4") | .on')" true
eq "FSR 4 flagged when the profile moves to an NVIDIA PC" "$(GAMING_DECK_GPU_VENDOR=nvidia "$CD" gaudit | jq -c '[.issues[] | select(.key == "steam:8000") | .var]')" '["PROTON_FSR4_UPGRADE"]'
printf 'check_environment("PROTON_USE_OPTISCALER", "optiscaler")\n' >> "$UP/compatibilitytools.d/GE-Test/proton"
OPT="$(UPS amd 'AMD Radeon RX 9070 XT' | jq -c '.options[] | select(.id == "optifsr4")')"
eq "OptiScaler FSR 4 available (DLSS in the game, RDNA4, GE)" "$(jq -r .available <<<"$OPT")" true
eq "…writes everything Proton needs, nothing to install" "$(jq -c '.set | keys' <<<"$OPT")" '["PROTON_FSR4_UPGRADE","PROTON_OPTISCALER_CONFIG","PROTON_USE_OPTISCALER"]'
has "…FSR 4 for DX12, DX11 and Vulkan games" "$(jq -r '.set.PROTON_OPTISCALER_CONFIG' <<<"$OPT")" "Upscalers.Dx12Upscaler=fsr31;Upscalers.Dx11Upscaler=fsr31_12;Upscalers.VulkanUpscaler=fsr31_12"
eq "the game has FSR 3.1: the direct chip is simpler" "$(UPS amd 'AMD Radeon RX 9070 XT' | jq .preferDirect)" true
eq "not on the RTX 2070" "$(UPS nvidia 'NVIDIA GeForce RTX 2070' | jq -r '.options[] | select(.id == "optifsr4") | .available')" false
printf '#!/bin/sh\necho "name=$PROTON_OPTISCALER_NAME cfg=$PROTON_OPTISCALER_CONFIG"\n' > "$T/fake/optgame"; chmod +x "$T/fake/optgame"
GAMING_DECK_STEAM_ROOT="$UP" "$CD" gprofile set steam:8000 'env=PROTON_USE_OPTISCALER=1 PROTON_OPTISCALER_CONFIG=Upscalers.Dx12Upscaler=fsr31' fx=true >/dev/null 2>&1 \
    || GAMING_DECK_STEAM_ROOT="$UP" "$CD" gprofile set steam:8000 'env=PROTON_USE_OPTISCALER=1 PROTON_OPTISCALER_CONFIG=Upscalers.Dx12Upscaler=fsr31' >/dev/null
mkdir -p "$HOME/.local/share/gaming-deck/gaming/fx/steam_8000"
echo '{"key":"steam:8000","dir":"/x","api":"dxgi"}' > "$HOME/.local/share/gaming-deck/gaming/fx/steam_8000/reshade.json"
bash -c 'source "$1"; profile_write steam:8000 "{\"fx\":true,\"fxMode\":\"reshade\"}"' _ "$CD"
"$CD" fx key Insert >/dev/null
O="$(GAMING_DECK_STEAM_ROOT="$UP" SteamAppId=8000 "$CD" run "$T/fake/optgame" 2>/dev/null)"
has "OptiScaler moves to winmm.dll next to ReShade's dxgi.dll" "$O" "name=winmm.dll"
has "…and its menu off INSERT when INSERT is the shader key" "$O" "Menu.ShortcutKey=0x22"
"$CD" fx key F11 >/dev/null; rm -rf "$HOME/.local/share/gaming-deck/gaming/fx/steam_8000"
section "Game session summary"
export GAMING_DECK_SESSION_MIN=0 GAMING_DECK_SESSION_EVERY=1 GAMING_DECK_GPU_VENDOR=intel GAMING_DECK_STEAM_ROOT="$ST" GAMING_DECK_STEAM_RUNNING=0
rm -f "$T/notify.log"; printf '#!/bin/sh\nsleep 2\nexit 0\n' > "$T/fake/sgame"; chmod +x "$T/fake/sgame"
SteamAppId=100 "$CD" run "$T/fake/sgame" >/dev/null 2>&1
S1="$("$CD" sessions 1)"
eq "session saved with the game's name" "$(jq -r '.[0].name' <<<"$S1")" 'Game "Quoted" One'
yes "samples recorded while it ran" "(( $(jq '.[0].samples' <<<"$S1") >= 1 ))"
eq "RAM measured" "$(jq '.[0].ramMax > 0' <<<"$S1")" true
has "summary notification" "$(cat "$T/notify.log")" 'Game "Quoted" One · 0 min'
"$CD" sessions off >/dev/null; rm -f "$T/notify.log"
SteamAppId=100 "$CD" run "$T/fake/sgame" >/dev/null 2>&1
yes "off → no summary" "[[ ! -s '$T/notify.log' ]]"
eq "…and nothing added" "$("$CD" sessions | jq length)" 1
"$CD" sessions on >/dev/null
GAMING_DECK_SESSION_MIN=60 SteamAppId=100 "$CD" run "$T/fake/sgame" >/dev/null 2>&1
eq "short runs (< 1 min) aren't kept" "$("$CD" sessions | jq length)" 1
unset GAMING_DECK_SESSION_MIN GAMING_DECK_SESSION_EVERY GAMING_DECK_GPU_VENDOR GAMING_DECK_STEAM_ROOT GAMING_DECK_STEAM_RUNNING
section "While playing: quiet notifications + lighter Hyprland"
HY="$T/hypr"; mkdir -p "$HY"; for o in animations:enabled decoration:blur:enabled decoration:shadow:enabled; do echo true > "$HY/$o"; done
echo false > "$HY/decoration:shadow:enabled"
stub dunstctl 'f="'"$T"'/dunst.paused"; case "$1" in is-paused) cat "$f" 2>/dev/null || echo false;; set-paused) echo "$2" > "$f"; echo "set-paused $2" >> "'"$T"'/dunst.log";; esac'
stub hyprctl 'd="'"$HY"'"; case "$1" in version) echo Hyprland;; getoption) echo "{\"option\": \"$3\", \"bool\": $(cat "$d/$3"), \"set\": false }";;
  eval) k="$(sed -E "s/^hl.config\(\{ ([a-z]+) = (\{ ([a-z]+) = )?(\{ ([a-z]+) = )?(true|false).*/\1:\3:\5 \6/" <<<"$2")"; v="${k##* }"; k="${k% *}"; k="${k%%:}"; k="${k%%:}"
        echo "$v" > "$d/$k"; echo "eval $k $v" >> "'"$T"'/hypr.log"; echo ok;; esac'
eq "status: both off, dunst and Hyprland found" "$("$CD" playing | jq -c '[.quiet, .lite, .notifier, .hyprland]')" '[false,false,"dunst",true]'
"$CD" playing quiet on >/dev/null; "$CD" playing lite on >/dev/null
eq "settings saved" "$("$CD" playing | jq -c '[.quiet, .lite]')" '[true,true]'
"$CD" playing loud on >/dev/null 2>&1; eq "unknown setting refused" "$?" 2
eq "gstatus carries them" "$(GAMING_DECK_GPU_VENDOR=intel "$CD" gstatus | jq -c '.playing | [.quiet, .lite]')" '[true,true]'
printf '#!/bin/sh\necho "$(dunstctl is-paused) $(cat %s/animations:enabled) $(cat %s/decoration:blur:enabled)" > %s/during\n' "$HY" "$HY" "$T" > "$T/fake/pgame"; chmod +x "$T/fake/pgame"
rm -f "$T/dunst.log" "$T/hypr.log"; SteamAppId=100 "$CD" run "$T/fake/pgame" >/dev/null 2>&1
eq "during the game: notifications paused, animations and blur off" "$(cat "$T/during")" "true false false"
eq "after: notifications back" "$(cat "$T/dunst.paused")" false
eq "after: animations and blur back" "$(cat "$HY/animations:enabled") $(cat "$HY/decoration:blur:enabled")" "true true"
yes "shadows were already off: never touched" "! grep -q shadow '$T/hypr.log'"
eq "Hyprland options set through eval (Lua config)" "$(head -1 "$T/hypr.log")" "eval animations:enabled false"
echo true > "$T/dunst.paused"; rm -f "$T/dunst.log"; SteamAppId=100 "$CD" run "$T/fake/okgame" >/dev/null 2>&1
yes "notifications you paused yourself stay paused" "[[ ! -s '$T/dunst.log' && \$(cat '$T/dunst.paused') == true ]]"
echo false > "$T/dunst.paused"; mkdir -p "$HOME/.local/share/gaming-deck/sessions"; echo steam:9 > "$HOME/.local/share/gaming-deck/sessions/999999"
rm -f "$T/dunst.log"; SteamAppId=100 "$CD" run "$T/fake/okgame" >/dev/null 2>&1
eq "a dead game's leftover marker doesn't keep things paused" "$(cat "$T/dunst.paused") $(paste -sd, "$T/dunst.log")" "false set-paused true,set-paused false"
eq "hook asks Umbral for a session when they're on" "$("$CD" hook umbral:x 2>/dev/null | jq .session)" true
"$CD" playing quiet off >/dev/null; "$CD" playing lite off >/dev/null
rm -f "$T/dunst.log" "$T/hypr.log"; SteamAppId=100 "$CD" run "$T/fake/okgame" >/dev/null 2>&1
yes "both off → nothing touched" "[[ ! -s '$T/dunst.log' && ! -s '$T/hypr.log' ]]"
rm -f "$T/bin/dunstctl" "$T/bin/hyprctl"
section "IO priority: does the game's disk honour it?"
eq "unknown game → nothing to say" "$("$CD" iosched steam:424242)" '{"disk":null,"scheduler":null,"levels":null}'
stub df 'printf "Filesystem\n/dev/fake1\n"'; stub lsblk 'printf "fake1 part\n└─fake disk\n"'
mkdir -p "$T/iosys/block/fake/queue"; UG2="$HOME/Games/umbral/games/io"; mkdir -p "$UG2"; head -c 10 /dev/zero > "$UG2/g.exe"
echo '{"prefixes":[],"games":[{"id":"io","name":"IO","kind":"custom","prefix_id":"x","exe":"'"$UG2"'/g.exe"}]}' > "$T/umbral-io.json"
echo 'none [mq-deadline] kyber bfq' > "$T/iosys/block/fake/queue/scheduler"
eq "mq-deadline: the level is ignored" "$(GAMING_DECK_SYSFS="$T/iosys" GAMING_DECK_UMBRAL_CONFIG="$T/umbral-io.json" "$CD" iosched umbral:io | jq -c '[.disk, .scheduler, .levels]')" '["fake","mq-deadline",false]'
echo 'none mq-deadline kyber [bfq]' > "$T/iosys/block/fake/queue/scheduler"
eq "BFQ: honoured" "$(GAMING_DECK_SYSFS="$T/iosys" GAMING_DECK_UMBRAL_CONFIG="$T/umbral-io.json" "$CD" iosched umbral:io | jq -c '[.scheduler, .levels]')" '["bfq",true]'
rm -f "$T/bin/df" "$T/bin/lsblk"
section "AMD: the dedicated GPU, not the CPU's integrated one"
G2="$T/sys2/class/drm"
mkgpu() {   # card vram busy temp(m°C) power(µW)
    mkdir -p "$G2/$1/device/hwmon/hwmon${1#card}"; echo 0x1002 > "$G2/$1/device/vendor"
    echo "$2" > "$G2/$1/device/mem_info_vram_total"; echo "$3" > "$G2/$1/device/gpu_busy_percent"; echo 100 > "$G2/$1/device/mem_info_vram_used"
    echo "$4" > "$G2/$1/device/hwmon/hwmon${1#card}/temp1_input"; echo edge > "$G2/$1/device/hwmon/hwmon${1#card}/temp1_label"; echo "$5" > "$G2/$1/device/hwmon/hwmon${1#card}/power1_average"
}
mkgpu card0 536870912 0 40000 1000000          # Ryzen iGPU listed first
mkgpu card1 17095983104 55 61000 250000000     # RX 9070 XT
eq "picks the card with the most VRAM" "$(GAMING_DECK_SYSFS="$T/sys2" fn amd_gpu_dev)" "$G2/card1/device"
eq "…its own temperature sensor" "$(GAMING_DECK_SYSFS="$T/sys2" fn amd_gpu_temp)" 61
eq "session samples read it: GPU °C, load, W" "$(GAMING_DECK_SYSFS="$T/sys2" GAMING_DECK_GPU_VENDOR=amd fn session_sample | awk '{print $3, $4, $5}')" "61 55 250"
section "TEST look (black and white)"
mkdir -p "$HOME/.local/share/gaming-deck/reshade/Shaders/SweetFX"; echo 'technique Monochrome {}' > "$HOME/.local/share/gaming-deck/reshade/Shaders/SweetFX/Monochrome.fx"
eq "vkBasalt: SweetFX Monochrome as a ReShade shader" "$(fn fx_builtin test /dev/stdout | grep -E '^(effects|monochrome) =' | paste -sd '|')" "effects = monochrome|monochrome = \"$HOME/.local/share/gaming-deck/reshade/Shaders/SweetFX/Monochrome.fx\""
eq "ReShade: the Monochrome technique" "$(fn reshade_builtin test /dev/stdout | head -1)" "Techniques=Monochrome@Monochrome.fx"
section "Community shader packs + CHECK FOR THIS PC (shaders, GameMode)"
FXD="$HOME/.local/share/gaming-deck/reshade"
mkdir -p "$T/xpk/Comm-main/Shaders" "$T/xpk/Comm-main/Textures"; echo 'technique Glow {}' > "$T/xpk/Comm-main/Shaders/Glow.fx"; echo x > "$T/xpk/Comm-main/Textures/glow.png"
( cd "$T/xpk" && bsdtar -a -cf "$T/xpk/comm.zip" Comm-main )
echo '[{"idx":"x-comm","default":false,"extra":true,"name":"Comm pack (community)","desc":"","url":"file://'"$T"'/xpk/comm.zip","repo":"","sub":"Comm","files":["Glow.fx"],"deny":[]}]' > "$T/fx-extra.json"
eq "community packs listed with the official ones" "$("$CD" fx packages | jq -c '.[] | select(.extra) | [.idx, .installed]')" '["x-comm",false]'
printf 'Techniques=Glow@Glow.fx\n' > "$T/glow.ini"
eq "a preset needing it installs it like an official pack" "$(fn reshade_need_files "$T/glow.ini" 2>/dev/null | jq -c '[.applied, .skipped]')" '[1,[]]'
yes "…into its own folder" "[[ -f '$FXD/Shaders/Comm/Glow.fx' && -f '$FXD/Textures/glow.png' ]]"
eq "…and marked installed" "$("$CD" fx packages | jq -r '.[] | select(.idx == "x-comm") | .installed')" true
# a look brought from another PC that uses a shader this one lacks
GD="$HOME/.local/share/gaming-deck/gaming/fx/steam_6100"; mkdir -p "$GD"
echo '{"source":"file","name":"Moved","mode":"reshade","applied":2,"effects":["Glow.fx","Nowhere.fx"],"skipped":[]}' > "$GD/report.json"
rm -rf "$FXD/Shaders/Comm"
GA="$(GAMING_DECK_GAMEMODE=1 "$CD" gaudit)"
eq "missing shader of a known pack → install it" "$(jq -c '[.issues[] | select(.key == "steam:6100" and .kind == "shader") | [.file, .fix, (.pack.idx // null)]]' <<<"$GA")" '[["Glow.fx","install","x-comm"],["Nowhere.fx","none",null]]'
GAMING_DECK_GAMEMODE=1 "$CD" gaudit fix steam:6100 >/dev/null 2>&1
yes "FIX installs the pack" "[[ -f '$FXD/Shaders/Comm/Glow.fx' ]]"
rm -rf "$GD"
# GameMode on in a profile, not installed here
"$CD" gprofile set steam:100 gamemode=true >/dev/null
eq "GameMode not installed → flagged for the profiles using it" "$(GAMING_DECK_GAMEMODE=0 "$CD" gaudit | jq -c '[.issues[] | select(.kind == "gamemode") | .key] | index("steam:100") != null')" true
eq "…installed → nothing to fix" "$(GAMING_DECK_GAMEMODE=1 "$CD" gaudit | jq '[.issues[] | select(.kind == "gamemode")] | length')" 0
eq "HEALTH: warns with the install command" "$(GAMING_DECK_GAMEMODE=0 "$CD" health | jq -c '.checks[] | select(.id == "tools:gamemode") | [.status, .fix]')" '["warn","sudo pacman -S --needed gamemode lib32-gamemode"]'
rm -f "$T/pkexec.log"; GAMING_DECK_GAMEMODE=0 "$CD" gaudit fix all >/dev/null 2>&1
has "FIX ALL installs it through pkexec pacman" "$(cat "$T/pkexec.log" 2>/dev/null)" "gamemode lib32-gamemode"
echo "[]" > "$T/fx-extra.json"
section "Preset review: what makes a preset look worse"
printf 'Techniques=Unsharp@Unsharp.fx,lilium__sdr_trc_fix@lilium__sdr_trc_fix.fx,ContrastAdaptiveSharpen@CAS.fx,Clarity@Clarity.fx,Clarity2@Clarity2.fx,Technicolor@Technicolor.fx,LevelsPlus@LevelsPlus.fx,Colors@pColors.fx,ColorMatrix@ColorMatrix.fx,FilmGrain@FilmGrain.fx\nTechniqueSorting=Unsharp@Unsharp.fx,CAS@CAS.fx\n\n[CAS.fx]\nContrast=0.000000\nSharpening=1.000000\n\n[Clarity.fx]\nClarityStrength=0.4\n' > "$T/heavy.ini"
RV="$(fn fx_review "$T/heavy.ini")"
eq "stacked sharpeners flagged, CAS kept" "$(jq -c '[.flags[] | select(.t | test("SHARPENERS")) | .off]' <<<"$RV")" '[["Unsharp.fx"]]'
eq "gamma tools, strong colour, film fx, CAS at 100 %" "$(jq -c '[.flags[].t]' <<<"$RV")" '["2 SHARPENERS","OVER-SHARP","SHARP 100 %","GAMMA","STRONG COLOUR","FILM FX","10 EFFECTS"]'
eq "LIGHTER switches off the culprits only" "$(jq -c .suggestOff <<<"$RV")" '["FilmGrain.fx","Unsharp.fx","lilium__sdr_trc_fix.fx"]'
eq "verdict" "$(jq -r .verdict <<<"$RV")" strong
printf 'Techniques=ContrastAdaptiveSharpen@CAS.fx,Clarity@Clarity.fx,Vibrance@Vibrance.fx\n\n[CAS.fx]\nSharpening=0.5\n' > "$T/light.ini"
eq "CAS + Clarity + one colour effect: light, nothing to switch off" "$(fn fx_review "$T/light.ini" | jq -c '[.verdict, .suggestOff]')" '["light",[]]'
# switching effects of a game's preset
FD="$HOME/.local/share/gaming-deck/reshade/Shaders/T"; mkdir -p "$FD"
for f in Unsharp lilium__sdr_trc_fix CAS Clarity Clarity2 Technicolor LevelsPlus pColors ColorMatrix FilmGrain; do echo "technique $f {}" > "$FD/$f.fx"; done
fn profile_write steam:6200 '{"fx":true,"fxMode":"reshade"}'
GD="$HOME/.local/share/gaming-deck/gaming/fx/steam_6200"; mkdir -p "$GD"; cp "$T/heavy.ini" "$GD/preset.ini"; tr -d '\r' < "$T/heavy.ini" > "$GD/ReShadePreset.ini"
echo '{"source":"sfx","id":"777","url":"https://sfx.example/777/","name":"Heavy one","mode":"reshade","applied":10,"effects":[],"skipped":[]}' > "$GD/report.json"
echo '{"key":"steam:6200","dir":"'"$T"'/g6200","api":"dxgi"}' > "$GD/reshade.json"; mkdir -p "$T/g6200"
"$CD" fx toggle steam:6200 FilmGrain.fx off >/dev/null 2>&1
eq "toggle off: gone from the applied preset" "$(grep -c 'FilmGrain' "$GD/ReShadePreset.ini")" 0
yes "…the original kept" "grep -q FilmGrain '$GD/preset.orig.ini'"
eq "…report keeps the SweetFX source and lists what's off" "$(jq -c '[.source, .id, .name, .disabled]' "$GD/report.json")" '["sfx","777","Heavy one",["FilmGrain.fx"]]'
"$CD" fx lighter steam:6200 >/dev/null 2>&1
eq "LIGHTER: the flagged ones off too" "$(jq -c .disabled "$GD/report.json")" '["FilmGrain.fx","Unsharp.fx","lilium__sdr_trc_fix.fx"]'
"$CD" fx toggle steam:6200 Unsharp.fx on >/dev/null 2>&1
eq "toggle on: back in the applied preset" "$(grep -m1 '^Techniques=' "$GD/ReShadePreset.ini" | grep -c Unsharp)" 1
"$CD" fx set steam:6200 builtin:sharpen >/dev/null 2>&1
yes "another look clears the switches" "[[ ! -e '$GD/preset.orig.ini' && ! -e '$GD/disabled.json' ]]"
"$CD" fx toggle steam:6200 'x/../y.fx' off >/dev/null 2>&1; eq "bad file name refused" "$?" 2
rm -rf "$GD" "$FD"
section "ReShade screenshot key"
eq "PrtSc by default" "$("$CD" fx status | jq -r .shotKey)" PrtSc
"$CD" fx shotkey F10 >/dev/null; eq "changed and kept" "$("$CD" fx status | jq -c '[.shotKey, .key, .effectsKey]')" "[\"F10\",$("$CD" fx status | jq -c .key),$("$CD" fx status | jq -c .effectsKey)]"
"$CD" fx shotkey Home >/dev/null 2>&1; eq "only the offered keys" "$?" 2
"$CD" fx shotkey "$("$CD" fx status | jq -r .effectsKey)" >/dev/null 2>&1; eq "not the on/off key" "$?" 2
"$CD" fx key F11 >/dev/null; eq "changing the menu key keeps the screenshot key" "$("$CD" fx status | jq -r .shotKey)" F10
"$CD" fx shotkey PrtSc >/dev/null
section "Migration from Control Deck"
OLD="$T/old-cd"; NEW="$HOME/.local/share/gaming-deck"; GM="$T/mgame"; MS="$T/msteam"
mkdir -p "$OLD/gaming/fx/steam_9100" "$OLD/reshade/bin/current" "$OLD/sessions" "$OLD/logs" "$GM" "$MS/userdata/7/config"
echo dll > "$OLD/reshade/bin/current/ReShade64.dll"; echo '{"steam:9100":{"gamemode":true}}' > "$OLD/gaming/profiles.json"
OW="Z:${OLD//\//\\}"
printf '[GENERAL]\nEffectSearchPaths=%s\\reshade\\Shaders\\**\nPresetPath=%s\\gaming\\fx\\steam_9100\\ReShadePreset.ini\n' "$OW" "$OW" > "$GM/ReShade.ini"
ln -s "$OLD/reshade/bin/current/ReShade64.dll" "$GM/dxgi.dll"
echo '{"key":"steam:9100","dir":"'"$GM"'","api":"dxgi"}' > "$OLD/gaming/fx/steam_9100/reshade.json"
printf 'reshadeIncludePath = "%s/reshade/Shaders"\n' "$OLD" > "$OLD/gaming/fx/steam_9100/vkBasalt.conf"
printf '2026-10-01 10:00:00\tinstall\trepo\tfoo\tok\n2026-10-01 11:00:00\tplay\tsteam\tsteam:9100\tok\n' > "$OLD/history.tsv"
printf '"UserLocalConfigStore"\n{\n\t"Software"\n\t{\n\t\t"Valve"\n\t\t{\n\t\t\t"Steam"\n\t\t\t{\n\t\t\t\t"apps"\n\t\t\t\t{\n\t\t\t\t\t"9100"\n\t\t\t\t\t{\n\t\t\t\t\t\t"LaunchOptions"\t\t"%s/.local/bin/control-deck run %%command%%"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n' "$HOME" > "$MS/userdata/7/config/localconfig.vdf"
mig() { GAMING_DECK_OLD_DATA="$OLD" GAMING_DECK_STEAM_ROOT="$MS" "$@"; }
mv "$NEW/gaming" "$NEW/gaming.keep" 2>/dev/null; mv "$NEW/reshade" "$NEW/reshade.keep" 2>/dev/null; mv "$NEW/history.tsv" "$NEW/history.keep" 2>/dev/null
mkdir -p "$NEW/gaming"; echo steam:1 > "$NEW/gaming/known-games.txt"; echo steam:9100 > "$OLD/gaming/known-games.txt"  # Gaming Deck opened before migrating
GAMING_DECK_STEAM_RUNNING=1 mig "$CD" migrate >/dev/null 2>&1; eq "Steam open: data moved, launch options left for later (3)" "$?" 3
yes "…game data now in Gaming Deck's folder" "[[ -f '$NEW/gaming/profiles.json' && ! -e '$OLD/gaming' ]]"
eq "…merged into the folder Gaming Deck had already made" "$(paste -sd , "$NEW/gaming/known-games.txt")" "steam:1,steam:9100"
eq "ReShade.ini paths point to the new folder" "$(grep -c 'gaming-deck' "$GM/ReShade.ini")" 2
eq "…DLL links too" "$(readlink "$GM/dxgi.dll")" "$NEW/reshade/bin/current/ReShade64.dll"
has "vkBasalt config fixed" "$(cat "$NEW/gaming/fx/steam_9100/vkBasalt.conf")" "$NEW/reshade/Shaders"
eq "history: only the game lines come over" "$(cut -f2 "$NEW/history.tsv" | paste -sd ,)" play
has "Steam's launch options untouched while it runs" "$(cat "$MS/userdata/7/config/localconfig.vdf")" "control-deck run"
GAMING_DECK_STEAM_RUNNING=0 mig "$CD" migrate >/dev/null 2>&1; eq "Steam closed: finishes" "$?" 0
has "…launch options call Gaming Deck" "$(cat "$MS/userdata/7/config/localconfig.vdf")" "$HOME/.local/bin/gaming-deck run %command%"
yes "…backup of Steam's file kept" "grep -q 'control-deck run' '$MS/userdata/7/config/localconfig.vdf.gaming-deck.bak'"
eq "running it again changes nothing" "$(GAMING_DECK_STEAM_RUNNING=0 mig "$CD" migrate 2>&1)" "✔ Nothing to migrate."
rm -rf "$NEW/gaming" "$NEW/reshade" "$NEW/history.tsv"
mv "$NEW/gaming.keep" "$NEW/gaming" 2>/dev/null; mv "$NEW/reshade.keep" "$NEW/reshade" 2>/dev/null; mv "$NEW/history.keep" "$NEW/history.tsv" 2>/dev/null
section "Interface language (ESP/ENG)"
rm -f "$HOME/.local/share/gaming-deck/ui.json"
eq "default follows the locale (es_ES)" "$(LC_ALL='' LC_MESSAGES='' LANG=es_ES.UTF-8 "$CD" uilang)" es
eq "default follows the locale (en_US)" "$(LC_ALL='' LC_MESSAGES='' LANG=en_US.UTF-8 "$CD" uilang)" en
"$CD" uilang es >/dev/null
eq "saved choice wins over the locale" "$(LANG=en_US.UTF-8 "$CD" uilang)" es
"$CD" uilang fr >/dev/null 2>&1; eq "unknown language refused" "$?" 2
eq "…and the saved one is kept" "$("$CD" uilang)" es
# --------------------------------------------------------- in-game panel ----
section "in-game panel: achievements, wiki, guides, notes, key"
PS="$T/psteam"; mkdir -p "$PS/config" "$PS/appcache/stats" "$PS/steamapps"
export GAMING_DECK_STEAM_ROOT="$PS" GAMING_DECK_STEAM_RUNNING=0
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' "$PS" > "$PS/steamapps/libraryfolders.vdf"
printf '"AppState"\n{\n\t"appid"\t\t"700"\n\t"name"\t\t"Kingdom Come: Deliverance II"\n\t"installdir"\t\t"KCD2"\n\t"SizeOnDisk"\t\t"1"\n}\n' > "$PS/steamapps/appmanifest_700.acf"
# two accounts, no MostRecent: the one that signed in last
printf '"users"\n{\n\t"76561197960265738"\n\t{\n\t\t"Timestamp"\t\t"100"\n\t}\n\t"76561197960265748"\n\t{\n\t\t"Timestamp"\t\t"200"\n\t}\n}\n' > "$PS/config/loginusers.vdf"
eq "Steam account: the newest sign-in when there's no MostRecent" "$(fn steam_account)" 20
sed -i '0,/"Timestamp"\t\t"100"/s//"Timestamp"\t\t"100"\n\t\t"MostRecent"\t\t"1"/' "$PS/config/loginusers.vdf"
eq "…MostRecent wins" "$(fn steam_account)" 10
# Steam's binary KeyValues: a schema with 3 achievements over two blocks, and the user's bits
python3 - "$PS/appcache/stats" <<'PY'
import struct, sys
def ser(d):
    o = b''
    for k, v in d.items():
        kb = k.encode() + b'\0'
        if isinstance(v, dict): o += b'\0' + kb + ser(v) + b'\x08'
        elif isinstance(v, str): o += b'\x01' + kb + v.encode() + b'\0'
        else: o += b'\x02' + kb + struct.pack('<i', v)
    return o
def ach(n, en, es, hidden=0):
    return {'name': n, 'display': {'name': {'english': en, 'spanish': es}, 'desc': {'english': en + ' desc', 'spanish': es + ' desc'},
            'hidden': str(hidden), 'icon': n + '.jpg', 'icon_gray': n + '_g.jpg'}}
schema = {'700': {'gamename': 'KCD2', 'stats': {
    '1': {'type': 'ACHIEVEMENTS', 'bits': {'0': ach('A0', 'First', 'Primero'), '31': ach('A31', 'Top bit', 'Bit alto')}},
    '2': {'type': 'ACHIEVEMENTS', 'bits': {'6': ach('B6', 'Secret', 'Secreto', 1)}},
    '3': {'type': 'INT', 'name': 'kills'}}}}
open(sys.argv[1] + '/UserGameStatsSchema_700.bin', 'wb').write(ser(schema) + b'\x08')
# bit 31 set: a negative int32 on disk
user = {'cache': {'crc': 1, '1': {'data': -2147483647, 'AchievementTimes': {'0': 1700000000, '31': 1700000100}}, '2': {'data': 0}}}
open(sys.argv[1] + '/UserGameStats_10_700.bin', 'wb').write(ser(user) + b'\x08')
PY
mkdir -p "$HOME/.cache/gaming-deck/ach"
echo '{"achievementpercentages":{"achievements":[{"name":"B6","percent":"12.5"},{"name":"A0","percent":"80.0"}]}}' > "$HOME/.cache/gaming-deck/ach/700-global.json"
"$CD" uilang en >/dev/null
A="$("$CD" ach 700)"
eq "achievements counted over every block (bit 31 included)" "$(jq -c '[.total, .unlocked, .percent]' <<<"$A")" "[3,2,66.7]"
eq "names, unlock times, hidden flag" "$(jq -c '[.items[] | [.id, .name, .unlocked, .time, .hidden]]' <<<"$A")" \
   '[["A0","First",true,1700000000,false],["A31","Top bit",true,1700000100,false],["B6","Secret",false,0,true]]'
eq "global rarity from the cached public percentages" "$(jq -c '[.hasRarity, (.items[] | .rarity)]' <<<"$A")" "[true,80.0,null,12.5]"
eq "colour icon when unlocked, grey one when not" "$(jq -r '[.items[0].icon, .items[2].icon] | map(split("/") | last) | join(" ")' <<<"$A")" "A0.jpg B6_g.jpg"
eq "the account's stats file is the one watched for new unlocks" "$(jq -r .statsFile <<<"$A")" "$PS/appcache/stats/UserGameStats_10_700.bin"
"$CD" uilang es >/dev/null
eq "Spanish names with the deck in Spanish (English kept for the wiki)" "$("$CD" ach 700 | jq -c '.items[0] | [.name, .nameEn, .desc]')" '["Primero","First","Primero desc"]'
"$CD" uilang en >/dev/null
eq "a game Steam has no achievements for" "$("$CD" ach 701 | jq -r .error)" noschema
"$CD" ach x >/dev/null 2>&1; eq "ach wants an appid" "$?" 2
# the game being played
mkdir -p "$T/pproc/5100" "$T/pproc/5200"
printf 'SteamAppId=700\0' > "$T/pproc/5100/environ"; printf 'SteamAppId=0\0' > "$T/pproc/5200/environ"
eq "ingame: the running Steam game, with its name" "$(PROC_ROOT="$T/pproc" "$CD" ingame | jq -c '[.appid, .name, .pid]')" '["700","Kingdom Come: Deliverance II",5100]'
mkdir -p "$T/pproc0"; eq "ingame: nothing running" "$(PROC_ROOT="$T/pproc0" "$CD" ingame)" "{}"
# wiki: which Fandom wiki fits the game
eq "wiki candidates: the full name first, sequel number dropped" "$(fn wiki_candidates "Kingdom Come: Deliverance II" | head -2 | paste -sd ' ')" "kingdomcomedeliverance kingdom-come-deliverance"
has "…and the subtitle alone (Khazan)" "$(fn wiki_candidates "The First Berserker: Khazan")" khazan
eq "a sequel fits its series' wiki" "$(fn wiki_score "Kingdom Come: Deliverance II" "Kingdom Come: Deliverance Wiki")" 100
yes "another game of the series doesn't" "(( $(fn wiki_score "Tainted Grail: The Fall of Avalon" "Tainted Grail: Conquest Wiki") < 60 ))"
"$CD" wiki 700 set https://evil.example.com >/dev/null 2>&1; eq "only Fandom wiki addresses" "$?" 2
"$CD" wiki 700 set https://kingdom-come-deliverance.fandom.com/ >/dev/null
eq "a wiki set by hand" "$("$CD" wiki 700 | jq -r .base)" "https://kingdom-come-deliverance.fandom.com"
G="$("$CD" guides 700)"
eq "guide links: EliteGuías (game, achievements), Map Genie, Steam, the wiki" "$(jq -r 'map(.label + ":" + .sub) | join(",")' <<<"$G")" \
   "EliteGuías:guide,EliteGuías:achievements,Map Genie:interactive map,Steam:community guides,Steam:global achievements,Wiki:kingdom-come-deliverance.fandom.com"
eq "Map Genie: the game's page by name, its game list when there's none" "$(jq -c '.[] | select(.label == "Map Genie") | [.url, .fallback]' <<<"$G")" \
   '["https://mapgenie.io/kingdom-come-deliverance-2","https://mapgenie.io/"]'
eq "EliteGuías: straight to the game's guide (its address worked out from the name)" "$(jq -r '.[0].url' <<<"$G")" "https://www.eliteguias.com/guias/k/kcd2/kingdom-come-deliverance-2.php"
eq "…its search if there's none" "$(jq -r '.[0].fallback' <<<"$G")" "https://www.eliteguias.com/buscar.php?q=Kingdom%20Come%3A%20Deliverance%20II"
eq "…and its achievements page" "$(jq -r '.[1].url' <<<"$G")" "https://www.eliteguias.com/trucos/k/kingdom-come-deliverance-2.php"
eq "EliteGuías names: subtitle words count" "$(fn eg_slug "Tainted Grail: The Fall of Avalon")" "tainted-grail-the-fall-of-avalon tgtfoa"
eq "…symbols and case" "$(fn eg_slug "BALL x PIT™")" "ball-x-pit bxp"
eq "Steam guides of this game" "$(jq -r '.[] | select(.sub == "community guides") | .url' <<<"$G")" "https://steamcommunity.com/app/700/guides/"
"$CD" wiki 700 clear; GAMING_DECK_FANDOM_FMT="file://$T/nofandom/%s" "$CD" wiki 700 >/dev/null
eq "no wiki found: remembered (not looked up on every open)" "$(jq -r '."700".base' "$HOME/.local/share/gaming-deck/gaming/wiki.json")" ""
eq "…and no wiki link" "$("$CD" guides 700 | jq -r 'map(select(.label == "Wiki")) | length')" 0
eq "no wiki: empty search" "$("$CD" wiki 700 search Henry)" "[]"
cat > "$T/wikipage.json" <<'WJ'
{"parse":{"title":"Henry","text":{"*":"<aside class=\"portable-infobox\"><h2>Henry</h2><div>Age 20</div></aside><p>Henry is the <b>hero</b>.<img src=\"x.png\"/></p><table><tr><td>stats</td></tr></table><h2><span>Story</span><span class=\"mw-editsection\">edit</span></h2><ul><li>Skalitz</li><li>Rattay<sup class=\"reference\">[1]</sup></li></ul>"}}}
WJ
W="$(fn wiki_text https://kcd.fandom.com "KCD Wiki" < "$T/wikipage.json")"
eq "wiki page → readable text (no infobox, tables, edit links or references)" "$(jq -r .text <<<"$W")" "$(printf 'Henry is the hero.\n\n§ Story\n\n• Skalitz\n• Rattay')"
eq "…with its address and licence" "$(jq -c '[.url, .source, .license]' <<<"$W")" '["https://kcd.fandom.com/wiki/Henry","KCD Wiki","CC BY-SA 3.0"]'
# OVERLAY's list: achievements, wiki and anti-cheat per installed game
mkdir -p "$PS/steamapps/common/KCD2/Game/EasyAntiCheat"
mkdir -p "$HOME/.cache/gaming-deck/fx"; echo '[]' > "$HOME/.cache/gaming-deck/fx/awacy.json"; echo '{}' > "$HOME/.cache/gaming-deck/fx/store-700.json"
eq "ovgames: each game with achievements, wiki and the anti-cheat its folder ships" \
   "$("$CD" ovgames | jq -c '.[] | [.appid, .ach.unlocked, .ach.total, (.wiki | has("base")), .anticheats]')" '["700",2,3,false,["Easy Anti-Cheat"]]'
eq "no anti-cheat folder: none" "$(fn game_ac_files "$T/nowhere")" "[]"
# Fextralife (souls-likes, a fixed list) with a search address; the deck's language without ui.json
eq "Fextralife for a souls-like, with its search" "$(fn cmd_guides 1245620 | jq -r '.[] | select(.label == "Fextralife") | .search')" \
   "https://eldenring.wiki.fextralife.com/Special:Search?search="
eq "…none for other games" "$("$CD" guides 700 | jq '[.[] | select(.label == "Fextralife")] | length')" 0
mv "$HOME/.local/share/gaming-deck/ui.json" "$T/ui.json.keep"
eq "language: a game's LC_ALL=C doesn't hide the system's Spanish" "$(LC_ALL=C LC_MESSAGES= LANG=es_ES.UTF-8 "$CD" uilang)" es
eq "…English otherwise" "$(LC_ALL=C LC_MESSAGES= LANG=en_GB.UTF-8 "$CD" uilang)" en
mv "$T/ui.json.keep" "$HOME/.local/share/gaming-deck/ui.json"
# the guide browser over the game
"$CD" web open "http://x.example" >/dev/null 2>&1; eq "web: https only" "$?" 2
eq "web close with none open" "$("$CD" web close; echo $?)" 0
# the key with a guide open: hide it / show it again as it was (SIGUSR1 to the browser), panel left closed
stub qs 'echo "qs $*" >> "'"$T"'/qsweb.log"'
( trap '' USR1 USR2; exec sleep 300 ) & WEBP2=$!; echo "$WEBP2" > "$T/web.pid"; echo '{"visible":true,"slots":[{"slot":"Map Genie · mapa"}]}' > "$T/web.state"
GAMING_DECK_PANEL_QML="$T/panel.qml" "$CD" panel >/dev/null 2>&1; eq "the key with a guide open: no new panel" "$(grep -c '^qs -n' "$T/qsweb.log" 2>/dev/null)" 0
has "…the panel told to close instead" "$(cat "$T/qsweb.log" 2>/dev/null)" "call panel close"
yes "…the guide is kept (hidden, not closed)" "kill -0 $WEBP2"
eq "…and remembers it was the guide that was on screen" "$(cat "$T/web.last")" web
has "a guide request goes to the running browser (its own tab)" "$("$CD" web open https://mapgenie.io/x --slot "Map Genie · mapa" --reuse; cat "$T/web.ctl")" '{"cmd":"open","slot":"Map Genie · mapa","url":"https://mapgenie.io/x","fallback":"","reuse":true}'
eq "web state: the open tabs" "$("$CD" web state | jq -r '.slots[0].slot')" "Map Genie · mapa"
kill "$WEBP2" 2>/dev/null; rm -f "$T/web.pid" "$T/web.state" "$T/web.ctl" "$T/web.last" "$T/qsweb.log"
eq "web state with no browser: nothing open" "$("$CD" web state)" '{"visible":false,"slots":[]}'
bash -c 'source "$1"; web_helper() { :; }; cmd_web https://example.org/' _ "$CD" >/dev/null 2>&1
eq "no WebKit / layer-shell: the guide goes to the browser instead" "$?" 0
# notes
"$CD" notes 700 set "$(printf 'línea 1\n[19:42] jefe')"
eq "notes are kept as written" "$("$CD" notes 700)" "$(printf 'línea 1\n[19:42] jefe')"
eq "no notes yet: empty" "$("$CD" notes 701)" ""
"$CD" gopen "file:///etc/passwd" >/dev/null 2>&1; eq "gopen: https and steam:// only" "$?" 2
# the activation key in Hyprland's config
HYD="$T/hypr"; mkdir -p "$HYD"; printf 'hl.bind("SUPER + I", hl.dsp.exec_cmd("x"))\n' > "$HYD/hyprland.lua"
stub hyprctl 'case "$1" in binds) cat "'"$T"'/binds.json" 2>/dev/null || echo "[]" ;; *) exit 0 ;; esac'
export GAMING_DECK_HYPR_DIR="$HYD"
"$CD" panel key F6 >/dev/null; "$CD" panel key F6 >/dev/null
eq "key written once in hyprland.lua, however many times it's set" "$(grep -c 'hl.bind("F6", hl.dsp.exec_cmd(".* panel")' "$HYD/hyprland.lua")" 1
has "…next to the user's own binds, which stay" "$(cat "$HYD/hyprland.lua")" 'hl.bind("SUPER + I"'
yes "…and the config was backed up first" "[[ -f '$HYD/hyprland.lua.gaming-deck.bak' ]]"
"$CD" panel key "SUPER + G" >/dev/null
eq "changing the key replaces it" "$(grep -c 'gaming-deck: \|hl.bind("SUPER + G", hl.dsp.exec_cmd(".* panel")\|"F6"' "$HYD/hyprland.lua")" 1
echo '[{"modmask":0,"key":"F7","dispatcher":"exec","arg":"obs-toggle"},{"modmask":64,"key":"G","dispatcher":"__lua","arg":"238","description":"Gaming Deck: in-game panel"}]' > "$T/binds.json"
"$CD" panel key "SUPER + G" >/dev/null 2>&1; eq "our own bind (Lua: only its description tells) isn't a conflict" "$?" 0
"$CD" panel key F7 >/dev/null 2>&1; eq "a key Hyprland already uses is refused" "$?" 3
"$CD" panel key 'F6"); os.exit(' >/dev/null 2>&1; eq "only key names (nothing that breaks out of the Lua string)" "$?" 2
"$CD" panel key off >/dev/null
eq "key off: the user's config is as it was" "$(cat "$HYD/hyprland.lua")" 'hl.bind("SUPER + I", hl.dsp.exec_cmd("x"))'
rm -f "$HYD/hyprland.lua"*; printf 'bind = SUPER, I, exec, x\n' > "$HYD/hyprland.conf"
"$CD" panel key "SUPER + SHIFT + P" >/dev/null
has "hyprland.conf (no Lua): a classic bind line" "$(cat "$HYD/hyprland.conf")" "bind = SUPER SHIFT, P, exec, "
unset GAMING_DECK_HYPR_DIR
# run starts the panel hidden, to pop up achievements unlocked while playing
stub qs 'case "$1" in ipc) exit 1 ;; esac; echo "qs $* show=$CD_PANEL_SHOW appid=${SteamAppId:-none}" >> "'"$T"'/qs.log"'
touch "$T/panel.qml"; export GAMING_DECK_PANEL_QML="$T/panel.qml"
rm -f "$T/qs.log"; SteamAppId=700 "$CD" run "$T/fake/ogame" >/dev/null
for _ in $(seq 25); do [[ -s "$T/qs.log" ]] && break; sleep 0.2; done
has "run starts the panel hidden" "$(cat "$T/qs.log")" "qs -n -p $T/panel.qml show=0 appid=none"  # (the game's SteamAppId stays out of it: it would pass for the game)
rm -f "$T/qs.log"; "$CD" panel >/dev/null
for _ in $(seq 25); do [[ -s "$T/qs.log" ]] && break; sleep 0.2; done
has "the key opens it (shown) when it isn't running" "$(cat "$T/qs.log")" "show=1"
"$CD" panel toast off >/dev/null; sleep 0.3; rm -f "$T/qs.log"; SteamAppId=700 "$CD" run "$T/fake/ogame" >/dev/null; sleep 0.5
yes "pop-ups off: run leaves it alone" "[[ ! -e '$T/qs.log' ]]"
eq "panel status" "$("$CD" panel status | jq -c '[.key, .toast, .installed, .running]')" '["SUPER + SHIFT + P",false,true,false]'
export GAMING_DECK_PANEL_QML="$T/no-panel.qml"; unset GAMING_DECK_STEAM_ROOT GAMING_DECK_STEAM_RUNNING
# every key of es.js must still be a string of the GUI or the backend, or it is dead
src="$(cat "$ROOT/quickshell/shell.qml" "$CD")"; src="${src//\'\"\'\"\'/\'}"
dead=0
while IFS= read -r k; do [[ "$src" == *"$k"* ]] || { dead=$((dead + 1)); echo "    dead key: $k"; }
done < <(sed -n 's/^    "\(\([^"\\]\|\\.\)*\)": .*/\1/p' "$ROOT/quickshell/es.js")
eq "no dead Spanish keys" "$dead" 0
if (( $(grep -c '^    "' "$ROOT/quickshell/es.js") > 600 )); then ok "es.js has the keys"; else bad "es.js has the keys" "fewer than 600"; fi
# every win.X / pal.X the GUI uses is defined (a split or a prune can drop one; QML only notices at run time)
undef="$(python3 - "$ROOT/quickshell/shell.qml" <<'PY2'
import re, sys
t = open(sys.argv[1]).read()
have = set(re.findall(r'property\s+(?:\w+\s+)?\w+\s+(\w+)', t)) | set(re.findall(r'function\s+(\w+)', t)) | set(re.findall(r'\bid:\s*(\w+)', t))
have |= {"visible", "width", "height", "color", "screen", "title", "implicitWidth", "implicitHeight", "contentItem"}
# processes and timers are reached by id (fooProc.running = true): those ids must exist too
procs = set(re.findall(r'\b([a-z]\w*)\.(?:running|command|start\(|restart\(|stop\()', t))
procs -= {x.strip() for ps in re.findall(r'function\s*\w*\s*\(([^)]*)\)', t) for x in ps.split(",")}
print(" ".join(sorted((set(re.findall(r'\bwin\.(\w+)', t)) | set(re.findall(r'\bpal\.(\w+)', t)) | procs) - have)))
PY2
)"
eq "the GUI uses nothing undefined" "$undef" ""
# ==========================================================================
printf '\n\e[1m%d passed, %d failed\e[0m\n' "$pass" "$failed"
[[ $failed -eq 0 ]]
