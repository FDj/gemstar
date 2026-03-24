# Change Log

## 1.0.2

- General server performance improvements.
- Server: Required by / Requires / date added information now hidden in a "Details" section by default.
- Server: Improve color hilighting in gems list.
- Server: Improve up/down/left/right arrow key navigation.
- Fix problem not fetching new changelogs due to extraneous caching.
- Fix `nil.include?` error fetching changelogs for gems without either `homepage_uri` or `source_code_uri`.

## 1.0.1

- Added `--format markdown` to `gemstar diff` command. 

## 1.0

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
