#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_ROOT="$ROOT_DIR/dist"
REPO_SLUG="palginpav/wine-bleeding"

usage() {
    cat <<'EOF'
Usage:
  ./tools/publish-release.sh [DDMMYYYY] [--notes "text" | --notes-file FILE]

Behavior:
  - Finds dist/WINE-BLEEDING-DDMMYYYY
  - Packs it into dist/WINE-BLEEDING-DDMMYYYY.tar.gz
  - Creates annotated git tag DDMMYYYY if missing
  - Pushes the tag to origin if missing remotely
  - Creates a GitHub Release named DDMMYYYY with release notes
  - Uploads the tar.gz asset if missing

Options:
  --notes "text"       Custom release notes (markdown)
  --notes-file FILE    Read release notes from file
  --notes-auto         Auto-generate notes from git log since last tag
  --edit-notes         Open $EDITOR to edit notes before publishing

Notes:
  - Uses git credential helper for GitHub API auth.
  - If no version is passed, today's date is used.
  - If no notes are provided, auto-generates from git log.
EOF
}

fail() {
    echo "Error: $*" >&2
    exit 1
}

# --- Parse arguments ---
version=""
notes_text=""
notes_file=""
notes_auto=0
edit_notes=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --notes) notes_text="${2:-}"; shift ;;
        --notes-file) notes_file="${2:-}"; shift ;;
        --notes-auto) notes_auto=1 ;;
        --edit-notes) edit_notes=1 ;;
        [0-3][0-9][0-1][0-9][0-9][0-9][0-9][0-9]) version="$1" ;;
        *) fail "unknown argument: $1. Use --help for usage." ;;
    esac
    shift
done

version="${version:-$(date +%d%m%Y)}"

dist_name="WINE-BLEEDING-$version"
dist_dir="$DIST_ROOT/$dist_name"
archive_path="$DIST_ROOT/$dist_name.tar.gz"
asset_name="$(basename "$archive_path")"

[ -d "$dist_dir" ] || fail "distribution directory not found: $dist_dir"
[ -d "$ROOT_DIR/.git" ] || fail "run from inside the wine repository"

if ! git -C "$ROOT_DIR" remote get-url origin >/dev/null 2>&1; then
    fail "git remote 'origin' is not configured"
fi

for cmd in tar git curl jq; do
    command -v "$cmd" >/dev/null 2>&1 || fail "required command not found: $cmd"
done

