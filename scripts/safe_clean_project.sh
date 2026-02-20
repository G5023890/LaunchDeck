#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/safe_clean_project.sh --dry-run
  ./scripts/safe_clean_project.sh --apply

Description:
  Safely finds and removes build caches/artifacts only inside the current project directory.
  Excludes .git via find -prune.
EOF
}

if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

MODE="${1:---dry-run}"
if [[ "$MODE" != "--dry-run" && "$MODE" != "--apply" ]]; then
  usage
  exit 1
fi

ROOT="$(pwd -P)"
if [[ "$ROOT" == "/" ]]; then
  echo "Refusing to run at filesystem root."
  exit 1
fi

TMP_RAW="$(mktemp "${TMPDIR:-/tmp}/safe-clean-raw.XXXXXX")"
TMP_LIST="$(mktemp "${TMPDIR:-/tmp}/safe-clean-list.XXXXXX")"
trap 'rm -f "$TMP_RAW" "$TMP_LIST"' EXIT

humanize_kb() {
  awk -v kb="$1" 'BEGIN {
    split("KB MB GB TB", u, " ");
    i = 1; v = kb + 0;
    while (v >= 1024 && i < 4) { v = v / 1024; i++ }
    printf "%.2f %s", v, u[i];
  }'
}

is_go_build_bin_dir() {
  local dir="$1"
  local parent
  parent="$(dirname "$dir")"

  if [[ ! -f "$ROOT/go.mod" && ! -f "$parent/go.mod" ]]; then
    return 1
  fi

  local has_entries=0
  local has_source=0
  local has_executable=0
  local item

  while IFS= read -r -d '' item; do
    has_entries=1
    case "$item" in
      *.go|*.sh|*.py|*.rb|*.js|*.ts|*.swift|*.c|*.cc|*.cpp|*.h|*.hpp)
        has_source=1
        ;;
    esac
    if [[ -f "$item" && -x "$item" ]]; then
      has_executable=1
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 2 -print0)

  [[ "$has_entries" -eq 1 && "$has_source" -eq 0 && "$has_executable" -eq 1 ]]
}

collect_standard_targets() {
  find "$ROOT" \
    -type d -name .git -prune -o \
    \( -type d \( \
      -name node_modules -o \
      -name dist -o \
      -name build -o \
      -name .cache -o \
      -name tmp -o \
      -name .tmp -o \
      -name .build -o \
      -name DerivedData -o \
      -name __pycache__ -o \
      -name .pytest_cache -o \
      -name .mypy_cache -o \
      -name target -o \
      -name pkg -o \
      -name CMakeFiles -o \
      -name .codex -o \
      -name .agent -o \
      -name xcuserdata \
    \) -print \) -o \
    \( -type f \( \
      -name '*.log' -o \
      -name '.DS_Store' -o \
      -name '*.xcuserstate' -o \
      -name '*.pyc' -o \
      -name 'CMakeCache.txt' \
    \) -print \)
}

collect_standard_targets >> "$TMP_RAW"

while IFS= read -r bin_dir; do
  if is_go_build_bin_dir "$bin_dir"; then
    echo "$bin_dir" >> "$TMP_RAW"
  fi
done < <(
  find "$ROOT" \
    -type d -name .git -prune -o \
    -type d -name bin -print
)

sort -u "$TMP_RAW" > "$TMP_LIST"

project_before_kb="$(du -sk "$ROOT" | awk '{print $1}')"
project_before_h="$(du -sh "$ROOT" | awk '{print $1}')"

total_delete_kb=0
count=0

echo "Project root: $ROOT"
echo "Project size: $project_before_h"
echo
echo "Dry-run candidates:"

if [[ ! -s "$TMP_LIST" ]]; then
  echo "  (nothing to delete)"
  echo
  echo "Total to delete: 0.00 KB"
  exit 0
fi

while IFS= read -r target; do
  [[ -e "$target" ]] || continue
  case "$target" in
    "$ROOT"/*) ;;
    *)
      continue
      ;;
  esac
  case "$target" in
    "$ROOT/.git"/*|"$ROOT/.git")
      continue
      ;;
  esac

  size_kb="$(du -sk "$target" | awk '{print $1}')"
  size_h="$(du -sh "$target" | awk '{print $1}')"
  rel="${target#$ROOT/}"
  printf "  %10s  %s\n" "$size_h" "$rel"
  total_delete_kb=$((total_delete_kb + size_kb))
  count=$((count + 1))
done < "$TMP_LIST"

echo
echo "Candidates count: $count"
echo "Total to delete: $(humanize_kb "$total_delete_kb")"

if [[ "$MODE" == "--dry-run" ]]; then
  echo
  echo "Dry-run only. No files were deleted."
  echo "Run with --apply to delete after interactive confirmation."
  exit 0
fi

echo
printf "Type YES to delete listed items: "
read -r confirm
if [[ "$confirm" != "YES" ]]; then
  echo "Cancelled. Nothing deleted."
  exit 0
fi

while IFS= read -r target; do
  [[ -e "$target" ]] || continue
  case "$target" in
    "$ROOT"/*) ;;
    *)
      continue
      ;;
  esac
  case "$target" in
    "$ROOT/.git"/*|"$ROOT/.git")
      continue
      ;;
  esac

  if [[ -d "$target" ]]; then
    rm -rf -- "$target"
  else
    rm -f -- "$target"
  fi
done < "$TMP_LIST"

project_after_kb="$(du -sk "$ROOT" | awk '{print $1}')"
project_after_h="$(du -sh "$ROOT" | awk '{print $1}')"
freed_kb=$((project_before_kb - project_after_kb))
if [[ "$freed_kb" -lt 0 ]]; then
  freed_kb=0
fi

echo
echo "Cleanup complete."
echo "Project size now: $project_after_h"
echo "Freed space: $(humanize_kb "$freed_kb")"
