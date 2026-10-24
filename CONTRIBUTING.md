# Contributing

## Tests

The Test workflow runs `<action>/test/entrypoint.sh` for every top-level folder that has one, each as its own job.
The script runs with bash from the repository root and must exit non-zero on failure.

## Versioning

Callers pin to the major tag, like `@v1`.
Every release gets an exact `vX.Y.Z` tag, and the Release workflow moves the major tag to the newest one.

```sh
gh release create v1.2.0 --generate-notes
```

| Change                                                  | Release            |
|---------------------------------------------------------|--------------------|
| Bug fix                                                 | Patch, `v1.1.1`    |
| New action, input or output                             | Minor, `v1.2.0`    |
| Removed or renamed input or output, changed behaviour   | Major, `v2.0.0`    |

A major release creates a new major tag, `v1` stays on the last `v1.x.y`.
