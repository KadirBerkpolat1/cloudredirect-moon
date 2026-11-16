#!/usr/bin/env bash
# x86_64: the steamrt64 bootstrapper is a `steam` without STEAM_STEAMRT_RECURSION_GUARD
# that never maps steamclient.so. The hook must leave LD_PRELOAD to the client it
# re-launches and start nothing there; the guarded client takes LD_PRELOAD out of its
# children's environment and starts the deferred init.
set -eu

library="${1:?cloud_redirect.so path is required}"
compiler="${CC:-cc}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/steam.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(void) {
    const char* preload = getenv("LD_PRELOAD");
    printf("%s\n", preload ? preload : "");
    usleep(10000);
    return 0;
}
EOF
"$compiler" "$tmp/steam.c" -o "$tmp/steam"

run() {
    local home="$1"; shift
    mkdir -p "$home"
    env -i PATH=/usr/bin:/bin HOME="$home" XDG_CONFIG_HOME="$home/config" \
        XDG_DATA_HOME="$home/data" "$@" LD_PRELOAD="$library" "$tmp/steam"
}

out="$(run "$tmp/boot")"
[ "$out" = "$library" ] || { echo "FAIL: bootstrapper lost LD_PRELOAD (got '$out')" >&2; exit 1; }
if grep -q 'OnLoad: target process' "$tmp/boot/config/CloudRedirect/cr_debug.log" 2>/dev/null; then
    echo "FAIL: deferred init started in the bootstrapper" >&2
    exit 1
fi

out="$(run "$tmp/client" STEAM_STEAMRT_RECURSION_GUARD=1)"
[ -z "$out" ] || { echo "FAIL: guarded client kept LD_PRELOAD for its children (got '$out')" >&2; exit 1; }
grep -q 'OnLoad: target process' "$tmp/client/config/CloudRedirect/cr_debug.log" || {
    echo "FAIL: deferred init did not start in the guarded client" >&2
    exit 1
}

echo "linux bootstrapper gate test passed"
