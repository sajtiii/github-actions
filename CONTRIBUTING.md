# Contributing

## Tests

The Test workflow runs `<action>/test/entrypoint.sh` for every top-level folder that has one, each as its own job.
The script runs with bash from the repository root and must exit non-zero on failure.

## Versioning

Callers pin to a major tag, like `@v1`. After a backwards-compatible change, move the tag:

```sh
git tag -f v1 && git push -f origin v1
```
