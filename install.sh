#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
umask 077

DEFAULT_REPO="samperez10/ecnl-bot"
REPO="${ECNL_REPO:-$DEFAULT_REPO}"
VERSION="latest"
INSTALL_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
INSTALL_DIR="${ECNL_INSTALL_DIR:-$HOME/ecnl}"
LOCAL_ARCHIVE=""
LOCAL_CHECKSUM=""
GITHUB_AUTH=0

usage() {
    cat <<'EOF'
Install the compiled ECNL app and the ecnl command in Termux.

Usage: bash install.sh [--repo OWNER/REPO] [--version TAG] [--prefix DIR] [--install-dir DIR]
                      [--github-auth] [--archive FILE --checksum FILE]

The default downloads the latest GitHub Release. Local archives support
installation without a download. Re-run to update; account and license data
remain in ~/ecnl/data. A new installation starts with no accounts or license.
--install-dir chooses the app folder; --prefix chooses where bin/ecnl goes.
--github-auth uses an authenticated GitHub CLI session for private releases.
EOF
}
fail() { echo "Error: $*" >&2; exit 1; }

format_bytes() {
    local bytes="${1:-0}" tenths
    if [ "$bytes" -ge 1048576 ]; then
        tenths=$((bytes * 10 / 1048576))
        printf '%s.%s MB' "$((tenths / 10))" "$((tenths % 10))"
    elif [ "$bytes" -ge 1024 ]; then
        tenths=$((bytes * 10 / 1024))
        printf '%s.%s KB' "$((tenths / 10))" "$((tenths % 10))"
    else
        printf '%s B' "$bytes"
    fi
}

clear_progress() {
    if [ -t 1 ]; then printf '\r\033[2K'; fi
}

download_file() {
    local url="$1" destination="$2" label="$3" completed="$4"
    local partial="${2}.partial" errors="${2}.error" headers="${2}.headers"
    local frame=0 downloaded=0 total=0 percent status detail
    local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    if [ ! -t 1 ]; then printf '%s…\n' "$label"; fi
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --connect-timeout 15 \
        --max-time 300 --dump-header "$headers" -o "$partial" "$url" 2>"$errors" &
    DOWNLOAD_PID=$!
    while kill -0 "$DOWNLOAD_PID" 2>/dev/null; do
        if [ -t 1 ]; then
            downloaded=0
            [ ! -f "$partial" ] || downloaded="$(stat -c %s "$partial")"
            total="$(sed -n 's/^[Cc]ontent-[Ll]ength:[[:space:]]*\([0-9]*\).*/\1/p' "$headers" 2>/dev/null | tail -n 1)" || total=0
            [[ "$total" =~ ^[0-9]+$ ]] || total=0
            if [ "$total" -gt 0 ]; then
                percent=$((downloaded * 100 / total))
                [ "$percent" -le 100 ] || percent=100
                printf '\r\033[2K%s %s  %3s%% · %s / %s' \
                    "${frames[frame % 10]}" "$label" "$percent" \
                    "$(format_bytes "$downloaded")" "$(format_bytes "$total")"
            else
                printf '\r\033[2K%s %s · %s' "${frames[frame % 10]}" "$label" "$(format_bytes "$downloaded")"
            fi
        fi
        frame=$((frame + 1))
        sleep 0.1
    done
    if wait "$DOWNLOAD_PID"; then status=0; else status=$?; fi
    DOWNLOAD_PID=""
    clear_progress
    if [ "$status" -ne 0 ]; then
        detail="$(sed -n '1p' "$errors")"
        [ -n "$detail" ] || detail="curl exited with status $status"
        fail "$label failed: $detail"
    fi
    mv -f -- "$partial" "$destination"
    downloaded="$(stat -c %s "$destination")"
    rm -f -- "$errors" "$headers"
    printf '✓ %s · %s\n' "$completed" "$(format_bytes "$downloaded")"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo|--version|--prefix|--install-dir|--archive|--checksum)
            [ "$#" -ge 2 ] || fail "Missing value for $1"
            case "$1" in
                --repo) REPO="$2" ;;
                --version) VERSION="$2" ;;
                --prefix) INSTALL_PREFIX="$2" ;;
                --install-dir) INSTALL_DIR="$2" ;;
                --archive) LOCAL_ARCHIVE="$2" ;;
                --checksum) LOCAL_CHECKSUM="$2" ;;
            esac
            shift 2 ;;
        --github-auth) GITHUB_AUTH=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option: $1" ;;
    esac
