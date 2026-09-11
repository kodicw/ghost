# Ghost Persistence Integration Test
#
# Proves that:
#   1. Root filesystem is tmpfs (RAM-based, ephemeral)
#   2. Preservation bind mounts are active for declared directories
#   3. Data written to preserved paths survives a reboot
#   4. Data written to non-preserved paths is wiped on reboot
#
# Run with: nix build .#checks.x86_64-linux.persistence -L
#       or: just check-vm
{ self, pkgs, preservation }:

pkgs.testers.nixosTest {
  name = "ghost-persistence";

  nodes.ghost = { config, lib, ... }: {
    imports = [
      preservation.nixosModules.preservation
      self.nixosModules.core
      self.nixosModules.persistence
      self.nixosModules.monitoring
      self.nixosModules.networking
    ];

    # ── Simulate ghost's tmpfs-in-RAM root (mirrors hardware.nix) ──
    virtualisation.fileSystems."/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [ "defaults" "size=2G" "mode=755" ];
    };

    # Add a second disk for persistent storage
    virtualisation.emptyDiskImages = [ 512 ];

    # Mount the second disk as the persistent volume
    virtualisation.fileSystems."/persistent" = {
      device = "/dev/vdb";
      fsType = "ext4";
      autoFormat = true;
      neededForBoot = true;
    };

    # Match real hardware.nix — systemd initrd is required for
    # preservation's inInitrd bind mounts (/etc/ssh, /etc/machine-id)
    boot.initrd.systemd.enable = true;

    # Disable services that require real network/hardware
    services.tailscale.enable = lib.mkForce false;
  };

  testScript = ''
    ghost.start()
    ghost.wait_for_unit("multi-user.target")

    # ── 1. Root filesystem is tmpfs ──────────────────────────────
    with subtest("Root filesystem is tmpfs"):
        fstype = ghost.succeed("stat -f -c '%T' /").strip()
        assert fstype == "tmpfs", f"Expected root fstype 'tmpfs', got '{fstype}'"

    # ── 2. Persistent volume is mounted ─────────────────────────
    with subtest("Persistent volume is mounted"):
        ghost.succeed("mountpoint -q /persistent")

    # ── 3. Preservation bind mounts are active ──────────────────
    with subtest("Preservation bind mounts are active"):
        for path in ["/var/log", "/var/lib/nixos", "/var/lib/systemd", "/etc/ssh"]:
            ghost.succeed(f"mountpoint -q {path}")

    # ── 4. Data lands on persistent volume ──────────────────────
    with subtest("Data written to preserved path lands on disk"):
        ghost.succeed("echo 'PERSIST_OK_42' > /var/log/ghost-test-marker")
        ghost.succeed("grep 'PERSIST_OK_42' /persistent/var/log/ghost-test-marker")

    # ── 5. Write ephemeral data (should NOT survive reboot) ─────
    with subtest("Ephemeral data exists before reboot"):
        ghost.succeed("echo 'GONE_AFTER_REBOOT' > /root/ephemeral-file")
        ghost.succeed("test -f /root/ephemeral-file")

    # ── 6. Reboot ───────────────────────────────────────────────
    ghost.shutdown()
    ghost.start()
    ghost.wait_for_unit("multi-user.target")

    # ── 7. Persistent data survived ─────────────────────────────
    with subtest("Persistent data survived reboot"):
        ghost.succeed("grep 'PERSIST_OK_42' /var/log/ghost-test-marker")

    # ── 8. Ephemeral data is gone ───────────────────────────────
    with subtest("Ephemeral data was wiped by reboot"):
        ghost.fail("test -f /root/ephemeral-file")

    # ── 9. Root is still tmpfs after reboot ─────────────────────
    with subtest("Root is still tmpfs after reboot"):
        fstype = ghost.succeed("stat -f -c '%T' /").strip()
        assert fstype == "tmpfs", f"Root should still be tmpfs after reboot, got '{fstype}'"
  '';
}
