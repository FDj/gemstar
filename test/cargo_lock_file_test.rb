# frozen_string_literal: true

require "test_helper"

class CargoLockFileTest < Minitest::Test
  CARGO_LOCK = <<~TOML
    version = 4

    [[package]]
    name = "demo-app"
    version = "0.1.0"
    dependencies = [
     "serde 1.0.228",
    ]

    [[package]]
    name = "serde"
    version = "1.0.228"
    source = "registry+https://github.com/rust-lang/crates.io-index"
    checksum = "abc"

    [[package]]
    name = "serde"
    version = "0.9.15"
    source = "registry+https://github.com/rust-lang/crates.io-index"
    checksum = "def"

    [[package]]
    name = "tracing"
    version = "0.1.41"
    source = "git+https://github.com/tokio-rs/tracing?branch=main#0123456789abcdef"
  TOML

  def test_specs_include_remote_crates_skip_workspace_packages_and_preserve_duplicate_versions
    lockfile = Gemstar::CargoLockFile.new(content: CARGO_LOCK)

    assert_equal({
      "serde@1.0.228" => "1.0.228",
      "serde@0.9.15" => "0.9.15",
      "tracing" => "0.1.41"
    }, lockfile.specs)
  end

  def test_source_for_exposes_crates_io_metadata
    lockfile = Gemstar::CargoLockFile.new(content: CARGO_LOCK)
    source = lockfile.source_for("serde@1.0.228")

    assert_equal :cargo, source[:type]
    assert source[:crates_io]
    assert_equal "serde", source[:package_name]
    assert_equal "https://crates.io/crates/serde", source[:registry_url]
  end

  def test_source_for_parses_git_revision_and_branch
    lockfile = Gemstar::CargoLockFile.new(content: CARGO_LOCK)
    source = lockfile.source_for("tracing")

    assert_equal :git, source[:type]
    assert_equal "https://github.com/tokio-rs/tracing", source[:remote]
    assert_equal "main", source[:branch]
    assert_equal "0123456789abcdef", source[:revision]
  end
end
