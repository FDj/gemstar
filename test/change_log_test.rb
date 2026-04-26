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

  class AwsMetadata < FakeMetadata
    def repo_uri(cache_only: false, force_refresh: false)
      "https://github.com/aws/aws-sdk-ruby"
    end

    def meta(cache_only: false, force_refresh: false)
      {
        "changelog_uri" => "https://github.com/aws/aws-sdk-ruby/tree/version-3/gems/aws-partitions/CHANGELOG.md"
      }
    end

    def changelog_source(repo_uri:, cache_only: false, force_refresh: false)
      {
        base: "https://raw.githubusercontent.com/aws/aws-sdk-ruby/refs/heads/version-3/gems/aws-partitions",
        paths: ["CHANGELOG.md"],
        branches: [""]
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

  def test_github_tag_dates_are_extracted_from_tag_history
    html = <<~HTML
      <div>
        <a href="/ddnexus/pagy/releases/tag/43.5.2">43.5.2</a>
        <relative-time datetime="2026-04-24T07:02:29Z">Apr 24, 2026</relative-time>
      </div>
    HTML

    dates, next_url = Gemstar::ChangeLog.new(FakeMetadata.new).send(
      :parse_single_github_tag_dates_page,
      html,
      "https://github.com/ddnexus/pagy"
    )

    assert_nil next_url
    assert_equal({ "43.5.2" => "Apr 24, 2026" }, dates)
  end

  def test_github_tree_file_changelog_uri_is_converted_to_raw
    candidates = Gemstar::ChangeLog.new(AwsMetadata.new).send(
      :changelog_uri_candidates,
      cache_only: false,
      force_refresh: false
    )

    assert_equal "https://raw.githubusercontent.com/aws/aws-sdk-ruby/version-3/gems/aws-partitions/CHANGELOG.md", candidates.first
  end

  def test_changelog_heading_dates_do_not_shift_date_only_values
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)

    assert_equal "Apr 24, 2026", changelog.send(:extract_release_date_from_heading, "1.1241.0 (2026-04-24)")
  end

  def test_changelog_sections_are_authoritative_when_present
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)

    assert_equal({ "1.0.0" => ["notes"] }, changelog.send(:merge_section_sources, { "1.0.0" => ["notes"] }, { "2.0.0" => ["repo release"] }))
  end
end
