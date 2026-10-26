# dependabot-auto-merge

Enables auto-merge on Dependabot pull requests whose update type is allowed.
GitHub then merges the pull request once the required checks pass.

## Usage

Copy [`example.yml`](example.yml) to `.github/workflows/dependabot-auto-merge.yml`.
The job `if` keeps the job from starting for other authors, the action checks the author too.

The job needs these permissions:

| Permission             | For                    |
|------------------------|------------------------|
| `contents: write`      | Merging                |
| `pull-requests: write` | Enabling auto-merge    |

The repository must allow auto-merge (Settings, General, Pull Requests) and `main` needs required status checks, otherwise the pull request merges right away or the call fails.

## Inputs

| Input          | Type                   | Default                                                            | Description                          |
|----------------|------------------------|--------------------------------------------------------------------|--------------------------------------|
| `update-types` | comma-separated list   | `version-update:semver-patch,version-update:semver-minor`          | Update types to auto-merge           |
| `merge-method` | choice: `merge`, `squash`, `rebase` | `merge`                                               | How the pull request is merged       |
| `github-token` | string                 | `github.token`                                                     | Token for the pull request           |

An invalid value fails the run.

## Outputs

| Output    | Description                                  |
|-----------|----------------------------------------------|
| `enabled` | `true` when auto-merge was enabled, else `false` |
