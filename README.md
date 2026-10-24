# github-actions

Shared GitHub Actions for my projects.

## docker-build

Builds a Docker image, scans it with Trivy and pushes it to a registry.

Copy [`docker-build/example.yml`](docker-build/example.yml) to `.github/workflows/docker.yml`.
It builds on pushes to `main`, pull requests, releases and every night, with the permissions the action needs:

- `packages: write` to push the image
- `pull-requests: write` to comment the Trivy report on pull requests
- `id-token: write` to sign the image

| Input             | Type                  | Default                     | Description                                       |
|-------------------|-----------------------|-----------------------------|---------------------------------------------------|
| `registry`        | choice: `ghcr`        | `ghcr`                      | Target registry. Supported: `ghcr`                |
| `context`         | string                | `.`                         | Build context                                     |
| `file`            | string                | `<context>/Dockerfile`      | Path to the Dockerfile                            |
| `platforms`       | list, comma-separated | runner's platform           | Target platforms, comma-separated                 |
| `build-args`      | list, one per line    |                             | Build arguments, newline-separated                |
| `push`            | boolean               | `true`                      | Push the image, see below                         |
| `variant`         | string, tag-safe      |                             | Matrix variant name, see below                    |
| `variant-default` | boolean               | `false`                     | The variant also gets the tags without the suffix |

Action inputs are untyped strings, so the action validates them before building:
booleans must be `true` or `false`, `registry` one of the listed values, and `variant` usable in a tag.

Outputs: `image`, `tags`, `digest`, `vulnerabilities` and `summary`.

The image is pushed when `push` is `true`, unless the run is a pull request from a fork
(its token can not write packages) or none of the tags below apply, like a manual run on a feature branch.

The image is pushed as `<registry>/<owner>/<repo>`, with these tags:

| Tag                    | When                       |
|------------------------|----------------------------|
| `edge`                 | Push to the default branch |
| `pr-<number>`          | Pull request               |
| `vX.Y.Z`, `vX.Y`, `vX` | `vX.Y.Z` tag or release    |
| `latest`               | Release                    |
| `nightly`              | Scheduled or manual run    |

Images are built with max provenance and SBOM attestations.
QEMU is set up when more than one platform is built, or one that differs from the runner's.

### Scanning and nightly builds

A single-platform image is built first and scanned with Trivy for fixable `HIGH` and `CRITICAL` vulnerabilities.
A `.trivyignore.yaml` in the working directory is used when it exists.
The findings land in the job summary and, on pull requests, in a comment (needs `pull-requests: write`, skipped for forks).
The final build reuses its layers.

- Regular builds are pushed even when Trivy finds vulnerabilities, the run gets a warning.
- Scheduled and manual (`workflow_dispatch`) runs are nightly builds. They skip the build cache and pull fresh base images.
  They are not pushed, and the run fails, when Trivy finds vulnerabilities or the scan itself fails.

### Summary

The `summary` output is a JSON description of the run, also shown as a table in the job summary.
In a matrix every variant runs in its own job, so each has its own summary.

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

`result` is `pushed`, `built` (not pushed), `blocked` (a nightly build with vulnerabilities) or `failed`.

### Signing

Pushed images are signed, except on pull requests, with [cosign](https://docs.sigstore.dev/cosign/overview/) keyless signing.
The job needs `id-token: write`, without it signing is skipped with a warning. To verify a signature:

```sh
cosign verify ghcr.io/<owner>/<repo>:latest \
  --certificate-identity-regexp 'https://github.com/<owner>/<repo>/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Matrix builds

Set `variant` to build several flavours of an image in a matrix.
Every tag gets a `-<variant>` suffix, `latest` becomes the variant name,
and each variant has its own build cache and PR comment.
The `variant-default` variant also gets the plain tags.

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

On a `v1.2.3` release this pushes `v1.2.3-php8.4`, `php8.4`, `v1.2.3-php8.5`, `php8.5`, `v1.2.3` and `latest`
(plus the `major` and `major.minor` tags).

## Tests

Every top-level folder with a `test/entrypoint.sh` is discovered by the Test workflow and run as its own matrix job.
The script is run with bash from the repository root and must exit non-zero on failure.

## Versioning

Callers pin to a major tag (`@v1`). After a backwards-compatible change, move it:

```sh
git tag -f v1 && git push -f origin v1
```
