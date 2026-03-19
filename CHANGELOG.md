# Change Log

## TODO
### Diff
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

### Server
  - main UI as a single page app
    - title nav bar
      - has "Gemstar" logo in the top left
      - then a project popup menu with an Add... option at the bottom
      - then from/to git revision popups that can show worktree or git revisions of the Gemfile.lock
    - the main area as a master/detail view
      - toolbar with buttons and information at the top
          - bundle install, bundle update, etc.
        - left side nav is the list of used gems
            - gem name, version e.g. "2.2.0 -> 2.3.1"  
            - add gem option at bottom
        - for each gem, in the detail area:
            - at the top, basic information about the gem
            - links to various sites: rubygems, github, home page, in buttons, opening to new tabs
            - you can see the revisions, color coded to "what's new" in green
            - if a version downgrade was applied, that change would be red
            - for future versions (i.e. already released, but not yet in the repo), the change would be greyish with a dashed line outline
            - for each revision:
                - at the top right next to the revision number,
                - buttons to upgrade/downgrade specific gems,
  - for now, don't edit Gemfiles, so no specific updates/downgrades of gems yet,
    but `bundle update` could already be possible 
  - keyboard navigation for master/detail view 


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
