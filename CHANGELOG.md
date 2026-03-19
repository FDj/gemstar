# Change Log

## Unreleased

- Added `gemstar server`, your interactive Gemfile.lock explorer and more.
- Default location for `diff` is now a tmp file.
- Removed Railtie from this gem.
- Improve how git root dir is determined.


## 0.0.2

- Diff: Fix regex warnings shown in terminal.
- Diff: Simplify and fix change log section parsing.

## 0.0.1

- Initial release
- Add GEMSTAR_DEBUG_GEM_REGEX to debug specific gems.
- Refactor to work correctly with more gems.
- Diff: More flexible changelog parsing.
- Diff: Fetch raw GitHub changelogs, not html.
- Diff: Support GitHub releases.
- Diff: Improved Markup rendering (with code samples)
- Diff: Try release notes in order of match frequency.
