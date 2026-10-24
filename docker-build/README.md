# docker-build

Builds a Docker image, scans it with Trivy, pushes it and signs it with cosign.

## Usage

Copy [`example.yml`](example.yml) to `.github/workflows/docker.yml`.
It runs on pushes to `main`, pull requests, releases, manual runs and every night at 03:00.

The job needs these permissions:

| Permission             | For                                |
|------------------------|------------------------------------|
| `packages: write`      | Pushing the image                  |
| `pull-requests: write` | The Trivy comment on pull requests |
| `id-token: write`      | Signing                            |

## Inputs

| Input             | Type                   | Default                | Description                                         |
|-------------------|------------------------|------------------------|-----------------------------------------------------|
| `registry`        | choice: `ghcr`         | `ghcr`                 | Target registry                                     |
| `context`         | string                 | `.`                    | Build context                                       |
| `file`            | string                 | `<context>/Dockerfile` | Path to the Dockerfile                              |
| `platforms`       | comma-separated list   | the runner's platform  | Target platforms                                    |
| `build-args`      | newline-separated list |                        | Build arguments                                     |
| `push`            | boolean                | `true`                 | Push the image, see [Pushing](#pushing)             |
| `variant`         | string                 |                        | Matrix variant, see [Matrix builds](#matrix-builds) |
| `variant-default` | boolean                | `false`                | Give this variant the unsuffixed tags too           |

An invalid value fails the run before anything is built.

## Outputs

| Output            | Description                                          |
|-------------------|------------------------------------------------------|
| `image`           | Image name, for example `ghcr.io/owner/repo`         |
| `tags`            | Image tags, one per line                             |
| `digest`          | Image digest                                         |
| `vulnerabilities` | Number of Trivy findings, empty when the scan failed |
| `summary`         | JSON description of the run, see [Summary](#summary) |

## Tags

The image is `<registry>/<owner>/<repo>`.

| Tag                    | When                       |
|------------------------|----------------------------|
| `edge`                 | Push to the default branch |
| `pr-<number>`          | Pull request               |
| `vX.Y.Z`, `vX.Y`, `vX` | `vX.Y.Z` tag or release    |
| `latest`               | Release                    |
| `nightly`              | Scheduled or manual run    |

Every image gets max provenance and SBOM attestations.

## Pushing

The image is pushed when `push` is `true`, except:

- pull requests from forks, whose token can't write packages
- runs that no tag applies to, such as a push to a feature branch
- nightly builds with vulnerabilities, see [Nightly builds](#nightly-builds)

## Scanning

Before the real build, the image is built for one platform and scanned with Trivy for fixable `HIGH` and `CRITICAL` vulnerabilities.
A `.trivyignore.yaml` in the repository root is used when present.
The real build reuses the scanned layers.

Findings go to the job summary and, on pull requests from the same repository, to a PR comment.
They don't stop regular builds, the run gets a warning instead.

## Nightly builds

Scheduled and manual runs are nightly builds.
They skip the build cache and pull fresh base images, so they pick up base image and package updates.

When Trivy finds vulnerabilities, or the scan fails, the image is not pushed and the run fails.
The previous `nightly` image stays in place.

## Signing

Pushed images are signed with keyless [cosign](https://docs.sigstore.dev/cosign/overview/) signing, except on pull requests.
Without `id-token: write` the image is not signed, and the run gets a warning.

```sh
cosign verify ghcr.io/<owner>/<repo>:latest \
  --certificate-identity-regexp 'https://github.com/<owner>/<repo>/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Matrix builds

`variant` builds several versions of one image in a matrix.
Each variant's tags get a `-<variant>` suffix, it gets the variant name instead of `latest`,
and it has its own build cache and PR comment.
The variant with `variant-default: true` also gets the unsuffixed tags.

```yaml
    strategy:
      matrix:
        php: ["8.4", "8.5"]
    steps:
      - uses: actions/checkout@v7

      - uses: sajtiii/github-actions/docker-build@v1
        with:
          variant: php${{ matrix.php }}
          variant-default: ${{ matrix.php == '8.5' }}
          build-args: |
            PHP_VERSION=${{ matrix.php }}
```

A `v1.2.3` release pushes:

| Variant  | Tags                                                           |
|----------|----------------------------------------------------------------|
| `php8.4` | `v1.2.3-php8.4`, `v1.2-php8.4`, `v1-php8.4`, `php8.4`          |
| `php8.5` | the same with `-php8.5`, plus `v1.2.3`, `v1.2`, `v1`, `latest` |

## Summary

Each run ends with a summary in the job summary and in the `summary` output.
In a matrix, every variant has its own.

`result` is one of:

| Result    | Meaning                                               |
|-----------|-------------------------------------------------------|
| `pushed`  | Built and pushed                                      |
| `built`   | Built, not pushed                                     |
| `blocked` | Nightly build not pushed, Trivy found vulnerabilities |
| `failed`  | Something else failed                                 |

```json
{
  "result": "pushed",
  "variant": "php8.5",
  "image": "ghcr.io/sajtiii/docker-laravel",
  "registry": "ghcr",
  "event": "push",
  "ref": "refs/heads/main",
  "nightly": false,
  "build": {
    "context": ".",
    "file": "./Dockerfile",
    "platforms": ["linux/amd64", "linux/arm64"],
    "scan_platform": "linux/amd64",
    "qemu": true,
    "build_args": ["PHP_VERSION=8.5"],
    "cache_scope": "php8.5"
  },
  "push": { "requested": true, "enabled": true, "reason": "" },
  "tags": ["ghcr.io/sajtiii/docker-laravel:edge", "ghcr.io/sajtiii/docker-laravel:edge-php8.5"],
  "digest": "sha256:...",
  "trivy": { "outcome": "success", "severity": "HIGH,CRITICAL", "vulnerabilities": 0, "ignore_file": ".trivyignore.yaml" },
  "signature": { "signed": true, "reason": "", "rekor_log_index": 123456 }
}
```
