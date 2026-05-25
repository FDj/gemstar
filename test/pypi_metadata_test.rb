# frozen_string_literal: true

require "test_helper"

class PyPIMetadataTest < Minitest::Test
  def test_normalizes_case_insensitive_project_urls
    metadata = Gemstar::PyPIMetadata.new("cryptography")
    normalized = metadata.send(
      :normalize_meta,
      {
        "info" => {
          "name" => "cryptography",
          "version" => "45.0.4",
          "summary" => "crypto",
          "package_url" => "https://pypi.org/project/cryptography/",
          "project_urls" => {
            "changelog" => "https://cryptography.io/en/latest/changelog/",
            "documentation" => "https://cryptography.io/",
            "homepage" => "https://github.com/pyca/cryptography"
          }
        }
      }
    )

    assert_equal "https://github.com/pyca/cryptography", normalized["homepage_uri"]
    assert_nil normalized["source_code_uri"]
    assert_equal "https://cryptography.io/en/latest/changelog/", normalized["changelog_uri"]
    assert_equal "https://cryptography.io/", normalized["documentation_uri"]
  end

  def test_date_version_tag_candidates_include_zero_padded_variant
    metadata = Gemstar::PyPIMetadata.new("certifi")

    assert_includes metadata.github_tag_candidates("2025.4.26"), "2025.04.26"
    assert_includes metadata.github_tag_candidates("2025.4.26"), "v2025.04.26"
    assert_includes metadata.github_tag_candidates("2025.4.26"), "release_2025.04.26"
  end

  def test_release_prefixed_tag_candidates_are_included
    metadata = Gemstar::PyPIMetadata.new("pycparser")

    assert_includes metadata.github_tag_candidates("2.22"), "release_v2.22"
  end

  def test_single_digit_minor_tag_candidates_include_zero_padded_variant
    metadata = Gemstar::PyPIMetadata.new("pycparser")

    assert_includes metadata.github_tag_candidates("3.0"), "release_v3.00"
  end
end
