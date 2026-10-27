#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$script_dir/vendor/dotfiles-lib/dotfiles-lib.sh"

quiet=false
dry_run=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet) quiet=true ;;
        --dry-run) dry_run=true ;;
        -h|--help)
            printf 'Usage: %s [--dry-run] [-q|--quiet]\n' "$0"
            exit 0
            ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

: "${HOME:?HOME must be set and nonempty}"
export _dfl_quiet=$quiet

dfl_link_reset
source "$script_dir/bin/link.sh"

if [[ $dry_run == true ]]; then
    dfl_link_preview
else
    dfl_link_apply
fi
