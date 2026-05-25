# frozen_string_literal: true

require "test_helper"

class UvLockFileTest < Minitest::Test
  UV_LOCK = <<~TOML
    version = 1
    revision = 3
    requires-python = ">=3.12"

    [[package]]
    name = "demo-app"
    version = "0.1.0"
    source = { virtual = "." }
    dependencies = [
        { name = "requests" },
    ]

    [[package]]
    name = "certifi"
    version = "2025.4.26"
    source = { registry = "https://pypi.org/simple" }
    sdist = { url = "https://files.pythonhosted.org/packages/certifi.tar.gz", hash = "sha256:abc" }
    wheels = [
        { url = "https://files.pythonhosted.org/packages/certifi.whl", hash = "sha256:def" },
    ]

    [[package]]
    name = "requests"
    version = "2.32.4"
    source = { registry = "https://pypi.org/simple" }
    dependencies = [
        { name = "certifi" },
    ]
  TOML

  def test_specs_include_locked_python_packages_and_skip_virtual_project
    lockfile = Gemstar::UvLockFile.new(content: UV_LOCK)

    assert_equal({
      "certifi" => "2025.4.26",
      "requests" => "2.32.4"
    }, lockfile.specs)
  end

  def test_source_for_uses_pypi_metadata
    lockfile = Gemstar::UvLockFile.new(content: UV_LOCK)

    assert_equal :pypi, lockfile.source_for("certifi")[:type]
    assert_equal "https://pypi.org/simple", lockfile.source_for("certifi")[:remote]
    assert_equal "https://files.pythonhosted.org/packages/certifi.tar.gz", lockfile.source_for("certifi")[:distribution_url]
    assert_equal "https://pypi.org/project/certifi/", lockfile.source_for("certifi")[:registry_url]
  end
end
