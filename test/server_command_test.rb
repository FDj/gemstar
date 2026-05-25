# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "gemstar/commands/server"

class ServerCommandTest < Minitest::Test
  FakeProject = Struct.new(:package_scope_options)

  def setup
    @tmpdir = Dir.mktmpdir("gemstar-server-test")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if defined?(@tmpdir) && File.directory?(@tmpdir)
  end

  def test_unsupported_project_exits_with_helpful_message
    command = Gemstar::Commands::Server.new(project: @tmpdir)

    stdout, stderr = capture_io do
      error = assert_raises(SystemExit) { command.run }

      assert_equal 1, error.status
    end

    assert_empty stdout
    assert_includes stderr, "Directory #{@tmpdir} does not contain a recognized project file."
    assert_includes stderr, "Only Gemfile, Gemfile.lock, config/importmap.rb, package.json, package-lock.json, and uv.lock are supported."
    refute_includes stderr, "from "
  end

  def test_reload_validates_projects_before_starting_watcher
    command = Gemstar::Commands::Server.new(project: @tmpdir, reload: true)

    stdout, stderr = capture_io do
      error = assert_raises(SystemExit) { command.run }

      assert_equal 1, error.status
    end

    assert_empty stdout
    assert_includes stderr, "Directory #{@tmpdir} does not contain a recognized project file."
    refute_includes stdout, "Starting gemstar server in reload mode"
  end

  def test_detail_cache_contexts_cover_default_and_package_scope_variants
    command = Gemstar::Commands::Server.new({})
    project = FakeProject.new([{ id: "gems" }, { id: "js" }])
    package_states = [
      { name: "rails", package_scope: "gems", status: :updated },
      { name: "turbo", package_scope: "js", status: :unchanged }
    ]

    base_contexts = command.send(
      :detail_cache_contexts_for,
      project: project,
      project_index: 2,
      from_revision_id: "abc123",
      to_revision_id: "worktree",
      package_states: package_states
    )
    rails_contexts = command.send(:detail_cache_contexts_for_package, package_states.first, base_contexts)

    assert_includes base_contexts, { project: 2, from: "abc123", to: "worktree", filter: "updated", scope: "all" }
    assert_includes base_contexts, { project: 2, from: "abc123", to: "worktree", filter: "all", scope: "all" }
    assert_includes rails_contexts, { project: 2, from: "abc123", to: "worktree", filter: "updated", scope: "gems" }
    assert_includes rails_contexts, { project: 2, from: "abc123", to: "worktree", filter: "all", scope: "gems" }
  end

  def test_detail_cache_fetcher_marks_internal_requests
    command = Gemstar::Commands::Server.new({})
    captured_env = nil
    app = lambda do |env|
      captured_env = env
      [200, {}, []]
    end

    fetcher = command.send(:build_detail_cache_fetcher, app)
    fetcher.call(
      { name: "rails" },
      { project: 0, from: "abc123", to: "worktree", filter: "updated", scope: "gems" }
    )

    assert_equal true, captured_env["gemstar.detail_cache_warm"]
    assert_equal "/detail", captured_env["PATH_INFO"]
    assert_includes captured_env["QUERY_STRING"], "package=rails"
  end
end
