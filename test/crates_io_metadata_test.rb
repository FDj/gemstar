# frozen_string_literal: true

require "test_helper"

class CratesIOMetadataTest < Minitest::Test
  def test_normalizes_crate_metadata
    metadata = Gemstar::CratesIOMetadata.new("serde")
    normalized = metadata.send(
      :normalize_meta,
      {
        "crate" => {
          "name" => "serde",
          "max_version" => "1.0.228",
          "description" => "Serialization framework",
          "homepage" => "https://serde.rs",
          "documentation" => "https://docs.rs/serde",
          "repository" => "https://github.com/serde-rs/serde"
        }
      }
    )

    assert_equal "serde", normalized["name"]
    assert_equal "1.0.228", normalized["version"]
    assert_equal "https://crates.io/crates/serde", normalized["project_uri"]
    assert_equal "https://github.com/serde-rs/serde", normalized["source_code_uri"]
  end

  def test_workspace_tag_candidates_include_crate_name
    metadata = Gemstar::CratesIOMetadata.new("tokio-util")

    assert_includes metadata.github_tag_candidates("0.7.16"), "tokio-util-0.7.16"
    assert_includes metadata.github_tag_candidates("0.7.16"), "tokio-util-v0.7.16"
    assert metadata.github_tag_matches?("tokio-util-0.7.16")
    refute metadata.github_tag_matches?("tokio-1.47.1")
  end
end
