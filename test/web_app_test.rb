# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "gemstar/web/app"

class WebAppTest < Minitest::Test
  FakeProject = Struct.new(:package_item_label)

  class FakeActionProject
    attr_reader :directory

    def initialize(scopes: [], directory: Dir.pwd)
      @scopes = scopes
      @directory = directory
    end

    def gemfile?
      @scopes.include?(:gems)
    end

    def lockfile?
      false
    end

    def uv_lock?
      @scopes.include?(:python)
    end

    def package_lock?
      @scopes.include?(:package_lock)
    end

    def package_json?
      @scopes.include?(:js) || package_lock?
    end

    def importmap?
      @scopes.include?(:importmap)
    end
  end

  class FakeRegistryMetadata
    def registry_release_dates(cache_only: false, force_refresh: false)
      {
        "45.0.4" => "Jun 10, 2025",
        "45.0.5" => "Jul 2, 2025",
        "46.0.0" => "Sep 16, 2025",
        "47.0.0" => "Apr 24, 2026",
        "48.0.0" => "May 4, 2026",
        "49.0.0" => "May 20, 2026"
      }
    end
  end

  def test_selected_filter_falls_back_to_all_when_project_has_no_updates
    app = Gemstar::Web::App.allocate
    app.instance_variable_set(:@gem_states, [
      { name: "requests", status: :unchanged },
      { name: "vite", status: :unchanged }
    ])

    assert_equal "all", app.send(:selected_filter, "updated", nil)
  end

  def test_selected_filter_keeps_explicit_updated_when_project_has_updates
    app = Gemstar::Web::App.allocate
    app.instance_variable_set(:@gem_states, [
      { name: "requests", status: :unchanged },
      { name: "vite", status: :updated }
    ])

    assert_equal "updated", app.send(:selected_filter, "updated", nil)
  end

  def test_empty_detail_html_uses_project_package_label
    app = Gemstar::Web::App.allocate
    app.instance_variable_set(:@selected_project, FakeProject.new("Python package"))

    html = app.send(:empty_detail_html)

    assert_includes html, "No Python package selected"
    assert_includes html, "Choose a Python package from the list"
    refute_includes html, "No gem selected"
  end

  def test_project_actions_for_python_project_use_uv_without_bundler
    app = Gemstar::Web::App.allocate

    actions = app.send(:project_actions, FakeActionProject.new(scopes: [:python]))

    assert_equal ["uv_sync", "uv_lock_upgrade"], actions.map { |action| action[:id] }
  end

  def test_project_actions_for_mixed_project_include_each_ecosystem
    app = Gemstar::Web::App.allocate

    actions = app.send(:project_actions, FakeActionProject.new(scopes: [:gems, :python, :package_lock, :importmap]))
    action_by_id = actions.to_h { |action| [action[:id], action] }

    assert_includes actions.map { |action| action[:id] }, "bundle_install"
    assert_includes actions.map { |action| action[:id] }, "uv_sync"
    assert_includes actions.map { |action| action[:id] }, "npm_install"
    assert_includes actions.map { |action| action[:id] }, "importmap_update"
    assert_equal %w[bin/importmap update], action_by_id.fetch("importmap_update")[:command]
  end

  def test_project_action_shell_command_cd_into_project_before_running_command
    app = Gemstar::Web::App.allocate
    project = FakeActionProject.new(directory: "/tmp/example project")

    command = app.send(:project_action_shell_command, project, ["uv", "lock", "--upgrade"])

    assert_equal "cd /tmp/example\\ project && uv lock --upgrade", command
  end

  def test_project_action_command_wraps_mise_projects_with_mise_exec
    app = Gemstar::Web::App.allocate
    project = FakeActionProject.new(directory: "/tmp/example")

    app.stub :project_uses_mise?, true do
      app.stub :mise_executable, "/opt/homebrew/bin/mise" do
        command = app.send(:project_action_command, project, { command: ["bin/bundle", "update"] })

        assert_equal ["/opt/homebrew/bin/mise", "exec", "--", "bin/bundle", "update"], command
      end
    end
  end

  def test_project_action_environment_removes_parent_ruby_and_bundler_variables
    app = Gemstar::Web::App.allocate

    environment = app.send(:project_action_environment)

    assert_nil environment["BUNDLE_GEMFILE"]
    assert_nil environment["RUBYOPT"]
    assert_nil environment["GEM_HOME"]
  end

  def test_revision_panel_labels_previous_versions_as_included_for_unchanged_worktree_package
    app = Gemstar::Web::App.allocate
    app.instance_variable_set(:@selected_to_revision_id, "worktree")
    app.instance_variable_set(:@selected_from_revision_id, "ddf1f2c5")
    app.instance_variable_set(:@revision_options, [{ id: "ddf1f2c5", label: "ddf1f2c5" }])
    app.instance_variable_set(:@selected_gem, { status: :unchanged })

    html = app.send(:render_detail_revision_panel, {
      latest: [{ version: "1.3", kind: :future, html: "<p>Available</p>" }],
      current: [],
      previous: [{ version: "1.2", kind: :previous, html: "<p>Included</p>" }]
    })

    assert_includes html, "Available"
    assert_includes html, "Included in ddf1f2c5"
    refute_includes html, "Worktree changes since ddf1f2c5"
    refute_includes html, "No changelog entries in this revision range."
  end

  def test_revision_panel_keeps_worktree_changes_group_for_updated_packages
    app = Gemstar::Web::App.allocate
    app.instance_variable_set(:@selected_to_revision_id, "worktree")
    app.instance_variable_set(:@selected_from_revision_id, "ddf1f2c5")
    app.instance_variable_set(:@revision_options, [{ id: "ddf1f2c5", label: "ddf1f2c5" }])
    app.instance_variable_set(:@selected_gem, { status: :updated })

    html = app.send(:render_detail_revision_panel, {
      latest: [],
      current: [],
      previous: [{ version: "1.0", kind: :previous, html: "<p>Earlier</p>" }]
    })

    assert_includes html, "Worktree changes since ddf1f2c5"
    assert_includes html, "No changelog entries in this revision range."
    assert_includes html, "Earlier changes"
  end

  def test_changelog_content_strips_setext_separator_after_version_heading
    app = Gemstar::Web::App.allocate

    content = app.send(
      :changelog_content,
      ["3.246.0\n--------\n\n* Feature - Updated configuration values for `defaults_mode`."],
      heading_version: "3.246.0"
    )

    refute_includes content[:html], "<hr"
    assert_includes content[:html], "Updated configuration values"
    assert_equal "3.246.0", content[:title]
  end

  def test_changelog_content_strips_rst_separator_after_version_heading
    app = Gemstar::Web::App.allocate

    content = app.send(
      :changelog_content,
      ["45.0.4 - 2025-06-09\n~~~~~~~~~~~~~~~~~~~\n\n* Fixed decrypting PKCS#8 files."],
      heading_version: "45.0.4"
    )

    refute_includes content[:html], "~~~~"
    assert_includes content[:html], "Fixed decrypting PKCS#8"
    assert_equal "45.0.4", content[:title]
  end

  def test_changelog_content_strips_version_heading_with_trailing_hashes
    app = Gemstar::Web::App.allocate

    content = app.send(
      :changelog_content,
      ["Version 4.0.2 ############\n\nMerged changes in 3.2.4 and 3.3.3."],
      heading_version: "4.0.2"
    )

    refute_includes content[:html], "############"
    refute_includes content[:html], "Version 4.0.2"
    assert_includes content[:html], "Merged changes in 3.2.4 and 3.3.3."
    assert_equal "4.0.2", content[:title]
  end

  def test_detail_refresh_requested_accepts_truthy_flag
    app = Gemstar::Web::App.allocate

    assert app.send(:detail_refresh_requested?, { "refresh" => "1" })
    assert app.send(:detail_refresh_requested?, { "refresh" => "true" })
    refute app.send(:detail_refresh_requested?, {})
  end

  def test_detail_use_github_cli_requested_accepts_truthy_flag
    app = Gemstar::Web::App.allocate

    assert app.send(:detail_use_github_cli_requested?, { "use_gh" => "1" })
    assert app.send(:detail_use_github_cli_requested?, { "use_gh" => "yes" })
    refute app.send(:detail_use_github_cli_requested?, {})
  end

  def test_relevant_package_versions_include_registry_versions_between_current_and_latest
    app = Gemstar::Web::App.allocate
    gem_state = {
      name: "cryptography",
      old_version: "45.0.4",
      new_version: nil,
      raw_old_version: nil,
      raw_new_version: nil,
      source: {}
    }

    app.stub :metadata_for, { "version" => "48.0.0" } do
      versions = app.send(:relevant_package_versions, gem_state, FakeRegistryMetadata.new)

      assert_includes versions, "45.0.4"
      assert_includes versions, "45.0.5"
      assert_includes versions, "46.0.0"
      assert_includes versions, "47.0.0"
      assert_includes versions, "48.0.0"
      refute_includes versions, "49.0.0"
    end
  end

  def test_release_date_matching_handles_zero_padded_version_segments
    app = Gemstar::Web::App.allocate

    date = app.send(:release_date_for, { "3.00" => "Feb 6, 2026" }, "3.0")

    assert_equal "Feb 6, 2026", date
  end

  def test_github_cli_release_button_only_renders_for_github_repo
    app = Gemstar::Web::App.allocate

    assert_includes app.send(:render_github_cli_release_button, "1.2.3", "https://github.com/basecamp/lexxy"), "Use GitHub CLI"
    assert_empty app.send(:render_github_cli_release_button, "1.2.3", "https://example.com/basecamp/lexxy")
  end
end