done

[ -x /system/bin/linker64 ] || fail "This build requires Android Termux."
case "$(uname -m)" in
    aarch64) ARCH="aarch64" ;;
    *) fail "This release supports aarch64 Termux only." ;;
esac
[[ "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "Invalid release tag."
for tool in tar sha256sum mktemp flock; do
    command -v "$tool" >/dev/null || fail "Missing $tool. Run: pkg install coreutils tar util-linux"
done

ASSET="ecnl-termux-$ARCH.tar.gz"
mkdir -p "$INSTALL_DIR"
APP_ROOT="$(CDPATH= cd -- "$INSTALL_DIR" && pwd -P)"
HOME_ROOT="$(CDPATH= cd -- "$HOME" && pwd -P)"
case "$APP_ROOT" in
    /|"$HOME_ROOT"|"${PREFIX:-/data/data/com.termux/files/usr}")
        fail "Choose a dedicated ECNL installation folder." ;;
esac
# The uninstall command removes this whole folder, so it must be dedicated.
shopt -s nullglob dotglob
for entry in "$APP_ROOT"/*; do
    case "$(basename -- "$entry")" in
        releases|current|data|uninstall.sh|update.sh|.update-lock|.ecnl-install|.launcher-copy|.install.*) ;;
        *) fail "Installation folder contains unrelated files: $entry" ;;
    esac
done
shopt -u nullglob dotglob
BIN_DIR="$INSTALL_PREFIX/bin"
mkdir -p "$APP_ROOT/releases" "$BIN_DIR"
BIN_DIR="$(CDPATH= cd -- "$BIN_DIR" && pwd -P)"
WORK_DIR="$(mktemp -d "$APP_ROOT/.install.XXXXXX")"
LAUNCHER_TEMP=""
RELEASE_DIR=""
ACTIVATED=0
DOWNLOAD_PID=""
cleanup() {
    if [ -n "$DOWNLOAD_PID" ]; then
        kill "$DOWNLOAD_PID" 2>/dev/null || true
        wait "$DOWNLOAD_PID" 2>/dev/null || true
        clear_progress
    fi
    rm -rf -- "$WORK_DIR"
    [ -z "$LAUNCHER_TEMP" ] || rm -f -- "$LAUNCHER_TEMP"
    if [ "$ACTIVATED" -eq 0 ] && [ -n "$RELEASE_DIR" ]; then
        rm -rf -- "$RELEASE_DIR"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
printf '\nECNL INSTALLER\nTermux ARM64\n\n'

if [ -n "$LOCAL_ARCHIVE" ]; then
    [ -n "$LOCAL_CHECKSUM" ] || fail "--archive requires --checksum."
    cp -- "$LOCAL_ARCHIVE" "$WORK_DIR/$ASSET"
    cp -- "$LOCAL_CHECKSUM" "$WORK_DIR/SHA256SUMS"
else
    [ -z "$LOCAL_CHECKSUM" ] || fail "--checksum requires --archive."
    [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "Specify --repo OWNER/REPO."
    if [ "$VERSION" = latest ]; then
        if [ "$GITHUB_AUTH" -eq 1 ]; then
            command -v gh >/dev/null || fail "Private downloads require gh. Run: pkg install gh; gh auth login"
            VERSION="$(gh api "repos/$REPO/releases/latest" --jq .tag_name)"
        else
            command -v curl >/dev/null || fail "Missing curl. Run: pkg install curl"
            RELEASE_URL="$(curl --proto '=https' --tlsv1.2 -fsSIL --max-time 15 \
                -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")"
            VERSION="${RELEASE_URL##*/}"
        fi
        [[ "$VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Latest release must have a version tag such as v1.0.1."
    fi
    if [ "$GITHUB_AUTH" -eq 1 ]; then
        command -v gh >/dev/null || fail "Private downloads require gh. Run: pkg install gh; gh auth login"
        RELEASE_ARGS=()
        if [ "$VERSION" != latest ]; then
            RELEASE_ARGS+=("$VERSION")
        fi
        printf 'Downloading ECNL…\n'
        gh release download "${RELEASE_ARGS[@]}" --repo "$REPO" --dir "$WORK_DIR" \
            --pattern "$ASSET" --pattern SHA256SUMS > "$WORK_DIR/download.log" 2>&1 \
            || fail "Download failed: $(sed -n '1p' "$WORK_DIR/download.log")"
        printf '✓ Download complete · %s\n' "$(format_bytes "$(stat -c %s "$WORK_DIR/$ASSET")")"
    else
    command -v curl >/dev/null || fail "Missing curl. Run: pkg install curl"
    if [ "$VERSION" = latest ]; then
        DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download"
    else
        DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION"
    fi
    download_file "$DOWNLOAD_URL/$ASSET" "$WORK_DIR/$ASSET" "Downloading ECNL" "Download complete"
    download_file "$DOWNLOAD_URL/SHA256SUMS" "$WORK_DIR/SHA256SUMS" "Downloading checksum" "Checksum received"
    fi
fi

# Only this asset may be referenced by the checksum file.
CHECKSUM=""
while read -r digest filename extra; do
    [ -z "$digest" ] && continue
    [[ "$digest" =~ ^[a-fA-F0-9]{64}$ ]] || fail "Invalid checksum file."
    [ "$filename" = "$ASSET" ] && [ -z "${extra:-}" ] || fail "Unexpected checksum entry."
    [ -z "$CHECKSUM" ] || fail "Duplicate checksum entry."
    CHECKSUM="$digest"
done < "$WORK_DIR/SHA256SUMS"
[ -n "$CHECKSUM" ] || fail "Archive checksum is missing."
(cd "$WORK_DIR" && printf '%s  %s\n' "$CHECKSUM" "$ASSET" | sha256sum --status -c -) || fail "Release checksum verification failed."
printf '✓ Release checksum verified\n'

# Release packages have a single ecnl/ root. Reject unexpected paths.
tar -tzf "$WORK_DIR/$ASSET" > "$WORK_DIR/contents.txt"
while IFS= read -r entry; do
    case "$entry" in
        ecnl|ecnl/|ecnl/*) ;;
        *) fail "Unexpected archive path: $entry" ;;
    esac
    case "/$entry/" in
        */../*|*/./*) fail "Unsafe archive path: $entry" ;;
    esac
done < "$WORK_DIR/contents.txt"
printf 'Extracting release…\n'
tar --no-same-owner --no-same-permissions -xzf "$WORK_DIR/$ASSET" -C "$WORK_DIR"
[ -f "$WORK_DIR/ecnl/ecnl-auto-solver" ] || fail "Executable is missing from the archive."
chmod +x "$WORK_DIR/ecnl/ecnl-auto-solver"
if [ "$VERSION" = latest ]; then
    # Offline packages carry their version in the release manifest.
    [ -f "$WORK_DIR/ecnl/release.json" ] || fail "Local package has no version metadata; specify --version."
    PACKAGE_VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK_DIR/ecnl/release.json")"
else
    PACKAGE_VERSION="${VERSION#v}"
fi
[[ "$PACKAGE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Package version must be MAJOR.MINOR.PATCH."
printf '%s\n' "$PACKAGE_VERSION" > "$WORK_DIR/ecnl/VERSION"
printf '✓ Release extracted\nChecking app…\n'
if ! "$WORK_DIR/ecnl/ecnl-auto-solver" --help > "$WORK_DIR/startup.log" 2>&1 || \
   ! "$WORK_DIR/ecnl/ecnl-auto-solver" tui --smoke-test >> "$WORK_DIR/startup.log" 2>&1; then
    cat "$WORK_DIR/startup.log" >&2
    fail "App startup check failed."
fi
printf '✓ App ready\n'

RELEASE_DIR="$(mktemp -d "$APP_ROOT/releases/$VERSION.XXXXXX")"
mv -- "$WORK_DIR/ecnl" "$RELEASE_DIR/app"
LAUNCHER_TEMP="$(mktemp "$BIN_DIR/.ecnl.XXXXXX")"
{
    printf '%s\n' '#!/data/data/com.termux/files/usr/bin/bash' 'set -eu'
    printf 'APP_ROOT=%q\n' "$APP_ROOT"
    cat <<'EOF'
if [ "${1:-}" = uninstall ]; then
    shift
    [ "$#" -eq 0 ] || { echo "Usage: ecnl uninstall" >&2; exit 1; }
    exec bash "$APP_ROOT/uninstall.sh"
fi
bash "$APP_ROOT/update.sh" || echo "Update check failed; starting installed ECNL." >&2
exec "$APP_ROOT/current/ecnl-auto-solver" --config "$APP_ROOT/data/config.json" "$@"
EOF
} > "$LAUNCHER_TEMP"
{
    printf '%s\n' '#!/data/data/com.termux/files/usr/bin/bash' 'set -euo pipefail'
    printf 'APP_ROOT=%q\n' "$APP_ROOT"
    printf 'LAUNCHER=%q\n' "$BIN_DIR/ecnl"
    cat <<'EOF'
[ -f "$APP_ROOT/.ecnl-install" ] || { echo "ECNL installation marker is missing; nothing removed." >&2; exit 1; }
case "$APP_ROOT" in
    ''|/|"$HOME"|"${PREFIX:-/data/data/com.termux/files/usr}")
        echo "Refusing to remove a system or home directory." >&2; exit 1 ;;
esac
printf 'Remove ECNL from %s and delete ALL accounts, passwords, sessions, logs, and local license data? [y/N] ' "$APP_ROOT"
if ! IFS= read -r answer; then
    echo
    echo "Uninstall cancelled."
    exit 0
fi
case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Uninstall cancelled."; exit 0 ;;
esac
# Unlink this installation's launcher only. Another install may now own it.
if [ -f "$LAUNCHER" ] && cmp -s "$LAUNCHER" "$APP_ROOT/.launcher-copy"; then
    rm -f -- "$LAUNCHER"
fi
rm -rf -- "$APP_ROOT"
echo "ECNL uninstalled, including all local data."
echo "This does not release the license's server-side installation binding."
EOF
} > "$WORK_DIR/uninstall.sh"
chmod 700 "$WORK_DIR/uninstall.sh"
cp -- "$LAUNCHER_TEMP" "$WORK_DIR/launcher-copy"
{
    printf '%s\n' '#!/data/data/com.termux/files/usr/bin/bash' 'set -euo pipefail' 'umask 077'
    printf 'APP_ROOT=%q\n' "$APP_ROOT"
    printf 'INSTALL_PREFIX=%q\n' "$(dirname -- "$BIN_DIR")"
    printf 'REPO=%q\n' "$REPO"
    printf 'GITHUB_AUTH=%q\n' "$GITHUB_AUTH"
    cat <<'EOF'
# Checking and installing are serialized across simultaneous launcher invocations.
LOCK="$APP_ROOT/.update-lock"
# A kernel lock is released even if Android kills this process.
exec 9> "$LOCK"
flock -n 9 || exit 0
UPDATE_DIR=""
cleanup_update() {
    [ -z "$UPDATE_DIR" ] || rm -rf -- "$UPDATE_DIR"
}
trap cleanup_update EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
if [ "$GITHUB_AUTH" -eq 1 ]; then
    LATEST="$(timeout 10 gh api "repos/$REPO/releases/latest" --jq .tag_name 2>/dev/null)" || exit 0
else
    URL="$(curl --proto '=https' --tlsv1.2 -fsSIL --connect-timeout 3 --max-time 8 \
        -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null)" || exit 0
    LATEST="${URL##*/}"
fi
[[ "$LATEST" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || exit 0
NEW_PARTS=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
IFS= read -r CURRENT < "$APP_ROOT/current/VERSION" || exit 0
[[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || exit 0
OLD_PARTS=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
NEWER=0
for i in 0 1 2; do
    # Bound numeric input before Bash arithmetic and compare decimal components.
    [ "${#NEW_PARTS[i]}" -le 8 ] && [ "${#OLD_PARTS[i]}" -le 8 ] || exit 0
    new=$((10#${NEW_PARTS[i]}))
    old=$((10#${OLD_PARTS[i]}))
    if [ "$new" -gt "$old" ]; then NEWER=1; break; fi
    if [ "$new" -lt "$old" ]; then exit 0; fi
done
[ "$NEWER" -eq 1 ] || exit 0
UPDATE_DIR="$(mktemp -d "$APP_ROOT/.install.update.XXXXXX")"
INSTALLER="$UPDATE_DIR/install.sh"
AUTH_ARGS=()
if [ "$GITHUB_AUTH" -eq 1 ]; then
    AUTH_ARGS+=(--github-auth)
    timeout 60 gh release download "$LATEST" --repo "$REPO" --dir "$UPDATE_DIR" \
        --pattern install.sh || exit 0
else
    curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout 5 --max-time 60 \
        "https://github.com/$REPO/releases/download/$LATEST/install.sh" -o "$INSTALLER" || exit 0
fi
bash -n "$INSTALLER" || exit 0
echo "Updating ECNL $CURRENT → ${LATEST#v}..."
if bash "$INSTALLER" --repo "$REPO" --version "$LATEST" --prefix "$INSTALL_PREFIX" \
    --install-dir "$APP_ROOT" "${AUTH_ARGS[@]}"; then
    echo "ECNL updated. Starting app..."
else
    echo "Update failed; starting the installed version." >&2
fi
EOF
} > "$WORK_DIR/update.sh"
chmod 700 "$WORK_DIR/update.sh"
# Create only the install's own empty config; never import existing accounts.
mkdir -p "$APP_ROOT/data"
if [ ! -e "$APP_ROOT/data/config.json" ]; then
    (set -o noclobber; printf '%s\n' '{"accounts": []}' > "$APP_ROOT/data/config.json")
fi
chmod 755 "$LAUNCHER_TEMP"
ln -s "releases/$(basename -- "$RELEASE_DIR")/app" "$WORK_DIR/current"
mv -Tf -- "$WORK_DIR/current" "$APP_ROOT/current"
ACTIVATED=1
mv -f -- "$WORK_DIR/uninstall.sh" "$APP_ROOT/uninstall.sh"
mv -f -- "$WORK_DIR/update.sh" "$APP_ROOT/update.sh"
mv -f -- "$WORK_DIR/launcher-copy" "$APP_ROOT/.launcher-copy"
printf '%s\n' 'ECNL installer-managed directory' > "$APP_ROOT/.ecnl-install"
mv -f -- "$LAUNCHER_TEMP" "$BIN_DIR/ecnl"
LAUNCHER_TEMP=""
printf '\nInstalled in %s\nRun: ecnl\n' "$APP_ROOT"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Add $BIN_DIR to PATH to use the ecnl command." ;;
esac
