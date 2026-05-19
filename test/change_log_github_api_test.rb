# frozen_string_literal: true

require "minitest/autorun"
require "json"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "gemstar/change_log"

class ChangeLogGithubApiTest < Minitest::Test
  class FakeMetadata
    def repo_uri(cache_only: false, force_refresh: false)
      "https://github.com/basecamp/lexxy"
    end

    def github_tag_matches?(_tag_name)
      true
    end
  end

  def test_github_release_api_body_is_parsed_as_release_section
    json = JSON.generate([
      {
        "tag_name" => "v0.9.12.beta",
        "name" => "v0.9.12.beta",
        "body" => "## What's Changed\n* Fix toolbar overflow in extensions"
      }
    ])

    sections = Gemstar::ChangeLog.new(FakeMetadata.new).send(:parse_github_api_releases, json)

    assert_equal ["0.9.12.beta"], sections.keys
    assert_includes sections["0.9.12.beta"].join, "Fix toolbar overflow"
  end

  def test_github_release_api_url_uses_owner_and_repo_only
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)

    assert_equal(
      "https://api.github.com/repos/basecamp/lexxy/releases",
      changelog.send(:github_releases_api_url, "https://github.com/basecamp/lexxy/releases")
    )
  end

  def test_specific_github_cli_release_is_opt_in_and_uses_release_body
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    calls = []
    changelog.define_singleton_method(:fetch_github_cli_release_json) do |repo_path, tag_name|
      calls << [repo_path, tag_name]
      JSON.generate(
        "tagName" => tag_name,
        "name" => tag_name,
        "body" => "* Notes from gh"
      )
    end
    original_fetch = Gemstar::Cache.method(:fetch)
    Gemstar::Cache.define_singleton_method(:fetch) do |_key, force: false, &block|
      block.call
    end

    sections = changelog.send(
      :parse_specific_github_release_pages,
      "https://github.com/basecamp/lexxy",
      "0.9.12.beta",
      cache_only: false,
      force_refresh: true,
      use_github_cli: true
    )

    assert_equal [["basecamp/lexxy", "0.9.12.beta"]], calls
    assert_equal ["## 0.9.12.beta\n", "* Notes from gh"], sections["0.9.12.beta"]
  ensure
    Gemstar::Cache.define_singleton_method(:fetch, original_fetch) if original_fetch
  end
end
