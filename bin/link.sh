script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

dfl_link_add "$script_dir/unzipj" "$HOME/.local/bin/unzipj"
dfl_link_add "$script_dir/screenshot-copy" "$HOME/.local/bin/screenshot-copy"
