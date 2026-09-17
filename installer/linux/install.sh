#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  ZShare -- install, or remove, for every game and every route.
#
#      ./install.sh                show what it will do, ask once, copy
#      ./install.sh --yes          copy without asking
#      ./install.sh --game t6,t7   only these games, from a download with several
#      ./install.sh --to <folder>  use this game folder, when it is not found
#      ./install.sh --uninstall    remove what an install put there
#      ./install.sh --find         show what it detects, change nothing
#
#  The Linux twin of install.ps1, and the two do the same thing. One
#  installer for every download: a single game's, or the Treyarch Bundle,
#  which carries all five. It maps each folder in the download to the place
#  its game reads it from:
#
#      Plutonium/storage/t6   Black Ops II -- the loose scripts and the mod
#      Plutonium/storage/t5   Black Ops
#      Plutonium/storage/t4   World at War
#      Black Ops III          BOIII's and Ezz BOIII's own custom_scripts
#      AppData                BOIII per user -- not Ezz BOIII, which clears
#                             it every time it launches
#      t7x                    T7x, which reads the compiled script
#      zshare                 Black Ops 4, as a Shield mod folder
#
#  A download carrying more than one game asks which of them to install,
#  offering every one it finds on this machine; --game answers that without
#  asking, and --yes takes every game found.
#
#  A route installs only when the client it is for is there. Each names its
#  anchors -- a folder or an exe, any one of which has to exist already --
#  and the installer creates what is missing below the root and nothing
#  above it.
#
#  Black Ops III can be several folders, one per client: "... BOIII",
#  "... EzzBOIII", "... T7x" beside the plain one. A copy whose client folder
#  links back into the plain folder is already covered by it; a copy with a
#  client folder of its own gets that client's route again, aimed at it.
#
#  Plutonium and the Black Ops III clients are Windows programs, so on Linux
#  they live inside a Wine or Proton prefix: DeckOps' compatdata prefix on any
#  Steam library, Heroic, Lutris, Bottles, plain ~/.wine, and the Flatpak
#  build of each.
#
#  The t7-compiler project and the Steam Workshop version are left alone, as
#  on Windows. Nothing leaves this machine, and uninstalling removes files
#  only -- never a folder.
# ---------------------------------------------------------------------------
set -u

YES=0
UNINSTALL=0
FIND=0
GAME_ARG=""
TO_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y|-Yes)             YES=1 ;;
        --uninstall|-Uninstall)    UNINSTALL=1 ;;
        --find|-Find)              FIND=1 ;;
        --game=*)                  GAME_ARG="${1#--game=}" ;;
        --game|-Game)              shift; GAME_ARG="${1:-}" ;;
        --to=*)                    TO_ARG="${1#--to=}" ;;
        --to|-To)                  shift; TO_ARG="${1:-}" ;;
    esac
    [ $# -gt 0 ] && shift
done
TO_ARG="${TO_ARG%/}"

say() { printf '  %s\n' "$*"; }

# ------------------------------------------------------------- the download

# The download root is wherever zshare.release is. From a download the
# installer sits two folders down, under installer/linux/.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD=""
d="$HERE"
for _ in 1 2 3 4; do
    if [ -f "$d/zshare.release" ]; then DOWNLOAD="$d"; break; fi
    d="$(dirname "$d")"
done

printf '\n  ZShare\n  ------\n'

if [ -z "$DOWNLOAD" ]; then
    printf '\n'
    say "This is not a ZShare download: there is no zshare.release beside it."
    say "Extract the whole download and run the installer from inside it."
    exit 1
fi

rel() { sed -n "s/^$1=//p" "$DOWNLOAD/zshare.release" | head -n1; }
say "$(rel name) v$(rel version)"

# ------------------------------------------------------------- finding games

LIBS=()
add_lib() {
    [ -n "${1:-}" ] && [ -d "$1/steamapps" ] || return 0
    local l
    for l in "${LIBS[@]-}"; do [ "$l" = "$1" ] && return 0; done
    LIBS+=("$1")
}
find_libs() {
    local ROOTS=(
        "$HOME/.steam/steam" "$HOME/.steam/root" "$HOME/.local/share/Steam"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    )
    local m r vdf lib
    # SteamOS mounts removable storage differently depending on its age.
    for m in /run/media/mmcblk0p1 /run/media/deck/* /run/media/*; do
        [ -d "$m/steamapps" ] && ROOTS+=("$m")
    done
    for r in "${ROOTS[@]}"; do
        add_lib "$r"
        vdf="$r/steamapps/libraryfolders.vdf"
        if [ -f "$vdf" ]; then
            while IFS= read -r lib; do add_lib "$lib"; done \
                < <(grep -oE '"path"[[:space:]]+"[^"]+"' "$vdf" 2>/dev/null |
                    sed -E 's/.*"path"[[:space:]]+"([^"]+)".*/\1/')
        fi
    done
}
find_libs

# What a folder has to hold to be that game's. Any one will do: a Black Ops
# III folder may carry only boiii.exe or t7x.exe when it is a client-only
# install, and Plutonium is the folder with storage in it.
is_root() {  # is_root <family> <path>
    [ -n "${2:-}" ] || return 1
    case "$1" in
        pluto) [ -d "$2/storage" ] ;;
        bo3)   [ -f "$2/BlackOps3.exe" ] || [ -f "$2/boiii.exe" ] || [ -f "$2/t7x.exe" ] ;;
        bo4)   [ -f "$2/BlackOps4.exe" ] ;;
        *)     return 1 ;;
    esac
}

