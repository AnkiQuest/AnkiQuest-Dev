#!/usr/bin/env bash
# Publishes the files as release $TAG of $GITHUB_REPOSITORY at commit
# $TARGET, updating the release in place. See action.yml.
set -euo pipefail

api="repos/$GITHUB_REPOSITORY"
body=$NOTES
if [[ -n $NOTES_FILE ]]; then
  body=$(<"$NOTES_FILE")
fi

# The files, one path or glob per line, and their asset names.
paths=()
while read -r line; do
  [[ -n $line ]] || continue
  # shellcheck disable=SC2206 # the line is a glob
  paths+=($line)
done <<< "$FILES"
names=" ${paths[*]##*/} "

# Runs a GitHub API call up to four times, waiting longer after each failure.
# Tests set RETRY_WAITS to skip the waits.
retry() {
  local wait
  for wait in ${RETRY_WAITS-10 30 60}; do
    "$@" && return
    echo "::warning::$1 failed, retrying in ${wait}s"
    sleep "$wait"
  done
  "$@"
}

# The release's id, or the id of an untagged draft a failed run left behind
# (see untag); creates the release if there is neither.
locate() {
  id=$(gh api "$api/releases?per_page=100" --jq "[.[] | select(.tag_name == \"$TAG\"
    or (.draft and .prerelease and (.tag_name | startswith(\"untagged-\"))))][0].id // empty") && [[ -n $id ]]
}
ensure() {
  locate || { gh api "$api/releases" -f tag_name="$TAG" -f target_commitish="$TARGET" -f name="$TITLE" \
    -F prerelease=true -f make_latest=false > /dev/null && locate; }
}

# Moves the tag to $TARGET and sets the title and notes. GitHub refuses to
# move a tag with this token past commits that change workflows, so the tag
# is deleted and publish has the release API create it again at $TARGET.
# The release is an untagged draft in between.
move() {
  { moved || untag; } && publish && moved
}
untag() {
  gh api -X DELETE "$api/git/refs/tags/$TAG" || ! gh api "$api/git/ref/tags/$TAG" > /dev/null
}
publish() {
  gh api -X PATCH "$api/releases/$id" -f tag_name="$TAG" -f target_commitish="$TARGET" -f name="$TITLE" \
    -f body="$body" -F draft=false -F prerelease=true -f make_latest=false > /dev/null
}
moved() {
  [[ $(gh api "$api/git/ref/tags/$TAG" --jq .object.sha) == "$TARGET" ]]
}

# Deletes the assets that are not among the files.
prune() {
  local listed name
  listed=$(gh release view "$TAG" --json assets --jq '.assets[].name') || return
  for name in $listed; do
    if [[ $names != *" $name "* ]]; then
      gh release delete-asset "$TAG" "$name" --yes || return
    fi
  done
}

retry ensure
retry move
retry gh release upload "$TAG" "${paths[@]}" --clobber
retry prune
