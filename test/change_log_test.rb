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

  def test_rst_changelog_name_variations_are_default_candidates
    paths = Gemstar::ChangeLog::DEFAULT_CHANGELOG_PATHS

    assert_includes paths, "CHANGELOG.rst"
    assert_includes paths, "Changelog.rst"
    assert_includes paths, "ChangeLog.rst"
    assert_includes paths, "changes.rst"
    assert_includes paths, "History.rst"
  end

  def test_extensionless_changelog_uri_adds_rst_candidate
    candidates = Gemstar::ChangeLog.new(FakeMetadata.new).send(
      :changelog_uri_markdown_candidates,
      "https://example.com/changelog"
    )

    assert_includes candidates, "https://example.com/changelog.md"
    assert_includes candidates, "https://example.com/changelog.rst"
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

  def test_rst_version_headings_are_parsed
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    content = <<~RST
      Changelog
      =========

      45.0.4 - 2025-06-09
      ~~~~~~~~~~~~~~~~~~~

      * Fixed decrypting PKCS#8 files encrypted with SHA1-RC4.
    RST

    changelog.stub :content, content do
      sections = changelog.send(:parse_changelog_sections)

      assert_includes sections.keys, "45.0.4"
      section_text = sections["45.0.4"].flatten.join
      assert_includes section_text, "Fixed decrypting PKCS#8"
      refute_includes section_text, "~~~~~~~~~~~~~~~~~~~"
      refute_includes section_text, ".. _v45-0-3"
    end
  end

  def test_starting_with_version_headings_are_parsed
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    content = <<~TEXT
      + Starting with version 2.22, please use the GitHub UI to compare tags.

      + Version 2.21 (2021.11.06)
      - Much improved support for C11.
    TEXT

    changelog.stub :content, content do
      sections = changelog.send(:parse_changelog_sections)

      assert_includes sections.keys, "2.22"
      assert_includes sections["2.22"].flatten.join, "please use the GitHub UI"
    end
  end

  def test_sections_for_versions_matches_zero_padded_version_segments
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    content = <<~TEXT
      + Version 3.00 (2026.02.06)
      - No API changes / functionality changes.
    TEXT

    changelog.stub :content, content do
      sections = changelog.sections_for_versions(["3.0"])

      assert_includes sections.keys, "3.00"
      assert_includes sections["3.00"].flatten.join, "No API changes"
    end
  end
end
