# Releasing Stay through Homebrew

This repository is the custom Homebrew tap for `nevdelap/stay`. A Homebrew
release is a formula update merged into this tap; it is not a source build and
there is no separate package-publishing job in this repository.

## What “do a release” means

When the user says **“do a release”**, Igor should:

1. Inspect the `nevdelap/stay` GitHub Releases page and identify the newest
   stable, non-draft release. Do not assume that the current formula version
   is still current, and do not select a prerelease unless the user asks for
   one.
2. Confirm that the release contains all four target archives and
   `SHA256SUMS`:

   - `stay-v<VERSION>-aarch64-apple-darwin.tar.gz`
   - `stay-v<VERSION>-x86_64-apple-darwin.tar.gz`
   - `stay-v<VERSION>-aarch64-unknown-linux-gnu.tar.gz`
   - `stay-v<VERSION>-x86_64-unknown-linux-gnu.tar.gz`

3. Read the checksums from the release’s `SHA256SUMS` file and verify the
   downloaded archives against it. Never invent or calculate a checksum from
   an archive that was not obtained from the selected release.
4. Update [`Formula/stay.rb`](../Formula/stay.rb): replace the version and
   the four platform-specific URLs and SHA-256 values. Preserve the `tmux`
   dependency, binary installation, and test behavior.
5. Update [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) with the
   same release version, four asset names, and four checksums. The formula and
   CI must refer to exactly the same release.
6. Run the checks that are available locally, inspect the diff, and leave a
   focused, PR-ready change. Do not push or merge unless the user explicitly
   asks for publication.
7. Report the selected release, asset/checksum verification, changed files,
   checks run, and the remaining user action. Normally the user must push the
   branch, open or update the pull request, and merge it into `main`.

If the newest stable release is already represented by the formula and CI,
report that no Homebrew release change is needed. If a required archive or
checksum is missing, stop before editing and report the upstream release
problem.

## Release discovery and verification

Use the GitHub release data for `nevdelap/stay`, rather than guessing from a
tag or from the version currently in this tap. The selected release should
have a tag of the form `v<VERSION>`. The formula uses `<VERSION>` in its
`version` output and uses the tag, including the leading `v`, in download
URLs.

Before editing, verify:

- the tag is the newest stable release;
- all four expected archive names exist;
- `SHA256SUMS` contains one entry for each expected archive;
- each checksum is a 64-character lowercase SHA-256 digest; and
- each archive contains the `stay` executable at the path expected by
  `bin.install "stay"`.

A temporary directory may be used for downloads. Remove only that temporary
directory after verification. Keep the release tag and the four verified
checksums in the work log or final report so the change can be audited.

## Local checks

The easiest way to run the host-side checks is from the repository root:

```sh
./scripts/check-homebrew-release.sh
```

The script prepares the local tap formula and runs the audit, style, fetch,
install/reinstall, and formula test checks below. It updates the local
Homebrew metadata and changes the local tap checkout; it does not change this
Git repository or publish anything. It mirrors the output to the terminal and
writes the complete result to the ignored file
`.homebrew-release-check.log`.

On NixOS, the script does not require a native Homebrew installation. If
`brew` is unavailable but `podman` or `docker` is present, it runs itself in
the small `ubuntu:26.04` container image. The container installs only the
required build tools and Homebrew prerequisites, then installs Homebrew as a
non-root user matching the host user. If needed, make Podman available for the
current shell with:

```sh
nix shell nixpkgs#podman
./scripts/check-homebrew-release.sh
```

This provides the Linux Homebrew check. GitHub Actions remains responsible for
the macOS and ARM64 jobs.

If Homebrew is available, run the equivalent of:

```sh
brew audit --strict --new --formula ./Formula/stay.rb
brew style --formula ./Formula/stay.rb
```

The exact tap-qualified commands used by CI are also useful after placing the
formula in a local tap:

```sh
brew fetch --force --retry nevdelap/stay/stay
brew install nevdelap/stay/stay
brew test nevdelap/stay/stay
```

The four-platform GitHub Actions workflow is the authoritative validation. It
tests macOS ARM64, macOS Intel, Linux ARM64, and Linux x86_64, checks release
archive checksums, and exercises the installed formula with tmux. A local
machine cannot replace the checks on architectures it does not run.

## User handoff after the change

The final response should state:

- the upstream release tag selected;
- whether all four assets and their checksums were verified;
- the files changed;
- local checks that passed or were unavailable; and
- what the user needs to do next: push the branch and open/merge the PR, or
  merge the already-open PR after CI passes.

Once the formula change is merged into `main`, users receive it through the
normal tap update flow:

```sh
brew update
brew upgrade nevdelap/stay/stay
```

The formula continues to install the upstream binary and the `tmux` runtime
dependency; it does not compile Stay from source.
