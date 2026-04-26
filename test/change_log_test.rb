# frozen_string_literal: true

require "test_helper"

class ChangeLogTest < Minitest::Test
  class FakeMetadata
    def repo_uri(cache_only: false, force_refresh: false)
      "https://github.com/ddnexus/pagy"
    end

    def meta(cache_only: false, force_refresh: false)
      { "changelog_uri" => "https://ddnexus.github.io/pagy/changelog/" }
    end

    def changelog_source(repo_uri:, cache_only: false, force_refresh: false)
      {
        base: "https://raw.githubusercontent.com/ddnexus/pagy",
        paths: ["CHANGELOG.md"],
        branches: ["master"]
      }
    end
  end

  def test_explicit_changelog_uri_markdown_candidate_precedes_generic_repo_changelog
    candidates = Gemstar::ChangeLog.new(FakeMetadata.new).send(
      :changelog_uri_candidates,
      cache_only: false,
      force_refresh: false
    )

    assert_equal "https://ddnexus.github.io/pagy/changelog.md", candidates.first
    assert_operator candidates.index("https://ddnexus.github.io/pagy/changelog.md"),
      :<,
      candidates.index("https://raw.githubusercontent.com/ddnexus/pagy/master/CHANGELOG.md")
  end
end
