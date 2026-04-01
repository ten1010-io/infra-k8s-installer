#!/usr/bin/env sh
set -eu

script_dir="$0"
case "$script_dir" in
  */*) script_dir=${script_dir%/*} ;;
  *) script_dir="." ;;
esac
script_dir="$(cd "$script_dir" && pwd)"
allowlist="${ALLOWLIST_FILE:-$script_dir/using_metrics.txt}"

if [ ! -f "$allowlist" ]; then
  echo "Allowlist not found: $allowlist" >&2
  exit 2
fi

build_metrics_regex() {
  if command -v awk >/dev/null 2>&1; then
    awk 'NF && $1 !~ /^#/ {
      if (!seen[$1]++) {
        if (n++) printf "|"
        printf "%s", $1
      }
    } END { print "" }' "$allowlist"
    return
  fi

  metrics=""
  seen="|"
  while IFS= read -r line || [ -n "$line" ]; do
    set -- $line
    name="${1:-}"
    [ -z "$name" ] && continue
    case "$name" in
      \#*) continue ;;
    esac
    case "$seen" in
      *"|$name|"*) continue ;;
    esac
    if [ -n "$metrics" ]; then
      metrics="${metrics}|$name"
    else
      metrics="$name"
    fi
    seen="${seen}${name}|"
  done < "$allowlist"

  printf '%s\n' "$metrics"
}

if ! metrics_regex="$(build_metrics_regex)"; then
  echo "Failed to build allowlist regex: $allowlist" >&2
  exit 2
fi

if [ -z "$metrics_regex" ]; then
  echo "Allowlist is empty: $allowlist" >&2
  exit 2
fi

resolve_vmctl_bin() {
  if [ -n "${VMCTL_BIN:-}" ]; then
    if command -v "$VMCTL_BIN" >/dev/null 2>&1; then
      printf '%s\n' "$VMCTL_BIN"
      return 0
    fi
    if [ -x "$VMCTL_BIN" ]; then
      printf '%s\n' "$VMCTL_BIN"
      return 0
    fi
    echo "VMCTL_BIN is set but not found or not executable: $VMCTL_BIN" >&2
  fi

  if command -v vmctl >/dev/null 2>&1; then
    printf '%s\n' "vmctl"
    return 0
  fi

  for candidate in /vmctl-prod /vmctl ./vmctl-prod ./vmctl; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "vmctl binary not found. Set VMCTL_BIN to the full path." >&2
  return 2
}

if ! vmctl_bin="$(resolve_vmctl_bin)"; then
  exit 2
fi

snapshot_path="${SNAPSHOT_PATH:-}"
if [ -z "$snapshot_path" ]; then
  if [ -n "${SNAPSHOT_DIR:-}" ]; then
    snapshot_path="/mnt/prometheus-db/snapshots/${SNAPSHOT_DIR}"
  else
    snapshot_path="/mnt/prometheus-db/snapshots/{snapshot_dir}"
    case "$snapshot_path" in
      *"{"*|*"}"*)
        echo "snapshot_dir not provided. Set SNAPSHOT_DIR or SNAPSHOT_PATH." >&2
        exit 2
        ;;
    esac
  fi
fi

"$vmctl_bin" prometheus \
  --prom-snapshot "$snapshot_path" \
  --vm-addr="http://vmagent-vmstack-vmagent.aipub-promstack.svc:8429" \
  --prom-filter-label="__name__" \
  --prom-filter-label-value="^(${metrics_regex})$" \
  --prom-concurrency 2 \
  --vm-concurrency 3