# The first Plutonium folder inside any prefix, or outside one.
find_pluto() {
    local root pfx
    local PREFIXES=()
    for l in "${LIBS[@]-}"; do PREFIXES+=("$l/steamapps/compatdata"); done
    PREFIXES+=(
        "$HOME/Games/Heroic/Prefixes"
        "$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/Prefixes"
        "$HOME/Games"
        "$HOME/.local/share/lutris/prefixes"
        "$HOME/.var/app/net.lutris.Lutris/data/lutris/prefixes"
        "$HOME/.local/share/bottles/bottles"
        "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles"
        "$HOME/.wine"
        "$HOME/.local/share/wineprefixes"
    )
    for root in "${PREFIXES[@]}"; do
        [ -d "$root" ] || continue
        for pfx in "$root"/*/pfx/drive_c/users/*/AppData/Local/Plutonium \
                   "$root"/*/drive_c/users/*/AppData/Local/Plutonium \
                   "$root"/drive_c/users/*/AppData/Local/Plutonium; do
            is_root pluto "$pfx" && { printf '%s' "$pfx"; return; }
        done
    done
    for pfx in "$HOME/.local/share/Plutonium" "$HOME/Plutonium"; do
        is_root pluto "$pfx" && { printf '%s' "$pfx"; return; }
    done
}

# The game folder, by what it holds. Several can match -- a folder per
# client beside the plainly named one -- so the shortest name wins, because
# a per-client copy only ever adds a suffix; copies with a client folder of
# their own are found again by client_copies. The mod tools (455130) are
# not a game.
find_game() {  # find_game <family> <glob>
    local family="$1" pattern="$2" best="" l d
    local CANDS=()
    # The pattern is left unquoted so it globs, and "*Black Ops III*" has
    # spaces in it: split on them, it was three patterns that matched
    # nothing, and Black Ops III was never found at all.
    local IFS=$'\n'
    for l in "${LIBS[@]-}"; do
        for d in "$l/steamapps/common"/$pattern; do CANDS+=("$d"); done
    done
    for d in "$HOME/Games"/$pattern "$HOME/Games/COD"/$pattern "$HOME/Games/Call of Duty"/$pattern \
             "$HOME"/$pattern /opt/games/$pattern /games/$pattern; do
        CANDS+=("$d")
    done
    for d in "${CANDS[@]-}"; do
        is_root "$family" "$d" || continue
        case "$d" in *455130*) continue ;; esac
        if [ -z "$best" ] || [ "${#d}" -lt "${#best}" ]; then best="$d"; fi
    done
    printf '%s' "$best"
}

# Black Ops III's AppData lives in its own Proton prefix, app 311210.
find_appdata() {
    local l pfx h
    for l in "${LIBS[@]-}"; do
        pfx="$l/steamapps/compatdata/311210/pfx/drive_c/users/steamuser/AppData/Local"
        [ -d "$pfx" ] && { printf '%s' "$pfx"; return; }
    done
    for h in "$HOME/Games/Heroic/Prefixes"/*/drive_c/users/*/AppData/Local \
             "$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic/Prefixes"/*/drive_c/users/*/AppData/Local; do
        [ -d "$h/boiii" ] && { printf '%s' "$h"; return; }
    done
}

declare -A ROOT_CACHE=()
root_of() {  # root_of <family>
    if [ -z "${ROOT_CACHE[$1]+set}" ]; then
        if [ -n "$TO_ARG" ] && is_root "$1" "$TO_ARG"; then
            ROOT_CACHE[$1]="$TO_ARG"
        else
            case "$1" in
                pluto)   ROOT_CACHE[$1]="$(find_pluto)" ;;
                appdata) ROOT_CACHE[$1]="$(find_appdata)" ;;
                bo3)     ROOT_CACHE[$1]="$(find_game bo3 '*Black Ops III*')" ;;
                bo4)     ROOT_CACHE[$1]="$(find_game bo4 '*')" ;;
            esac
        fi
    fi
    printf '%s' "${ROOT_CACHE[$1]}"
}

if [ -n "$TO_ARG" ] && ! is_root pluto "$TO_ARG" && ! is_root bo3 "$TO_ARG" && ! is_root bo4 "$TO_ARG"; then
    printf '\n'
    say "That is not a game folder ZShare knows: $TO_ARG"
    say "Plutonium is the folder with storage in it, Black Ops III the one with"
    say "BlackOps3.exe, boiii.exe or t7x.exe, and Black Ops 4 the one with BlackOps4.exe."
    exit 1
fi

# The folder a path really is, through any symlink on the way. A part that
# does not exist yet is kept as written.
real_path() {  # real_path <path>
    local d="$1" rest="" r
    while [ -n "$d" ] && [ "$d" != "/" ] && [ ! -e "$d" ]; do
        rest="/$(basename "$d")$rest"
        d="$(dirname "$d")"
    done
    [ -d "$d" ] || { printf '%s' "$1"; return 0; }
    r="$(cd -P "$d" 2>/dev/null && pwd -P)" || { printf '%s' "$1"; return 0; }
    printf '%s%s' "$r" "$rest"
}

# The per-client copies of Black Ops III beside the one found, into COPY_PATH,
# COPY_NAME and COPY_CLIENT: every folder whose name starts with its name and
# carries a client -- its exe or its folder -- whose folder is not a link
# back into the one found.
client_copies() {
    COPY_PATH=(); COPY_NAME=(); COPY_CLIENT=()
    local hub parent leaf c cl real hubs seen=" "
    hub="$(root_of bo3)"
    [ -n "$hub" ] || return 0
    parent="$(dirname "$hub")"; leaf="$(basename "$hub")"
    [ -d "$parent" ] || return 0
    for c in "$parent/$leaf"*; do
        [ -d "$c" ] || continue
        [ "$(basename "$c")" = "$leaf" ] && continue
        case "$c" in *455130*) continue ;; esac
        for cl in boiii t7x; do
            [ -e "$c/$cl.exe" ] || [ -e "$c/$cl" ] || continue
            real="$(real_path "$c/$cl")"; hubs="$(real_path "$hub/$cl")"
            [ "$real" = "$hubs" ] && continue
            case "$seen" in *" $real "*) continue ;; esac
            seen="$seen$real "
            COPY_PATH+=("$c"); COPY_NAME+=("$(basename "$c")"); COPY_CLIENT+=("$cl")
        done
    done
}

# ------------------------------------------------------------- the games

# Every game, in the order they are offered: key | name | other words for it.
GAMES=(
    "t6|Black Ops II|bo2"
    "t5|Black Ops|bo1 bo"
    "t4|World at War|waw"
    "t7|Black Ops III|bo3"
    "t8|Black Ops 4|bo4"
)

game_name() {  # game_name <key>
    local g k n a
    for g in "${GAMES[@]}"; do
        IFS='|' read -r k n a <<< "$g"
        [ "$k" = "$1" ] && { printf '%s' "$n"; return; }
    done
    printf '%s' "$1"
}

game_key() {  # game_key <word>
    local w g k n a x
    w="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    for g in "${GAMES[@]}"; do
        IFS='|' read -r k n a <<< "$g"
        [ "$k" = "$w" ] && { printf '%s' "$k"; return; }
        for x in $a; do [ "$x" = "$w" ] && { printf '%s' "$k"; return; }; done
    done
}

# ------------------------------------------------------------- the routes

# game | top | family | into | anchors | label | client | root -- the same
# table install.ps1 has. Anchors are any-of, space separated. Plutonium makes
# a game's storage folder the first time that game is launched, which is what
# makes it the anchor for each of the three. Client names the Black Ops III
# client a game-folder route belongs to, and root, when set, is the per-client
# copy of the game a route was repeated for.
ROUTES=(
    "t6|Plutonium/storage/t6|pluto|storage/t6|storage/t6|Black Ops II||"
    "t5|Plutonium/storage/t5|pluto|storage/t5|storage/t5|Black Ops||"
    "t4|Plutonium/storage/t4|pluto|storage/t4|storage/t4|World at War||"
    "t7|Black Ops III|bo3||boiii boiii.exe|Black Ops III -- BOIII / Ezz BOIII|boiii|"
    "t7|AppData|appdata||boiii/data|Black Ops III -- BOIII per user||"
    "t7|t7x|bo3|t7x|t7x t7x.exe|Black Ops III -- T7x|t7x|"
    "t8|zshare|bo4|project-bo4/mods/zshare|project-bo4/mods|Black Ops 4 -- Shield||"
)

# A per-client copy of Black Ops III gets its client's route again, aimed at
# that copy -- looked for only when this download carries Black Ops III, and
# kept with the rest of Black Ops III rather than after Black Ops 4.
if [ -d "$DOWNLOAD/Black Ops III" ] || [ -d "$DOWNLOAD/t7x" ]; then
    client_copies
    if [ "${#COPY_PATH[@]}" -gt 0 ]; then
        last=-1
        for i in "${!ROUTES[@]}"; do
            IFS='|' read -r game _ <<< "${ROUTES[$i]}"
            [ "$game" = "t7" ] && last="$i"
        done
        EXPANDED=()
        for i in "${!ROUTES[@]}"; do
            EXPANDED+=("${ROUTES[$i]}")
            [ "$i" = "$last" ] || continue
            for j in "${!COPY_PATH[@]}"; do
                for r2 in "${ROUTES[@]}"; do
                    IFS='|' read -r g2 top2 fam2 into2 anch2 label2 client2 _ <<< "$r2"
                    [ -n "$client2" ] && [ "$client2" = "${COPY_CLIENT[$j]}" ] || continue
                    EXPANDED+=("$g2|$top2|$fam2|$into2|$anch2|$label2, in ${COPY_NAME[$j]}|$client2|${COPY_PATH[$j]}")
                done
            done
        done
        ROUTES=("${EXPANDED[@]}")
    fi
fi

PLAN_GAME=(); PLAN_LABEL=(); PLAN_FROM=(); PLAN_TO=(); PLAN_READY=()

for r in "${ROUTES[@]}"; do
    IFS='|' read -r game top family into anchor label client rootset <<< "$r"
    src="$DOWNLOAD/$top"
    [ -d "$src" ] || continue

    if [ -n "$rootset" ]; then root="$rootset"; else root="$(root_of "$family")"; fi
    ready=0
    dest=""
    if [ -n "$root" ]; then
        for a in $anchor; do
            [ -e "$root/$a" ] && { ready=1; break; }
        done
        [ -z "$anchor" ] && [ -d "$root" ] && ready=1
        if [ -n "$into" ]; then dest="$root/$into"; else dest="$root"; fi
    fi

    while IFS= read -r -d '' f; do
        relpath="${f#"$src"/}"
        # Never the installer itself, wherever a download keeps it.
        case "/$relpath/" in */installer/*) continue ;; esac
        PLAN_GAME+=("$game")
        PLAN_LABEL+=("$label")
        PLAN_FROM+=("$f")
        if [ -n "$dest" ]; then PLAN_TO+=("$dest/$relpath"); else PLAN_TO+=(""); fi
        PLAN_READY+=("$ready")
    done < <(find "$src" -type f -print0 | sort -z)
done

if [ "${#PLAN_FROM[@]}" -eq 0 ]; then
    printf '\n'
    say "This download has nothing an installer can place."
    exit 1
fi

# ------------------------------------------------------------- which games

in_list() {  # in_list <word> <list...>
    local w="$1" x
    shift
    for x in "$@"; do [ "$x" = "$w" ] && return 0; done
    return 1
}

# The games this download carries, and the ones found on this machine.
PRESENT=()
HERE_GAMES=()
for g in "${GAMES[@]}"; do
    IFS='|' read -r k _ _ <<< "$g"
    has=0; ok=0
    for i in "${!PLAN_FROM[@]}"; do
        [ "${PLAN_GAME[$i]}" = "$k" ] || continue
        has=1
        [ "${PLAN_READY[$i]}" = 1 ] && ok=1
    done
    [ "$has" = 1 ] && PRESENT+=("$k")
    [ "$ok" = 1 ] && HERE_GAMES+=("$k")
done

# A download with one game has nothing to choose. With several, --game names
# them, --yes and --find take every one, and otherwise the player picks from a
# numbered list -- Enter for every game found here.
PICKED=()
if [ -n "$GAME_ARG" ]; then
    WANT=()
    for w in $(printf '%s' "$GAME_ARG" | tr ',' ' '); do
        k="$(game_key "$w")"
        if [ -z "$k" ] || ! in_list "$k" "${PRESENT[@]}"; then
            carried=""
            for p in "${PRESENT[@]}"; do carried="${carried:+$carried, }$p ($(game_name "$p"))"; done
            printf '\n'
            say "'$w' is not a game in this download. It carries: $carried."
            exit 1
        fi
        WANT+=("$k")
    done
    for p in "${PRESENT[@]}"; do in_list "$p" "${WANT[@]}" && PICKED+=("$p"); done
elif [ "${#PRESENT[@]}" -le 1 ] || [ "$FIND" = 1 ]; then
    PICKED=("${PRESENT[@]}")
elif [ "$YES" = 1 ]; then
    PICKED=("${HERE_GAMES[@]+"${HERE_GAMES[@]}"}")
else
    printf '\n'
    say "This download carries more than one game. Which do you want?"
    printf '\n'
    for i in "${!PRESENT[@]}"; do
        k="${PRESENT[$i]}"
        if in_list "$k" "${HERE_GAMES[@]+"${HERE_GAMES[@]}"}"; then s="found"; else s="not found on this machine"; fi
        printf '    %d. %-16s%s\n' "$((i + 1))" "$(game_name "$k")" "$s"
    done
    while :; do
        printf '\n'
        if [ ! -t 0 ]; then
            say "Nothing to answer with. Run it again with --game t6,t7 or with --yes."
            exit 0
        fi
        printf '  Numbers, like 1 4 -- or Enter for every game found: '
        if ! read -r a; then
            printf '\n'
            say "Nothing to answer with. Run it again with --game t6,t7 or with --yes."
            exit 0
        fi
        if [ -z "${a// /}" ]; then
            PICKED=("${HERE_GAMES[@]+"${HERE_GAMES[@]}"}")
            break
        fi
        WANT=(); BAD=()
        for w in $(printf '%s' "$a" | tr ',' ' '); do
            k=""
            case "$w" in
                ''|*[!0-9]*) ;;
                *) [ "$w" -ge 1 ] && [ "$w" -le "${#PRESENT[@]}" ] && k="${PRESENT[$((w - 1))]}" ;;
            esac
            if [ -z "$k" ]; then
                k="$(game_key "$w")"
                [ -n "$k" ] && ! in_list "$k" "${PRESENT[@]}" && k=""
            fi
            if [ -n "$k" ]; then WANT+=("$k"); else BAD+=("$w"); fi
        done
        if [ "${#BAD[@]}" -eq 0 ] && [ "${#WANT[@]}" -gt 0 ]; then
            for p in "${PRESENT[@]}"; do in_list "$p" "${WANT[@]}" && PICKED+=("$p"); done
            break
        fi
        say "Not in the list: ${BAD[*]-}"
    done
fi

# ------------------------------------------------------------- show it

printf '\n'
last=""
for i in "${!PLAN_FROM[@]}"; do
    in_list "${PLAN_GAME[$i]}" "${PICKED[@]+"${PICKED[@]}"}" || continue
    if [ "${PLAN_LABEL[$i]}" != "$last" ]; then
        last="${PLAN_LABEL[$i]}"
        if [ "${PLAN_READY[$i]}" = 1 ]; then
            printf '    %s\n' "$last"
        else
            printf '    %s   not installed here -- skipped\n' "$last"
        fi
    fi
    [ "${PLAN_READY[$i]}" = 1 ] && printf '      %s\n' "${PLAN_TO[$i]}"
done

if in_list t7 "${PICKED[@]+"${PICKED[@]}"}"; then
    printf '\n'
    say "The Steam Workshop version installs through Steam -- subscribe to it there."
fi

READY=()
for i in "${!PLAN_FROM[@]}"; do
    in_list "${PLAN_GAME[$i]}" "${PICKED[@]+"${PICKED[@]}"}" || continue
    [ "${PLAN_READY[$i]}" = 1 ] && READY+=("$i")
done

if [ "$FIND" = 1 ]; then
    printf '\n'
    if [ "$UNINSTALL" = 1 ]; then w=removed; else w=written; fi
    say "${#READY[@]} file(s) would be $w."
    exit 0
fi

if [ "${#READY[@]}" -eq 0 ]; then
    printf '\n'
    say "None of the games picked were found on this machine."
    say "Run the game once so it creates its folders, then run this again."
    exit 1
fi

# One question, answered once. With no terminal to answer from, stop and name
# the flag that would have answered it, rather than guessing or hanging.
confirm() {  # confirm <question> <flag>
    [ "$YES" = 1 ] && return 0
    if [ ! -t 0 ]; then
        printf '\n'
        say "Nothing to answer with. Run it again with $2."
        return 1
    fi
    local a
    printf '  %s [y/N] ' "$1"
    read -r a || return 1
    case "$a" in y*|Y*) return 0 ;; esac
    return 1
}

# ------------------------------------------------------------- remove

if [ "$UNINSTALL" = 1 ]; then
    HERE_NOW=()
    for i in "${READY[@]}"; do [ -f "${PLAN_TO[$i]}" ] && HERE_NOW+=("$i"); done
    printf '\n'
    if [ "${#HERE_NOW[@]}" -eq 0 ]; then
        say "ZShare is not installed in any of those places."
        exit 0
    fi
    say "${#HERE_NOW[@]} file(s) will be removed. Folders are left alone."
    confirm "remove?" "--uninstall --yes" || { say "Cancelled."; exit 0; }
    n=0
    for i in "${HERE_NOW[@]}"; do
        if rm -f "${PLAN_TO[$i]}"; then n=$((n + 1)); else say "could not remove ${PLAN_TO[$i]}"; fi
    done
    printf '\n'
    say "$n removed."
    exit 0
fi

# ------------------------------------------------------------- install

printf '\n'
say "Only ZShare's own files are written. Nothing is deleted."
confirm "install?" "--yes" || { say "Cancelled."; exit 0; }

n=0
failed=0
for i in "${READY[@]}"; do
    dir="$(dirname "${PLAN_TO[$i]}")"
    if mkdir -p "$dir" && cp -f "${PLAN_FROM[$i]}" "${PLAN_TO[$i]}"; then
        n=$((n + 1))
    else
        say "could not write ${PLAN_TO[$i]}"
        failed=$((failed + 1))
    fi
done

printf '\n'
if [ "$failed" -gt 0 ]; then
    say "$n installed, $failed failed. Is the game running?"
    exit 1
fi
say "$n installed."
say "End the current match and start a new one -- no game restart needed."
printf '\n'
exit 0
