#!/usr/bin/env bash
# Installs T3 Bar into /Applications, or updates it in place if it is already there.
# Safe to re-run: every run pulls the latest code, rebuilds, and swaps the app bundle.
set -euo pipefail

main() {
    cd "$(dirname "$0")/.."
    pull_latest
    build_bundle
    install_bundle "$(install_dir)"
}

readonly BUNDLE_ID="com.torz.t3bar"
readonly APP_NAME="T3 Bar.app"
readonly BUILT_APP="dist/$APP_NAME"

pull_latest() {
    if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        echo "==> No upstream branch, installing the checkout as it is"
        return
    fi
    echo "==> Pulling latest changes"
    # Fast-forward only: a diverged checkout is someone's work in progress, so stop rather than merge into it.
    git pull --ff-only
}

build_bundle() {
    echo "==> Building"
    make app
    # The linker's ad-hoc signature covers only the binary; signing the bundle binds Info.plist to it, so the
    # system sees one stable identity (com.torz.t3bar) for the login item across updates.
    codesign --force --sign - "$BUILT_APP"
}

# /Applications is writable for admin users; everyone else gets the per-user Applications folder, which
# Launch Services and Spotlight index just the same.
install_dir() {
    if [[ -w /Applications ]]; then
        echo /Applications
    else
        mkdir -p "$HOME/Applications"
        echo "$HOME/Applications"
    fi
}

install_bundle() {
    local target="$1/$APP_NAME"
    if [[ -d "$target" ]]; then
        echo "==> Updating $target"
    else
        echo "==> Installing to $target"
    fi
    quit_running_app
    rm -rf "$target"
    ditto "$BUILT_APP" "$target"
    open "$target"
    echo "==> Done, T3 Bar is running from $target"
}

# Replacing the bundle under a running process leaves the old binary in memory until the next login, so the
# update would look like it did nothing.
quit_running_app() {
    # Guarded because telling an app that is not running to quit launches it first.
    pgrep -x T3Bar >/dev/null || return 0
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -x T3Bar >/dev/null || return 0
        sleep 0.25
    done
    pkill -x T3Bar || true
}

main "$@"
