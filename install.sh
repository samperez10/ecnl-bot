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
for tool in tar sha256sum mktemp; do
    command -v "$tool" >/dev/null || fail "Missing $tool. Run: pkg install coreutils tar"
done

ASSET="ecnl-termux-$ARCH.tar.gz"
mkdir -p "$INSTALL_DIR"
APP_ROOT="$(CDPATH= cd -- "$INSTALL_DIR" && pwd)"
BIN_DIR="$INSTALL_PREFIX/bin"
mkdir -p "$APP_ROOT/releases" "$BIN_DIR"
WORK_DIR="$(mktemp -d "$APP_ROOT/.install.XXXXXX")"
LAUNCHER_TEMP=""
RELEASE_DIR=""
ACTIVATED=0
cleanup() {
    rm -rf -- "$WORK_DIR"
    [ -z "$LAUNCHER_TEMP" ] || rm -f -- "$LAUNCHER_TEMP"
    if [ "$ACTIVATED" -eq 0 ] && [ -n "$RELEASE_DIR" ]; then
        rm -rf -- "$RELEASE_DIR"
    fi
}
trap cleanup EXIT

if [ -n "$LOCAL_ARCHIVE" ]; then
    [ -n "$LOCAL_CHECKSUM" ] || fail "--archive requires --checksum."
    cp -- "$LOCAL_ARCHIVE" "$WORK_DIR/$ASSET"
    cp -- "$LOCAL_CHECKSUM" "$WORK_DIR/SHA256SUMS"
else
    [ -z "$LOCAL_CHECKSUM" ] || fail "--checksum requires --archive."
    [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "Specify --repo OWNER/REPO."
    if [ "$GITHUB_AUTH" -eq 1 ]; then
        command -v gh >/dev/null || fail "Private downloads require gh. Run: pkg install gh; gh auth login"
        RELEASE_ARGS=()
        if [ "$VERSION" != latest ]; then
            RELEASE_ARGS+=("$VERSION")
        fi
        gh release download "${RELEASE_ARGS[@]}" --repo "$REPO" --dir "$WORK_DIR" \
            --pattern "$ASSET" --pattern SHA256SUMS
    else
    command -v curl >/dev/null || fail "Missing curl. Run: pkg install curl"
    if [ "$VERSION" = latest ]; then
        DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download"
    else
        DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION"
    fi
    echo "Downloading ECNL ($VERSION, $ARCH)..."
    curl --proto '=https' --tlsv1.2 -fL --retry 3 "$DOWNLOAD_URL/$ASSET" -o "$WORK_DIR/$ASSET"
    curl --proto '=https' --tlsv1.2 -fL --retry 3 "$DOWNLOAD_URL/SHA256SUMS" -o "$WORK_DIR/SHA256SUMS"
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
(cd "$WORK_DIR" && printf '%s  %s\n' "$CHECKSUM" "$ASSET" | sha256sum -c -)

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
tar --no-same-owner --no-same-permissions -xzf "$WORK_DIR/$ASSET" -C "$WORK_DIR"
[ -f "$WORK_DIR/ecnl/ecnl-auto-solver" ] || fail "Executable is missing from the archive."
chmod +x "$WORK_DIR/ecnl/ecnl-auto-solver"
echo "Checking the downloaded app..."
"$WORK_DIR/ecnl/ecnl-auto-solver" --help >/dev/null
"$WORK_DIR/ecnl/ecnl-auto-solver" tui --smoke-test

RELEASE_DIR="$(mktemp -d "$APP_ROOT/releases/$VERSION.XXXXXX")"
mv -- "$WORK_DIR/ecnl" "$RELEASE_DIR/app"
LAUNCHER_TEMP="$(mktemp "$BIN_DIR/.ecnl.XXXXXX")"
{
    printf '%s\n' '#!/data/data/com.termux/files/usr/bin/bash' 'set -eu'
    printf 'APP_ROOT=%q\n' "$APP_ROOT"
    cat <<'EOF'
exec "$APP_ROOT/current/ecnl-auto-solver" --config "$APP_ROOT/data/config.json" "$@"
EOF
} > "$LAUNCHER_TEMP"
# Create only the install's own empty config; never import existing accounts.
mkdir -p "$APP_ROOT/data"
if [ ! -e "$APP_ROOT/data/config.json" ]; then
    (set -o noclobber; printf '%s\n' '{"accounts": []}' > "$APP_ROOT/data/config.json")
fi
chmod 755 "$LAUNCHER_TEMP"
ln -s "releases/$(basename -- "$RELEASE_DIR")/app" "$WORK_DIR/current"
mv -Tf -- "$WORK_DIR/current" "$APP_ROOT/current"
ACTIVATED=1
mv -f -- "$LAUNCHER_TEMP" "$BIN_DIR/ecnl"
LAUNCHER_TEMP=""
echo "Installed in $APP_ROOT. Run: ecnl"
echo "CLI examples: ecnl status | ecnl run --task math | ecnl license activate"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Add $BIN_DIR to PATH to use the ecnl command." ;;
esac
