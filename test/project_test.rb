# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class ProjectTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("gemstar-project-test")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if File.directory?(@tmpdir)
  end

  def test_unsupported_project_error_uses_expanded_directory_and_supported_files
    error = assert_raises(Gemstar::Project::UnsupportedProjectError) do
      Gemstar::Project.from_cli_argument(@tmpdir)
    end

    assert_includes error.message, "Directory #{@tmpdir} does not contain a recognized project file."
    assert_includes error.message, "Only Gemfile, Gemfile.lock, config/importmap.rb, package.json, package-lock.json, and uv.lock are supported."
  end

  def test_gemfile_lock_marks_supported_project_directory
    FileUtils.touch(File.join(@tmpdir, "Gemfile.lock"))

    project = Gemstar::Project.from_cli_argument(@tmpdir)

    assert_equal @tmpdir, project.directory
  end

  def test_uv_lock_marks_supported_project_directory
    File.write(File.join(@tmpdir, "uv.lock"), <<~TOML)
      version = 1
      revision = 3

      [[package]]
      name = "requests"
      version = "2.32.4"
      source = { registry = "https://pypi.org/simple" }
    TOML

    project = Gemstar::Project.from_cli_argument(@tmpdir)

    assert_equal @tmpdir, project.directory
    assert_equal ["python"], project.package_scope_options.map { |option| option[:id] }
    assert_equal ["requests"], project.gem_states.map { |state| state[:name] }
    assert_equal "Python", project.gem_states.first[:package_type_label]
  end

  def test_package_item_label_names_single_ecosystem_projects
    FileUtils.touch(File.join(@tmpdir, "package.json"))
    js_project = Gemstar::Project.from_cli_argument(@tmpdir)
    assert_equal "JavaScript package", js_project.package_item_label

    FileUtils.rm(File.join(@tmpdir, "package.json"))
    File.write(File.join(@tmpdir, "uv.lock"), "version = 1\nrevision = 3\n")
    python_project = Gemstar::Project.from_cli_argument(@tmpdir)
    assert_equal "Python package", python_project.package_item_label
  end
end
