# myarchrepo

I created this repo because the AUR can pose security risks and is not always reliable.

## Building Packages

Packages live in `src/<pkgname>/` with their `PKGBUILD`. Builds output `.pkg.tar.zst` files—**do not install locally**; let pacman handle via this repo.

### Build and Move to Repo

```bash
./build.sh <pkgname>
```

## Using the Repo
Add to `/etc/pacman.conf` (before other repos for priority):
```
[myrepo]
SigLevel = Optional TrustAll
Server = https://lludol.github.io/myarchrepo/x86_64/
```

### Install/Upgrade
```
sudo pacman -Syy     # Sync DB
sudo pacman -S <pkgname>  # Install
sudo pacman -Syu     # Upgrade all, including from repo
```

List AUR pkgs to migrate: `pacman -Qm`. Build them here instead.