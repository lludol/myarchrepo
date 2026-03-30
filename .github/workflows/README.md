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
