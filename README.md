# myarchrepo

I created this repo because the AUR can pose security risks and is not always reliable.

## Building Packages

Packages live in `src/<pkgname>/` with their `PKGBUILD`. Builds output ignored `.pkg.tar.zst` artifacts under `x86_64/`; the active repository is published to Cloudflare R2 rather than stored in Git or Git LFS.

**Build on the machine that has the build tools (e.g. `extra-x86_64-build`). Other machines consume the repository directly from R2.**

### Build one package

```bash
./build.sh <pkgname>
```

This builds the package and updates the local repository database. Run `./upload-r2.sh --prune` afterward to publish a standalone build.

To download the current databases, build every outdated package, publish to R2, and remove obsolete R2 package objects in one command:

```bash
./build-outdated.sh
```

Use `./build-outdated.sh --no-upload` when an R2 upload is not wanted. The `--debug` and `--no-upload` options can be combined.

### Publish to Cloudflare R2

The repository can be published to the `myarchrepo` R2 bucket and served through `https://repo.ll03.me`.

In the R2 bucket settings, connect `repo.ll03.me` under **Custom Domains** so package downloads are publicly readable over HTTPS. The S3 API endpoint remains authenticated and is used only for publishing.

Create an R2 API token with **Object Read & Write** permission limited to the `myarchrepo` bucket, then configure the AWS CLI profile used by the upload script:

```bash
aws configure --profile r2
```

Use `auto` as the region. Keep the R2 Access Key ID and Secret Access Key out of this repository.

Publish the current repository:

```bash
./upload-r2.sh
```

The script uploads only package archives referenced by `x86_64/myrepo.db.tar.zst`, followed by the repository databases. Historical package archives in `x86_64/` are not uploaded unless the current database references them. Objects already present with the same SHA-256 checksum are skipped.

After verifying an update, remove remote package archives that are no longer referenced by the current database:

```bash
./upload-r2.sh --prune
```

The `--prune` option only deletes remote `*.pkg.tar.zst`, `*.pkg.tar.xz`, and corresponding signature objects. It does not delete repository databases or unrelated bucket objects.

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
Server = https://repo.ll03.me/$arch
```

Then:

```bash
sudo pacman -Syy     # Sync DB
sudo pacman -S <pkgname>  # Install
sudo pacman -Syu     # Upgrade all, including from repo
```

Verify the public database directly if synchronization fails:

```bash
curl --fail --head https://repo.ll03.me/x86_64/myrepo.db
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
| chatgpt | ✅ |
| cursor-bin | ✅ |
| fastmail | ✅ |
| hermes-desktop | ✅ |
| overskride | ✅ |
| slack-desktop-wayland | ✅ |
| ticktick | ✅ |
| tradingview | ✅ |
| trezor-suite | ✅ |
| visual-studio-code-bin | ✅ |
| zoom | ✅ |
