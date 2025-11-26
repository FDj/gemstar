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
    - support ```ruby ```

## Unreleased

- Diff: Fix regex warnings shown in terminal.

## 0.0.1

- Initial release
- Add GEMSTAR_DEBUG_GEM_REGEX to debug specific gems.
- Refactor to work correctly with more gems.
- Diff: More flexible changelog parsing.
- Diff: Fetch raw GitHub changelogs, not html.
- Diff: Support GitHub releases.
- Diff: Improved Markup rendering (with code samples)
- Diff: Try release notes in order of match frequency.
