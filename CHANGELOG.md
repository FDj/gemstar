# Change Log

## TODO
- Diff:
    - Gems:
        - benchmark
        - brakeman
        - json (not using CHANGES.md?)
        - nio4r not using releases.md?
        - parser not using CHANGELOG.md?
        - actioncable-next uses release tag names?
        - paper_trail not using CHANGELOG.md?
        - playwright-ruby-client uses release tags?
    - bundler itself
    - use changelog files from installed gems where present
    - use 'gh' tool to fetch GitHub releases
    - support downgrading pinned gems, i.e. minitest 6.0 -> 5.x
    - read release notes from locally installed gems
    - for each gem, show why it's included (Gemfile or 2nd dependency)

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
