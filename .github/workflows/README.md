# Running workflows locally with act

Create a `.secrets` file in the repo root (it’s in `.gitignore`) with the variables your workflows need, for example:

```
SKIP_CREATE_PR=true
GH_API_TOKEN=ghp_your_token_here
```

On GitHub, the **Create Pull Request** step needs a Personal Access Token: the default `GITHUB_TOKEN` is not allowed to create or approve PRs. Add a repo secret `GH_API_TOKEN` (classic PAT with `repo` scope, or fine-grained with **Pull requests: Read and write**) for automated PR creation.

Then run a workflow with [act](https://github.com/nektos/act) (Docker required):

```bash
act workflow_dispatch -W .github/workflows/update-amdgpu_top-tui-bin.yml --secret-file .secrets
```
