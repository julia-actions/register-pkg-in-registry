# register-pkg-in-registry

_A GitHub action to register Julia packages in custom (e.g. private) registries._

## Options

### Inputs

- `registry` (required): GitHub repository of the private registry (in the form `owner/repository`).
- `subdirectory` (optional): Subdirectory of the repository where the package lives.
  Defaults to `.`.
- `push` (optional): If `true`, push the branch to the registry. Defaults to `true`.
  - Defaults to `true`.
- `branch` (optional): If `inputs.push=true`, branch name where the registering package will be uploaded.
  - Defaults to the string returned by `RegistryTools.registration_branch`.
- `name` (optional): Name of the committing user.
  - Defaults to `${{ github.actor }}`.
- `email` (optional): Email of the committing user.
  - Defaults to `${{ github.actor_id }}+${{ github.actor }}@users.noreply.github.com`.

### Outputs

- `name`: Project name.
- `uuid`: Project UUID.
- `version`: Project version.
- `hash`: Tree hash of the registering package.
- `branch`: If `inputs.push=true`, branch where the registering package has been uploaded.
- `path`: Path to the locally cloned Git repository of the private registry.

## Example workflow

```yaml
name: Register Package

on:
  workflow_dispatch:

jobs:
  register:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: julia-actions/setup-julia@v3
      - uses: julia-actions/cache@v3
      - uses: julia-actions/register-pkg-in-registry@v0.4
        with:
          registry: YOUR_ORGANIZATION/YOUR_REGISTRY_REPO
        env:
          GITHUB_TOKEN: ${{ secrets.MY_PAT }}
```

## Requirements

`GITHUB_TOKEN` must be set to a token configured with _Contents_ and _Pull Requests_ write permissions on the registry repository, otherwise the workflow won't be able to push the branch to the registry repository.

If all your repositories (custom registry and the Julia packages) live within the same organisation, you can set up a [GitHub App](https://docs.github.com/en/apps/overview) to automatically generate an ephemeral token with the [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token) workflow:

```yaml
name: Register Package
on:
  workflow_dispatch:
jobs:
  register:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: julia-actions/setup-julia@v3
      - uses: julia-actions/cache@v3
      - uses: actions/create-github-app-token@v3
        id: generate_token
        with:
          client-id: "${{ secrets.APP_ID }}"
          private-key: "${{ secrets.APP_PRIVATE_KEY }}"
          permission-contents: "write"
          permission-pull-requests: "write"
          owner: YOUR_ORGANIZATION
          repositories: |
            YOUR_REGISTRY_REPO
      - uses: julia-actions/register-pkg-in-registry@v0.4
        with:
          registry: YOUR_ORGANIZATION/YOUR_REGISTRY_REPO
        env:
          GITHUB_TOKEN: ${{ steps.generate_token.outputs.token }}
```
