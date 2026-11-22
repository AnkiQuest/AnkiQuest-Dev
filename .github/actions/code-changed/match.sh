#!/usr/bin/env bash
# Sorts paths, one per line on stdin, into docs and code: prints
# "docs<TAB>path" when the path matches one of the globs in $GLOBS (one per
# line; blank lines and lines starting with # are ignored), else
# "code<TAB>path".
#
# Globs: `*` and `?` stay within one directory, `**` spans directories and
# `**/` also matches no directory, so `**/*.md` matches README.md and
# a/b/c.md. Every other character is literal; there are no [classes].
set -euo pipefail

# shellcheck disable=SC2016 # literal characters, not expansions
readonly SPECIAL='\.+^$(){}|[]'

# One glob as an anchored extended regular expression.
glob_regex() {
  local glob=$1 regex='' char i
  for ((i = 0; i < ${#glob}; i++)); do
    char=${glob:i:1}
    if [[ ${glob:i:3} == '**/' ]]; then
      regex+='(.*/)?'
      i=$((i + 2))
    elif [[ ${glob:i:2} == '**' ]]; then
      regex+='.*'
      i=$((i + 1))
    elif [[ $char == '*' ]]; then
      regex+='[^/]*'
    elif [[ $char == '?' ]]; then
      regex+='[^/]'
    elif [[ $SPECIAL == *"$char"* ]]; then
      regex+="\\$char"
    else
      regex+=$char
    fi
  done
  printf '^%s$' "$regex"
}

# The globs, trimmed, without blank lines and comments.
regexes=()
while IFS= read -r glob; do
  glob=${glob#"${glob%%[![:space:]]*}"}
  glob=${glob%"${glob##*[![:space:]]}"}
  if [[ -z $glob || $glob == '#'* ]]; then
    continue
  fi
  regexes+=("$(glob_regex "$glob")")
done <<< "${GLOBS:-}"

while IFS= read -r path; do
  if [[ -z $path ]]; then
    continue
  fi
  kind=code
  for regex in "${regexes[@]}"; do
    if [[ $path =~ $regex ]]; then
      kind=docs
      break
    fi
  done
  printf '%s\t%s\n' "$kind" "$path"
done
