# Fixture corpus

Binary Automerge documents that the tests in `Tests/AutomergeTests/Corpus` load through the Swift API.
Every file here must have an expectation in those tests; a test fails if a file is added without one.

## `golden/`

Documents built with the Swift API by the recipes in `GoldenRecipes.swift`: scalars (including the
edges of each numeric range, NaN and the infinities), nested objects, text with marks, merged
conflicts, and a commit history. Each recipe pins its actors and change timestamps, so it builds the
same bytes every time. Each `<name>.automerge` is the saved document, and `<name>.json` is a typed dump
of its contents and history, in the format described in `CorpusDump.swift`.

The tests check both directions: the checked-in bytes must still load to the expected dump, and
building each recipe today must still save to the checked-in bytes.

Don't edit an existing recipe; the checked-in bytes stand in for documents saved by earlier versions.
Add a new recipe, then write its files with:

```bash
AUTOMERGE_UPDATE_CORPUS=1 swift test --filter GoldenCorpusTests
```

and review the diff before committing. The same command regenerates every file after an intended
format change.

## `interop/`

- `exemplar` is `interop/exemplar` from the `automerge/automerge` repository, a document made by
  another implementation.
- `exemplar.export.json` is the output of `automerge export exemplar` from the Rust CLI, as given in
  that repository's `interop/README.md`, reformatted the way `JSONEncoder` writes it with the values
  unchanged. It's the one expected output here that comes from another implementation rather than
  from this package, so the regeneration command leaves it alone.
- `exemplar.json` is the typed dump, written by the regeneration command above.

## `upstream/`

Copied unchanged from the Rust `automerge` crate, version 0.7.2 (the version in `rust/Cargo.toml`),
which is MIT licensed like this package:

- `upstream/fixtures/` from `rust/automerge/tests/fixtures`
- `upstream/fuzz-crashers/` from `rust/automerge/tests/fuzz-crashers`

In the Rust tests every fuzz crasher must fail to load. The fixtures cover LEB128 validation,
64-bit object ID counters, and documents stored as more than one change chunk.

When bumping the `automerge` crate, copy both directories from the new version's `tests/`
directory (for example `~/.cargo/registry/src/*/automerge-<version>/tests`), then add an
expectation for any new file to `UpstreamCorpusTests.swift`.
