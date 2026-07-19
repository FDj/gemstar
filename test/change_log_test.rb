# frozen_string_literal: true

require "test_helper"

class ChangeLogTest < Minitest::Test
  class FakeMetadata
    def gem_name
      "fake"
    end

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

  class ParserMetadata < FakeMetadata
    def repo_uri(cache_only: false, force_refresh: false)
      "https://github.com/whitequark/parser"
    end

    def meta(cache_only: false, force_refresh: false)
      {
        "version" => "3.3.12.0",
        "changelog_uri" => "https://github.com/whitequark/parser/blob/v3.3.12.0/CHANGELOG.md"
      }
    end

    def changelog_source(repo_uri:, cache_only: false, force_refresh: false)
      {
        base: "https://raw.githubusercontent.com/whitequark/parser",
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

  def test_rst_changelog_name_variations_are_default_candidates
    paths = Gemstar::ChangeLog::DEFAULT_CHANGELOG_PATHS

    assert_includes paths, "CHANGELOG"
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

  def test_extensionless_github_changelog_uri_keeps_exact_file_candidate
    candidates = Gemstar::ChangeLog.new(FakeMetadata.new).send(
      :changelog_uri_markdown_candidates,
      "https://github.com/SeleniumHQ/selenium/blob/trunk/rb/CHANGES"
    )

    assert_equal "https://raw.githubusercontent.com/SeleniumHQ/selenium/trunk/rb/CHANGES", candidates.first
    assert_includes candidates, "https://raw.githubusercontent.com/SeleniumHQ/selenium/trunk/rb/CHANGES.md"
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

  def test_version_pinned_changelog_uri_follows_repository_branch_candidate
    candidates = Gemstar::ChangeLog.new(ParserMetadata.new).send(
      :changelog_uri_candidates,
      cache_only: false,
      force_refresh: false
    )

    assert_equal "https://raw.githubusercontent.com/whitequark/parser/master/CHANGELOG.md", candidates.first
    assert_operator candidates.index("https://raw.githubusercontent.com/whitequark/parser/master/CHANGELOG.md"),
      :<,
      candidates.index("https://raw.githubusercontent.com/whitequark/parser/v3.3.12.0/CHANGELOG.md")
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

  def test_documentation_percentage_is_not_parsed_as_a_version
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    content = <<~MARKDOWN
      ## [0.1.3] - 2026-07-14

      - TAG: [v0.1.3][0.1.3t]
      - COVERAGE: 96.33% -- 105/109 lines in 2 files
      - BRANCH COVERAGE: 81.58% -- 31/38 branches in 2 files
      - 88.89% documented

      ### Fixed

      - Package configured license files in gem release file lists.

      ## [0.1.2] - 2026-06-22

      - TAG: [v0.1.2][0.1.2t]
      - 88.89% documented

      ### Added

      - Added support for JRuby 10.1 and TruffleRuby 34.0.
    MARKDOWN

    changelog.stub :content, content do
      sections = changelog.send(:parse_changelog_sections)

      assert_equal %w[0.1.3 0.1.2], sections.keys
      assert_includes sections["0.1.3"].flatten.join, "88.89% documented"
      assert_includes sections["0.1.3"].flatten.join, "Package configured license files"
      assert_includes sections["0.1.2"].flatten.join, "Added support for JRuby"
    end
  end

  def test_oauth2_changelog_does_not_parse_percentages_or_versioned_prose_as_releases
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    content = <<~MARKDOWN
      ## [2.0.25] - 2026-07-14

      - TAG: [v2.0.25][2.0.25t]
      - 88.35% documented

      ### Added

      - Added support for JRuby 10.1 and TruffleRuby 34.0.

      ## [2.0.24] - 2026-06-18

      - 90.48% documented

      ### Changed

      - Pinned generated GitHub Actions checkout steps to the peeled
        v6.0.3 commit SHA so workflow verification accepts them.

      ## [2.0.23] - 2026-06-13

      - Fixed head appraisal dependency conflicts.
    MARKDOWN

    changelog.stub :content, content do
      sections = changelog.send(:parse_changelog_sections)

      assert_equal %w[2.0.25 2.0.24 2.0.23], sections.keys
      assert_includes sections["2.0.24"].flatten.join, "90.48% documented"
      assert_includes sections["2.0.24"].flatten.join, "v6.0.3 commit SHA"
    end
  end

  def test_snaky_hash_documentation_percentages_are_not_release_versions
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    content = <<~MARKDOWN
      ## [2.0.7] - 2026-07-14

      - COVERAGE: 100.00% -- 133/133 lines in 7 files
      - 92.86% documented

      ### Added

      - Added support for JRuby 10.1 and TruffleRuby 34.0.

      ## [2.0.4] - 2026-05-16

      - BRANCH COVERAGE: 100.00% -- 38/38 branches in 7 files
      - 100.00% documented

      ### Added

      - Incident Response Plan in IRP.md.
    MARKDOWN

    changelog.stub :content, content do
      sections = changelog.send(:parse_changelog_sections)

      assert_equal %w[2.0.7 2.0.4], sections.keys
      assert_includes sections["2.0.7"].flatten.join, "92.86% documented"
      assert_includes sections["2.0.4"].flatten.join, "100.00% documented"
    end
  end

  def test_version_gem_documentation_percentages_are_not_release_versions
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    content = <<~MARKDOWN
      ## [1.1.14] - 2026-07-13

      - 85.19% documented

      ### Fixed

      - Package configured license files in gem release file lists.

      ## [1.1.9] - 2026-05-24

      - 84.62% documented

      ## [1.1.7] - 2026-05-16

      - 76.92% documented

      ## [1.1.6] - 2026-05-15

      - 77.78% documented
    MARKDOWN

    changelog.stub :content, content do
      sections = changelog.send(:parse_changelog_sections)

      assert_equal %w[1.1.14 1.1.9 1.1.7 1.1.6], sections.keys
      assert_includes sections["1.1.14"].flatten.join, "85.19% documented"
      assert_includes sections["1.1.6"].flatten.join, "77.78% documented"
    end
  end

  def test_four_part_parser_gem_versions_are_parsed
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    content = <<~CHANGELOG
      Changelog
      =========

      v3.3.12.0 (2026-07-16)
      ----------------------

      API modifications:
       * Bump maintenance branches to 3.3.12 (#1091) (Koichi ITO)

      v3.3.11.1 (2026-03-27)
      ----------------------

      API modifications:
       * Bump maintenance branches to 3.2.11 (#1089) (Koichi ITO)
    CHANGELOG

    changelog.stub :content, content do
      sections = changelog.send(:parse_changelog_sections)
      dates = changelog.send(:parse_changelog_release_dates)

      assert_equal %w[3.3.12.0 3.3.11.1], sections.keys
      assert_includes sections["3.3.12.0"].flatten.join, "Bump maintenance branches"
      assert_equal "Jul 16, 2026", dates["3.3.12.0"]
    end
  end

  def test_extensionless_roda_changelog_sections_are_parsed
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    content = <<~CHANGELOG
      === master

      * Add url_escape plugin for Roda#url_{,un}escape methods.

      === 3.106.0 (2026-07-13)

      * Add shape_friendly plugin to make objects shape-friendly.

      === 3.105.0 (2026-06-12)

      * Improve performance of Integer matcher by 2-3x.
    CHANGELOG

    changelog.stub :content, content do
      sections = changelog.send(:parse_changelog_sections)
      dates = changelog.send(:parse_changelog_release_dates)

      assert_equal %w[3.106.0 3.105.0], sections.keys
      assert_includes sections["3.106.0"].flatten.join, "shape_friendly"
      assert_equal "Jul 13, 2026", dates["3.106.0"]
    end
  end

  def test_thruster_mislabeled_release_heading_is_corrected_from_package_metadata
    metadata = Gemstar::RubyGemsMetadata.new("thruster")
    changelog = Gemstar::ChangeLog.new(metadata)
    source = metadata.changelog_source(
      repo_uri: "https://github.com/basecamp/thruster",
      cache_only: true,
      force_refresh: false
    )
    content = <<~MARKDOWN
      ## v0.1.22 / 2026-07-16

      * Build with Go 1.26.5 (#140)

      ## v0.1.22 / 2026-06-29

      * Build with Go 1.26.4
      * Exclude image types from compression (#137)
    MARKDOWN

    assert_equal "https://raw.githubusercontent.com/basecamp/thruster/v0.1.23", source[:base]

    changelog.stub :content, content do
      sections = changelog.send(:parse_changelog_sections)
      dates = changelog.send(:parse_changelog_release_dates)

      assert_equal %w[0.1.23 0.1.22], sections.keys
      assert_includes sections["0.1.23"].flatten.join, "Go 1.26.5"
      assert_includes sections["0.1.22"].flatten.join, "Go 1.26.4"
      assert_equal "Jul 16, 2026", dates["0.1.23"]
      assert_equal "Jun 29, 2026", dates["0.1.22"]
    end
  end

  def test_sections_for_versions_matches_zero_padded_version_segments
    changelog = Gemstar::ChangeLog.new(FakeMetadata.new)
    content = <<~TEXT
      + Version 3.00 (2026.02.06)

      - No API changes / functionality changes.
      - Compatibility release.
    TEXT

    changelog.stub :content, content do
      sections = changelog.sections_for_versions(["3.0"])

      assert_includes sections.keys, "3.00"
      assert_includes sections["3.00"].flatten.join, "No API changes"
    end
  end
end
