# Change Log

## 1.0.4

- Server: Improve layout, detail panel state management, and initial gem selection
- Server: Gem details now in collapsible panel
- Server: Arrow left/right navigation improved
- Enhance changelog parsing with GitHub tag and release support
- Extend `LockFile` with dependency requirements, spec sources, and platform parsing
- Refactor dependency processing to include platform and source details
- Refactor changelog parsing to merge GitHub release and changelog sections

## 1.0.3

- Load our own WEBrick to avoid conflicts with hosting puma.rb etc.

## 1.0.2

- General server performance improvements.
- Server: Required by / Requires / date added information now hidden in a "Details" section by default.
- Server: Improve color hilighting in gems list.
- Server: Improve up/down/left/right arrow key navigation.
- Fix problem not fetching new changelogs due to extraneous caching.
- Fix `nil.include?` error fetching changelogs for gems without either `homepage_uri` or `source_code_uri`.
- Add gem-release as a development dependency. 

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
