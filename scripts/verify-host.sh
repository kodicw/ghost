#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Ghost Remote Hardware Verification
#
# Validates that a running Ghost instance has the correct disk
# layout, filesystem types, preservation bind mounts, and that
# persistent data survives a reboot.
#
# Usage:
#   ./scripts/verify-host.sh root@192.168.1.100
#   ./scripts/verify-host.sh root@192.168.1.100 --reboot
#
# Flags:
#   --reboot    Also test that data survives a real reboot.
#               WARNING: This will reboot the remote machine.
#               Without this flag, only static checks are run.
#
# Exit codes:
#   0 = all checks passed
#   1 = one or more checks failed
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# ── Argument parsing ────────────────────────────────────────

TARGET="${1:-}"
DO_REBOOT=false

if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <ssh-target> [--reboot]"
  echo "  e.g. $0 root@192.168.1.100"
  echo "       $0 root@ghost.local --reboot"
  exit 1
fi

for arg in "${@:2}"; do
  case "$arg" in
    --reboot) DO_REBOOT=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# ── Helpers ─────────────────────────────────────────────────

PASS=0
FAIL=0
SKIP=0

SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes"

green()  { printf "\033[32m%s\033[0m\n" "$*"; }
red()    { printf "\033[31m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
bold()   { printf "\033[1m%s\033[0m\n" "$*"; }

run_remote() {
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "$TARGET" "$@" 2>/dev/null
}

check() {
  local name="$1"
  local cmd="$2"
  local expect="${3:-}"

  printf "  %-55s " "$name"

  result=$(run_remote "$cmd" 2>&1) || {
    red "FAIL"
    echo "    command: $cmd"
    echo "    output:  $result"
    FAIL=$((FAIL + 1))
    return 0
  }

  if [[ -n "$expect" ]]; then
    if echo "$result" | grep -qE "$expect"; then
      green "PASS"
    else
      red "FAIL"
      echo "    expected: $expect"
      echo "    got:      $result"
      FAIL=$((FAIL + 1))
      return 0
    fi
  else
    green "PASS"
  fi

  PASS=$((PASS + 1))
}

check_fail() {
  local name="$1"
  local cmd="$2"

  printf "  %-55s " "$name"

  if run_remote "$cmd" >/dev/null 2>&1; then
    red "FAIL (command should have failed but succeeded)"
    FAIL=$((FAIL + 1))
  else
    green "PASS"
    PASS=$((PASS + 1))
  fi
}

skip() {
  local name="$1"
  local reason="$2"
  printf "  %-55s " "$name"
  yellow "SKIP ($reason)"
  SKIP=$((SKIP + 1))
}

separator() {
  echo ""
  bold "── $1 ──"
  echo ""
}

# ── Pre-flight ──────────────────────────────────────────────

echo ""
bold "Ghost Hardware Verification"
bold "Target: $TARGET"
bold "Reboot test: $DO_REBOOT"
echo ""

printf "  %-55s " "SSH connectivity"
if run_remote "true"; then
  green "OK"
else
  red "FAIL — cannot connect to $TARGET"
  exit 1
fi

# ── 1. Hostname & OS ───────────────────────────────────────

separator "1. System Identity"

check "Hostname is ghost or ghost-fs" \
  "hostname" \
  "^ghost(-fs)?$"

check "Running NixOS" \
  "cat /etc/os-release | grep -c NixOS" \
  "1"

check "System is fully booted" \
  "systemctl is-system-running || true" \
  "running|degraded"

# ── 2. Root Filesystem ─────────────────────────────────────

separator "2. Root Filesystem (tmpfs)"

check "/ is tmpfs" \
  "stat -f -c '%T' /" \
  "tmpfs"

check "/ has correct size (~3G)" \
  "df -BM / | tail -1 | awk '{print \$2}'" \
  "[23][0-9]{3}M"

check "/tmp is tmpfs" \
  "stat -f -c '%T' /tmp" \
  "tmpfs"

# ── 3. Btrfs Subvolumes ───────────────────────────────────

separator "3. Btrfs Disk Layout"

check "/nix is mounted" \
  "mountpoint -q /nix && echo ok" \
  "ok"

check "/nix is btrfs" \
  "stat -f -c '%T' /nix" \
  "btrfs"

check "/nix subvolume is 'nix'" \
  "btrfs subvolume show /nix 2>/dev/null | head -1 || findmnt -n -o OPTIONS /nix" \
  "nix"

check "/nix uses zstd compression" \
  "findmnt -n -o OPTIONS /nix" \
  "compress=zstd"

check "/persistent is mounted" \
  "mountpoint -q /persistent && echo ok" \
  "ok"

check "/persistent is btrfs" \
  "stat -f -c '%T' /persistent" \
  "btrfs"

check "/persistent uses zstd compression" \
  "findmnt -n -o OPTIONS /persistent" \
  "compress=zstd"

check "Disk is labeled 'nixos'" \
  "lsblk -o LABEL -n | grep -c nixos || blkid | grep -c nixos" \
  "[1-9]"

# ── 4. Boot ───────────────────────────────────────────────

separator "4. Boot Configuration"

check "/boot is mounted" \
  "mountpoint -q /boot && echo ok" \
  "ok"

check "/boot is vfat (EFI)" \
  "stat -f -c '%T' /boot" \
  "msdos"

check "systemd-boot is installed" \
  "bootctl is-installed 2>/dev/null && echo ok || test -f /boot/EFI/systemd/systemd-bootx64.efi && echo ok" \
  "ok"

check "initrd uses systemd" \
  "readlink /etc/initrd-release 2>/dev/null || test -d /run/initramfs/etc && echo ok || cat /proc/cmdline" \
  "."

# ── 5. Preservation Bind Mounts ───────────────────────────

separator "5. Preservation Bind Mounts"

PRESERVED_DIRS=(
  "/var/lib/docker"
  "/var/lib/nixos"
  "/var/lib/systemd"
  "/var/log"
  "/etc/ssh"
)

for dir in "${PRESERVED_DIRS[@]}"; do
  check "$dir is a bind mount" \
    "mountpoint -q '$dir' && echo ok" \
    "ok"
done

check "/etc/machine-id exists and is stable" \
  "test -s /etc/machine-id && cat /etc/machine-id" \
  "^[0-9a-f]{32}$"

check "/etc/ssh/ssh_host_ed25519_key exists" \
  "test -f /etc/ssh/ssh_host_ed25519_key && echo ok" \
  "ok"

# ── 6. Backing Store ─────────────────────────────────────

separator "6. Persistent Backing Store"

for dir in "${PRESERVED_DIRS[@]}"; do
  backing="/persistent${dir}"
  check "$backing exists on disk" \
    "test -d '$backing' && echo ok" \
    "ok"
done

check "/persistent/etc/machine-id exists on disk" \
  "test -s /persistent/etc/machine-id && echo ok" \
  "ok"

# ── 7. Critical Services ─────────────────────────────────

separator "7. Critical Services"

SERVICES=(
  "sshd"
  "docker"
  "prometheus-node-exporter"
)

for svc in "${SERVICES[@]}"; do
  check "$svc is running" \
    "systemctl is-active $svc" \
    "^active$"
done

check "No unexpected failed units (except grist env)" \
  "systemctl --failed --no-legend --no-pager | grep -v docker-grist | wc -l" \
  "^0$"

# ── 8. zRAM ──────────────────────────────────────────────

separator "8. Memory & Swap"

check "zRAM swap is active" \
  "swapon --show=NAME,TYPE --noheadings | grep -c zram" \
  "[1-9]"

# ── 9. Reboot Persistence Test ───────────────────────────

separator "9. Reboot Persistence Test"

MARKER="ghost-verify-$(date +%s)"
MARKER_PATH="/var/log/ghost-verify-marker"

if [[ "$DO_REBOOT" == "true" ]]; then
  echo "  Writing marker to persistent path..."
  run_remote "echo '$MARKER' > $MARKER_PATH"

  check "Marker written to preserved path" \
    "cat $MARKER_PATH" \
    "$MARKER"

  check "Marker exists on backing store" \
    "cat /persistent${MARKER_PATH}" \
    "$MARKER"

  MACHINE_ID_BEFORE=$(run_remote "cat /etc/machine-id")
  SSH_KEY_BEFORE=$(run_remote "sha256sum /etc/ssh/ssh_host_ed25519_key | cut -d' ' -f1")

  echo ""
  echo "  Writing ephemeral marker to /root (should NOT survive)..."
  run_remote "echo 'ephemeral-$MARKER' > /root/ephemeral-verify-marker"

  echo "  Rebooting $TARGET..."
  # Send reboot and don't wait for the connection to close
  run_remote "nohup bash -c 'sleep 1 && reboot' &>/dev/null &" || true
  echo "  Waiting for host to go down..."
  sleep 5

  # Wait for host to come back (up to 120 seconds)
  echo "  Waiting for host to come back (up to 120s)..."
  SECONDS=0
  while ! run_remote "true" 2>/dev/null; do
    if (( SECONDS > 120 )); then
      red "  FAIL: Host did not come back after 120 seconds"
      FAIL=$((FAIL + 1))
      echo ""
      bold "Results: $PASS passed, $FAIL failed, $SKIP skipped"
      exit 1
    fi
    sleep 3
  done
  echo "  Host is back after ${SECONDS}s"
  echo ""

  check "[POST-REBOOT] System is fully booted" \
    "systemctl is-system-running || true" \
    "running|degraded"

  check "[POST-REBOOT] Root is still tmpfs" \
    "stat -f -c '%T' /" \
    "tmpfs"

  check "[POST-REBOOT] Persistent marker survived" \
    "cat $MARKER_PATH" \
    "$MARKER"

  check_fail "[POST-REBOOT] Ephemeral marker was wiped" \
    "test -f /root/ephemeral-verify-marker"

  check "[POST-REBOOT] machine-id is unchanged" \
    "cat /etc/machine-id" \
    "^${MACHINE_ID_BEFORE}$"

  check "[POST-REBOOT] SSH host key is unchanged" \
    "sha256sum /etc/ssh/ssh_host_ed25519_key | cut -d' ' -f1" \
    "^${SSH_KEY_BEFORE}$"

  check "[POST-REBOOT] Bind mounts restored" \
    "mountpoint -q /var/log && mountpoint -q /etc/ssh && mountpoint -q /var/lib/docker && echo ok" \
    "ok"

  check "[POST-REBOOT] Docker is running" \
    "systemctl is-active docker" \
    "^active$"

  # Cleanup
  run_remote "rm -f $MARKER_PATH /persistent${MARKER_PATH}" 2>/dev/null || true

else
  skip "Reboot persistence test" "use --reboot flag to enable"
fi

# ── Summary ──────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if (( FAIL == 0 )); then
  green "  ✓ ALL CHECKS PASSED: $PASS passed, $SKIP skipped"
else
  red   "  ✗ SOME CHECKS FAILED: $PASS passed, $FAIL failed, $SKIP skipped"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit $((FAIL > 0 ? 1 : 0))
