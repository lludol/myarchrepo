# myarchrepo

I created this repo because the AUR can pose security risks and is not always reliable.

## Building Packages

Packages live in `src/<pkgname>/` with their `PKGBUILD`. Builds output `.pkg.tar.zst` files—**do not install locally**; let pacman handle via this repo.

**Build on the machine that has the build tools (e.g. `extra-x86_64-build`). On other machines, only sync (see below).**

### Build and sync (build machine)

```bash
./build.sh <pkgname>
```

This builds, updates the repo DB, and runs `sync.sh` to copy `x86_64/` to `/var/lib/pacman/sync/myarchrepo/`.

### Sync only (machines that don’t build)

After `git pull` (and `git lfs pull`):

```bash
./sync.sh
```

### Optional: systemd user timer (weekly pull + on login)

To have the repo updated automatically once per week (Monday 08:00) and shortly after you log in:

```bash
mkdir -p ~/.config/systemd/user
cp systemd-user/myarchrepo-pull.service systemd-user/myarchrepo-pull.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now myarchrepo-pull.timer
```

Check timer status: `systemctl --user list-timers myarchrepo-pull.timer`

If your repo is not at `~/myarchrepo`, edit `WorkingDirectory=` in `myarchrepo-pull.service` before copying.

## Using the Repo

Add to `/etc/pacman.conf`:

```
[myrepo]
SigLevel = Optional TrustAll
Server = file:///var/lib/pacman/sync/myarchrepo
```

Then:

```bash
sudo pacman -Syy     # Sync DB
sudo pacman -S <pkgname>  # Install
sudo pacman -Syu     # Upgrade all, including from repo
```

List AUR pkgs to migrate: `pacman -Qm`. Build them here instead.

## TODO

- [ ] Add a test-build step (Arch `base-devel` container) to verify PKGBUILDs before merging PRs
- [ ] Enable auto-merge on update PRs once test-build is in place

## Auto-update actions

| Package | Has action |
|---------|------------|
| amdgpu_top-tui-bin | ✅ |
| beekeeper-studio-bin | ✅ |
| catppuccin-cursors-latte | ✅ |
| catppuccin-cursors-macchiato | ✅ |
| catppuccin-gtk-theme-latte | ✅ |
| catppuccin-gtk-theme-macchiato | ✅ |
| cursor-bin | ✅ |
| elephant | ✅ |
| elephant-bluetooth | ✅ |
| elephant-calc | ✅ |
| elephant-clipboard | ✅ |
| elephant-desktopapplications | ✅ |
| elephant-files | ✅ |
| elephant-menus | ✅ |
| elephant-symbols | ✅ |
| elephant-unicode | ✅ |
| elephant-websearch | ✅ |
| fastmail | ✅ |
| mongodb-compass-bin | ✅ |
| overskride | ✅ |
| slack-desktop-wayland | ✅ |
| ticktick | ✅ |
| tradingview | ✅ |
| trezor-suite | ✅ |
| visual-studio-code-bin | ✅ |
| walker | ✅ |
| zoom | ✅ |
