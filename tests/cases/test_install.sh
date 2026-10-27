#!/usr/bin/env bash

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

setUp() {
    test_dir="$(mktemp -d "$SHUNIT_TMPDIR/install.XXXXXX")" || return 1
    fixture="$test_dir/repo space"
    test_home="$test_dir/home space"
    mkdir -p "$fixture" || return 1
    cp -a "$repo_dir/install.sh" "$repo_dir/bin" "$repo_dir/scripts" "$repo_dir/vendor" "$fixture/" || return 1
    # Unlisted commands must not be installed automatically.
    cp "$fixture/bin/unzipj" "$fixture/bin/aaa fixture"
    cp "$fixture/bin/unzipj" "$fixture/bin/zzz fixture"
}

run_install() (
    cd "$test_dir" || exit 1
    HOME="$test_home" "$fixture/install.sh" "$@" < /dev/null
)

assert_links() {
    local src dest
    dest="$test_home/.local/bin/unzipj"
    assertTrue "test -L '$dest'"
    assertEquals "$fixture/bin/unzipj" "$(readlink -- "$dest")"
    assertTrue "test -x '$dest'"
    for src in 'aaa fixture' 'zzz fixture'; do
        dest="$test_home/.local/bin/$src"
        assertFalse "test -e '$dest' || test -L '$dest'"
    done
    assertFalse "test -e '$test_home/.local/bin/link.sh' || test -L '$test_home/.local/bin/link.sh'"
    for src in "$fixture"/scripts/*; do
        dest="$test_home/.local/bin/${src##*/}"
        assertFalse "test -e '$dest' || test -L '$dest'"
    done
}

test_entry_point_creates_absolute_links_from_another_directory() {
    run_install > /dev/null 2>&1
    assertEquals 0 "$?"
    assert_links
}

test_rerun_skips_existing_links() {
    run_install > /dev/null 2>&1
    local before
    before=$(stat -c '%i:%Y:%Z' "$test_home/.local/bin/unzipj")
    run_install > "$test_dir/output" 2>&1
    assertEquals 0 "$?"
    assertEquals 1 "$(grep -c '^skip ' "$test_dir/output")"
    assertEquals "$before" "$(stat -c '%i:%Y:%Z' "$test_home/.local/bin/unzipj")"
    assert_links
}

test_dry_run_leaves_home_absent_even_with_quiet() {
    local option
    for option in --dry-run --quiet; do
        run_install --dry-run "$option" > "$test_dir/output" 2>&1
        assertEquals 0 "$?"
        assertFalse "test -e '$test_home'"
        assertEquals 1 "$(grep -c '^create ' "$test_dir/output")"
    done
}

test_dry_run_reports_existing_links() {
    run_install > /dev/null 2>&1
    run_install --dry-run > "$test_dir/output" 2>&1
    assertEquals 0 "$?"
    assertEquals 1 "$(grep -c '^skip ' "$test_dir/output")"
    assert_links
}

test_quiet_suppresses_creation_and_skip_messages() {
    local option
    for option in --quiet -q; do
        rm -rf -- "$test_home"
        run_install "$option" > "$test_dir/output" 2>&1
        assertEquals 0 "$?"
        assertFalse "test -s '$test_dir/output'"
        assert_links
        run_install "$option" > "$test_dir/output" 2>&1
        assertEquals 0 "$?"
        assertFalse "test -s '$test_dir/output'"
        assert_links
    done
}

assert_conflict_preserved() {
    local dest="$test_home/.local/bin/unzipj" option before
    # Explicitly declare commands before and after the conflicting destination.
    cat > "$fixture/bin/link.sh" <<'EOF'
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
dfl_link_add "$script_dir/aaa fixture" "$HOME/.local/bin/aaa fixture"
dfl_link_add "$script_dir/unzipj" "$HOME/.local/bin/unzipj"
dfl_link_add "$script_dir/zzz fixture" "$HOME/.local/bin/zzz fixture"
EOF
    cp -a "$dest" "$test_dir/expected"
    before=$(stat -c '%i:%Y:%Z' "$dest")
    for option in --dry-run '' --quiet; do
        if [[ -n $option ]]; then
            run_install "$option" > "$test_dir/output" 2>&1
        else
            run_install > "$test_dir/output" 2>&1
        fi
        assertNotEquals 0 "$?"
        if [[ $option == --dry-run ]]; then
            assertEquals 1 "$(grep -c '^conflict ' "$test_dir/output")"
        fi
        assertFalse "test -e '$test_home/.local/bin/aaa fixture' || test -L '$test_home/.local/bin/aaa fixture'"
        assertFalse "test -e '$test_home/.local/bin/zzz fixture' || test -L '$test_home/.local/bin/zzz fixture'"
        assertEquals "$before" "$(stat -c '%i:%Y:%Z' "$dest")"
        if [[ -L $dest ]]; then
            assertEquals "$(readlink -- "$test_dir/expected")" "$(readlink -- "$dest")"
        else
            diff -r -- "$test_dir/expected" "$dest"
            assertEquals 0 "$?"
        fi
    done
}

test_existing_file_prevents_all_links() {
    mkdir -p "$test_home/.local/bin"
    printf 'existing\n' > "$test_home/.local/bin/unzipj"
    assert_conflict_preserved
}

test_old_installed_copy_is_a_conflict() {
    mkdir -p "$test_home/.local/bin"
    cp "$fixture/bin/unzipj" "$test_home/.local/bin/unzipj"
    assert_conflict_preserved
}

test_existing_directory_is_a_conflict() {
    mkdir -p "$test_home/.local/bin/unzipj"
    printf 'existing\n' > "$test_home/.local/bin/unzipj/child"
    assert_conflict_preserved
}

test_different_link_is_a_conflict() {
    mkdir -p "$test_home/.local/bin"
    ln -s "$fixture/bin/aaa fixture" "$test_home/.local/bin/unzipj"
    assert_conflict_preserved
}

test_broken_link_is_a_conflict() {
    mkdir -p "$test_home/.local/bin"
    ln -s "$test_dir/missing" "$test_home/.local/bin/unzipj"
    assert_conflict_preserved
}

test_invalid_parent_is_preserved() {
    mkdir -p "$test_home/.local"
    printf 'blocked\n' > "$test_home/.local/bin"
    run_install --dry-run > /dev/null 2>&1
    assertNotEquals 0 "$?"
    run_install > /dev/null 2>&1
    assertNotEquals 0 "$?"
    assertEquals blocked "$(cat "$test_home/.local/bin")"
}

test_unknown_arguments_prevent_changes() {
    local argument
    for argument in --unknown unexpected; do
        run_install "$argument" > /dev/null 2>&1
        assertNotEquals 0 "$?"
        assertFalse "test -e '$test_home'"
    done
}

test_help_does_not_install() {
    run_install --help > "$test_dir/output" 2>&1
    assertEquals 0 "$?"
    assertEquals 1 "$(grep -c '^Usage:' "$test_dir/output")"
    assertFalse "test -e '$test_home'"
}

# shellcheck source=/dev/null
source "${SHUNIT2:-/usr/share/shunit2/shunit2}"
