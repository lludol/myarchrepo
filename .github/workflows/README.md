# Running workflows locally with act

Create a `.secrets` file in the repo root (it’s in `.gitignore`) with the variables your workflows need, for example:

```
SKIP_CREATE_PR=true
GH_API_TOKEN=ghp_your_token_here
```

Then run a workflow with [act](https://github.com/nektos/act) (Docker required):

```bash
act workflow_dispatch -W .github/workflows/update-amdgpu_top-tui-bin.yml --secret-file .secrets
```
