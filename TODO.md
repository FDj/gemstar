## Gemstar TODO
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
- Add... project in web ui
- bundle install, bundle update, etc.
- possibly add gem in web ui
- upgrade/downgrade/pin specific versions
