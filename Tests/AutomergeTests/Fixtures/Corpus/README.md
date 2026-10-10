# Fixture corpus

Binary Automerge documents that the tests in `Tests/AutomergeTests/Corpus` load through the Swift API.
Every file here must have an expectation in those tests; a test fails if a file is added without one.

## `upstream/`

Copied unchanged from the Rust `automerge` crate, version 0.12.0 (the version in `rust/Cargo.toml`),
which is MIT licensed like this package:

- `upstream/fixtures/` from `rust/automerge/tests/fixtures`
- `upstream/fuzz-crashers/` from `rust/automerge/tests/fuzz-crashers`

In the Rust tests every fuzz crasher must fail to load. The fixtures cover LEB128 validation,
64-bit object ID counters, documents stored as more than one change chunk, and an invalid
zero-width mark.

When bumping the `automerge` crate, copy both directories from the new version's `tests/`
directory (for example `~/.cargo/registry/src/*/automerge-<version>/tests`), then add an
expectation for any new file to `UpstreamCorpusTests.swift`.
