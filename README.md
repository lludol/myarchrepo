# myarchrepo

I created this repo because the AUR can pose security risks and is not always reliable.

## Building Packages

Packages live in `src/<pkgname>/` with their `PKGBUILD`. Builds output `.pkg.tar.zst` files—**do not install locally**; let pacman handle via this repo.

### Build and Move to Repo

```bash
./build.sh <pkgname>
```

## Update Repo Database

```bash
repo-add x86_64/myrepo.db.tar.zst x86_64/*.pkg.tar.zst
git add . && git commit -m "feat(pkg) <pkgname> added/updated" && git push
```

## Using the Repo
Add to `/etc/pacman.conf` (before other repos for priority):
```
[myrepo]
SigLevel = Optional TrustAll
Server = https://raw.githubusercontent.com/lludol/myarchrepo/main/x86_64/
```

### Install/Upgrade
```
sudo pacman -Syy     # Sync DB
sudo pacman -S <pkgname>  # Install
sudo pacman -Syu     # Upgrade all, including from repo
```

List AUR pkgs to migrate: `pacman -Qm`. Build them here instead.