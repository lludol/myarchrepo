# Running workflows locally with act

Create a `.secrets` file in the repo root (it’s in `.gitignore`) with the variables your workflows need, for example:

```
SKIP_CREATE_PR=true
GH_API_TOKEN=ghp_your_token_here
```

Workflows commit and push to the default branch. The default `GITHUB_TOKEN` is usually enough. If `main` is protected, add a repo secret `GH_API_TOKEN` (classic PAT with `repo` scope, or fine-grained with **Contents: Read and write**) so checkout and push use that token instead.

Then run a workflow with [act](https://github.com/nektos/act) (Docker required):

```bash
act workflow_dispatch -W .github/workflows/update-amdgpu_top-tui-bin.yml --secret-file .secrets
```

## hermes-desktop updater

The updater takes the package version from stable semver release tags such as
`v0.21.7`. Legacy date tags such as `v2026.9.24` use the version in
`pyproject.toml`; modern releases may leave that file at `0.0.0`.
Electron comes from `apps/desktop/package.json`'s `devDependencies.electron`,
falling back to `build.electronVersion` when the modern field is absent or null.
Versions must be exact numeric `major.minor.patch` values, without ranges or
prerelease suffixes. Invalid metadata fails with an explicit error. Older package
versions are skipped; an unchanged version and tag is also skipped.

Archive root and required-file checks, source/header SHA-256 checksums, and the
Electron major guard remain enforced. A major change requires manually updating
the dependency, launcher, and `electronDist` path.

Run the offline regression tests with Python 3, PyYAML, Bash, and jq installed:

```bash
export TMPDIR="${TMPDIR:-/tmp}"
python3 -B tests/test_hermes_desktop_updater.py
```

The tests execute the workflow's actual metadata, headers, and PKGBUILD-update
shell blocks against fixture network responses and a temporary PKGBUILD copy.
All test files live under `TMPDIR`; no credentials, build, commit, or push are used.