# --- Generate release notes ---
generate_notes() {
    local prev_tag
    prev_tag=$(git -C "$ROOT_DIR" tag --sort=-creatordate | head -1 2>/dev/null || true)

    local wine_commits mono_commits wpf_commits winforms_commits
    if [ -n "$prev_tag" ]; then
        wine_commits=$(git -C "$ROOT_DIR" log --oneline "$prev_tag"..HEAD 2>/dev/null || true)
    else
        wine_commits=$(git -C "$ROOT_DIR" log --oneline --since="2026-03-01" 2>/dev/null || true)
    fi

    local mono_dir="$ROOT_DIR/build-deps/wine-mono/mono"
    local wpf_dir="$ROOT_DIR/build-deps/wine-mono/wpf"
    local wf_dir="$ROOT_DIR/build-deps/wine-mono/winforms"

    mono_commits=""
    [ -d "$mono_dir/.git" ] && mono_commits=$(git -C "$mono_dir" log --oneline wine-bleeding --not $(git -C "$mono_dir" merge-base wine-bleeding main 2>/dev/null || echo HEAD) 2>/dev/null || true)
    wpf_commits=""
    [ -d "$wpf_dir/.git" ] && wpf_commits=$(git -C "$wpf_dir" log --oneline wine-bleeding --not $(git -C "$wpf_dir" merge-base wine-bleeding main 2>/dev/null || echo HEAD) 2>/dev/null || true)
    winforms_commits=""
    [ -d "$wf_dir/.git" ] && winforms_commits=$(git -C "$wf_dir" log --oneline wine-bleeding --not $(git -C "$wf_dir" merge-base wine-bleeding main 2>/dev/null || echo HEAD) 2>/dev/null || true)

    cat <<NOTES
## WINE-BLEEDING $version

### Wine changes
$(echo "$wine_commits" | sed 's/^/- /' | head -30)

### wine-mono patches (palginpav forks)
NOTES

    if [ -n "$mono_commits" ]; then
        echo "**mono:**"
        echo "$mono_commits" | sed 's/^/- /'
    fi
    if [ -n "$wpf_commits" ]; then
        echo ""
        echo "**wpf:**"
        echo "$wpf_commits" | sed 's/^/- /'
    fi
    if [ -n "$winforms_commits" ]; then
        echo ""
        echo "**winforms:**"
        echo "$winforms_commits" | sed 's/^/- /'
    fi

    cat <<NOTES

### Deployment
\`\`\`bash
tar xf $asset_name -C ~/PortProton/data/dist/
./tools/deploy-to-portproton.sh $version
\`\`\`
NOTES
}

# Determine release notes
if [ -n "$notes_text" ]; then
    release_notes="$notes_text"
elif [ -n "$notes_file" ]; then
    [ -f "$notes_file" ] || fail "notes file not found: $notes_file"
    release_notes=$(cat "$notes_file")
else
    # Auto-generate
    release_notes=$(generate_notes)
fi

# Allow editing
if [ "$edit_notes" -eq 1 ]; then
    tmpfile=$(mktemp /tmp/release-notes-XXXXXX.md)
    echo "$release_notes" > "$tmpfile"
    "${EDITOR:-vi}" "$tmpfile"
    release_notes=$(cat "$tmpfile")
    rm -f "$tmpfile"
fi

echo "==> Release notes preview:"
echo "---"
echo "$release_notes" | head -40
echo "---"
echo ""
read -rp "Proceed with release? [Y/n] " confirm
case "$confirm" in
    n|N|no|No) echo "Aborted."; exit 0 ;;
esac

echo "==> Packaging $dist_name"
rm -f "$archive_path"
tar -C "$DIST_ROOT" -czf "$archive_path" "$dist_name"

echo "==> Resolving GitHub credentials"
cred="$(
    printf 'protocol=https\nhost=github.com\n\n' | git -C "$ROOT_DIR" credential fill
)"
gh_user="$(printf '%s\n' "$cred" | sed -n 's/^username=//p')"
gh_pass="$(printf '%s\n' "$cred" | sed -n 's/^password=//p')"

[ -n "$gh_user" ] || fail "git credential helper did not return a GitHub username"
[ -n "$gh_pass" ] || fail "git credential helper did not return a GitHub password/token"

github_api() {
    curl -fsS -u "$gh_user:$gh_pass" -H 'Accept: application/vnd.github+json' "$@"
}

echo "==> Ensuring git tag $version"
if ! git -C "$ROOT_DIR" rev-parse --verify "$version" >/dev/null 2>&1; then
    git -C "$ROOT_DIR" tag -a "$version" -m "wine-bleeding $version"
fi

if ! git -C "$ROOT_DIR" ls-remote --tags origin "refs/tags/$version" | grep -q .; then
    git -C "$ROOT_DIR" push origin "$version"
fi

echo "==> Ensuring GitHub Release $version"
release_json="$(
    github_api "https://api.github.com/repos/$REPO_SLUG/releases/tags/$version" 2>/dev/null || true
)"
release_id="$(printf '%s' "$release_json" | jq -r '.id // empty')"
release_url=""

if [ -z "$release_id" ]; then
    create_payload="$(
        jq -n \
            --arg tag "$version" \
            --arg name "$dist_name" \
            --arg body "$release_notes" \
            '{tag_name:$tag,name:$name,body:$body,draft:false,prerelease:false,generate_release_notes:false}'
    )"
    release_json="$(
        github_api \
            -H 'Content-Type: application/json' \
            -d "$create_payload" \
            "https://api.github.com/repos/$REPO_SLUG/releases"
    )"
    release_id="$(printf '%s' "$release_json" | jq -r '.id // empty')"
else
    # Update existing release notes
    update_payload="$(jq -n --arg body "$release_notes" --arg name "$dist_name" '{body:$body,name:$name}')"
    github_api -X PATCH \
        -H 'Content-Type: application/json' \
        -d "$update_payload" \
        "https://api.github.com/repos/$REPO_SLUG/releases/$release_id" >/dev/null
fi

[ -n "$release_id" ] || fail "failed to create or resolve GitHub Release for $version"

release_url="$(printf '%s' "$release_json" | jq -r '.html_url // empty')"
upload_url="$(printf '%s' "$release_json" | jq -r '.upload_url // empty' | sed 's/{?name,label}//')"
[ -n "$upload_url" ] || fail "release upload URL is missing"

asset_id="$(
    printf '%s' "$release_json" | jq -r --arg name "$asset_name" '.assets[]? | select(.name == $name) | .id' | head -n1
)"

if [ -z "$asset_id" ]; then
    echo "==> Uploading asset $asset_name ($(du -h "$archive_path" | cut -f1))"
    upload_json="$(
        github_api \
            -H 'Content-Type: application/gzip' \
            --data-binary @"$archive_path" \
            "$upload_url?name=$asset_name"
    )"
    asset_id="$(printf '%s' "$upload_json" | jq -r '.id // empty')"
    [ -n "$asset_id" ] || fail "asset upload failed"
fi

download_url="$(
    github_api "https://api.github.com/repos/$REPO_SLUG/releases/tags/$version" |
    jq -r --arg name "$asset_name" '.assets[]? | select(.name == $name) | .browser_download_url'
)"

echo ""
echo "Release: ${release_url:-https://github.com/$REPO_SLUG/releases/tag/$version}"
echo "Asset:   $download_url"
