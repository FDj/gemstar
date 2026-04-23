# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class DiffCommandTest < Minitest::Test
  class FakeRenderer
    def render_diff(_diff_command)
      "rendered output"
    end
  end

  class FakeGitRepo
    attr_reader :received_time_expression

    def commit_before(time_expression)
      @received_time_expression = time_expression
      "abc123"
    end

    def commit_info(revision)
      return nil unless revision == "abc123"

      {
        id: "abc123456789",
        short_sha: "abc1234",
        authored_at: "2026-04-02T10:30:00+02:00",
        subject: "Update dependency baseline"
      }
    end

    def commits_between(from_revision, to_revision = "HEAD")
      @received_commit_range = [from_revision, to_revision]
      [
        {
          id: "def4567890",
          short_sha: "def4567",
          authored_at: "2026-04-01T12:00:00+02:00",
          subject: "Update frontend packages"
        }
      ]
    end

    def received_commit_range
      @received_commit_range
    end
  end

  class FakeProject
    attr_reader :directory, :name, :git_repo

    def initialize(directory:, name:, package_states:)
      @directory = directory
      @name = name
      @package_states = package_states
      @git_repo = FakeGitRepo.new
    end

    def gem_states(from_revision_id:, to_revision_id:)
      @received_revisions = [from_revision_id, to_revision_id]
      @package_states
    end

    def received_revisions
      @received_revisions
    end
  end

  def setup
    @tmpdir = Dir.mktmpdir("gemstar-diff-test")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if File.directory?(@tmpdir)
  end

  def test_project_diff_uses_project_states_and_passes_revisions
    project = FakeProject.new(
      directory: @tmpdir,
      name: "demo-app",
      package_states: [
        {
          name: "rails",
          package_scope: "gems",
          package_type_label: "Gem",
          old_version: "7.1.0",
          new_version: "7.1.1",
          version_label: "7.1.0 → 7.1.1",
          status: :upgrade
        },
        {
          name: "react",
          package_scope: "js",
          package_type_label: "JS",
          old_version: "18.2.0",
          new_version: "19.0.0",
          version_label: "18.2.0 → 19.0.0",
          package_source_file: :package_lock,
          status: :upgrade
        },
        {
          name: "left-pad",
          package_scope: "js",
          package_type_label: "JS",
          old_version: "1.3.0",
          new_version: "1.3.0",
          version_label: "1.3.0",
          package_source_file: :package_lock,
          status: :unchanged
        }
      ]
    )

    Gemstar::Project.stub :from_cli_argument, project do
      diff = Gemstar::Commands::Diff.new(project: @tmpdir, from: "main~1", to: "HEAD")
      diff.stub :output_renderer, FakeRenderer.new do
        built = []
        diff.stub :build_entry, ->(package_state:) {
          built << package_state
          {
            old: package_state[:old_version],
            new: package_state[:new_version],
            version_label: package_state[:version_label],
            package_scope: package_state[:package_scope]
          }
        } do
          diff.run
        end

        assert_equal ["main~1", "HEAD"], project.received_revisions
        assert_equal %w[rails react], built.map { |state| state[:name] }.sort
        assert_equal ["rails", "react"], diff.updates.keys.sort
        assert_equal "demo-app", diff.project_name
      end
    end
  end

  def test_project_diff_disambiguates_duplicate_js_package_names
    project = FakeProject.new(
      directory: @tmpdir,
      name: "demo-app",
      package_states: [
        {
          name: "stimulus",
          package_scope: "js",
          package_type_label: "JS",
          old_version: "3.1.0",
          new_version: "3.2.0",
          version_label: "3.1.0 → 3.2.0",
          package_source_file: :importmap,
          status: :upgrade
        },
        {
          name: "stimulus",
          package_scope: "js",
          package_type_label: "JS",
          old_version: "3.1.0",
          new_version: "3.2.0",
          version_label: "3.1.0 → 3.2.0",
          package_source_file: :package_lock,
          status: :upgrade
        }
      ]
    )

    Gemstar::Project.stub :from_cli_argument, project do
      diff = Gemstar::Commands::Diff.new(project: @tmpdir)
      diff.stub :output_renderer, FakeRenderer.new do
        diff.stub :build_entry, ->(package_state:) {
          {
            old: package_state[:old_version],
            new: package_state[:new_version],
            version_label: package_state[:version_label],
            package_scope: package_state[:package_scope]
          }
        } do
          diff.run
        end

        assert_equal ["stimulus (importmap)", "stimulus (package-lock)"], diff.updates.keys.sort
      end
    end
  end

  def test_project_diff_filters_to_requested_ecosystem
    project = FakeProject.new(
      directory: @tmpdir,
      name: "demo-app",
      package_states: [
        {
          name: "rails",
          package_scope: "gems",
          package_type_label: "Gem",
          old_version: "7.1.0",
          new_version: "7.1.1",
          version_label: "7.1.0 → 7.1.1",
          status: :upgrade
        },
        {
          name: "react",
          package_scope: "js",
          package_type_label: "JS",
          old_version: "18.2.0",
          new_version: "19.0.0",
          version_label: "18.2.0 → 19.0.0",
          package_source_file: :package_lock,
          status: :upgrade
        }
      ]
    )

    Gemstar::Project.stub :from_cli_argument, project do
      diff = Gemstar::Commands::Diff.new(project: @tmpdir, ecosystem: "js")
      diff.stub :output_renderer, FakeRenderer.new do
        built = []
        diff.stub :build_entry, ->(package_state:) {
          built << package_state[:name]
          {
            old: package_state[:old_version],
            new: package_state[:new_version],
            version_label: package_state[:version_label],
            package_scope: package_state[:package_scope]
          }
        } do
          diff.run
        end

        assert_equal ["react"], built
        assert_equal ["react"], diff.updates.keys
      end
    end
  end

  def test_project_diff_resolves_since_to_from_revision
    project = FakeProject.new(
      directory: @tmpdir,
      name: "demo-app",
      package_states: [
        {
          name: "rails",
          package_scope: "gems",
          package_type_label: "Gem",
          old_version: "7.1.0",
          new_version: "7.1.1",
          version_label: "7.1.0 → 7.1.1",
          status: :upgrade
        }
      ]
    )

    Gemstar::Project.stub :from_cli_argument, project do
      diff = Gemstar::Commands::Diff.new(project: @tmpdir, since: "3 weeks")
      diff.stub :output_renderer, FakeRenderer.new do
        diff.stub :build_entry, ->(package_state:) {
          {
            old: package_state[:old_version],
            new: package_state[:new_version],
            version_label: package_state[:version_label],
            package_scope: package_state[:package_scope]
          }
        } do
          diff.run
        end

        assert_equal "3 weeks ago", project.git_repo.received_time_expression
        assert_equal ["abc123", "worktree"], project.received_revisions
        assert_equal ["abc123", "HEAD"], project.git_repo.received_commit_range
        assert_equal "abc123", diff.from
        assert_equal "abc1234", diff.since_cutoff_commit[:short_sha]
        assert_equal ["def4567"], diff.considered_commits.map { |commit| commit[:short_sha] }
      end
    end
  end

  def test_since_cutoff_is_logged
    project = FakeProject.new(
      directory: @tmpdir,
      name: "demo-app",
      package_states: []
    )

    Gemstar::Project.stub :from_cli_argument, project do
      diff = Gemstar::Commands::Diff.new(project: @tmpdir, since: "3 weeks ago")
      diff.stub :output_renderer, FakeRenderer.new do
        output = capture_io { diff.run }.first

        assert_includes output, "Since cutoff: 3 weeks ago -> abc1234 Update dependency baseline (2026-04-02)"
      end
    end
  end

  def test_since_rejects_explicit_from
    error = assert_raises(Thor::Error) do
      Gemstar::Commands::Diff.new(project: @tmpdir, since: "3 weeks", from: "main~1")
    end

    assert_equal "--since cannot be combined with --from", error.message
  end

  def test_lockfile_diff_rejects_non_gem_ecosystem
    error = assert_raises(Thor::Error) do
      Gemstar::Commands::Diff.new(ecosystem: "js").run
    end

    assert_equal "--ecosystem=js requires --project because lockfile mode only supports gems", error.message
  end

  def test_project_diff_prints_clickable_file_url_for_report
    output_file = File.join(@tmpdir, "report with spaces.html")
    project = FakeProject.new(
      directory: @tmpdir,
      name: "demo-app",
      package_states: []
    )

    Gemstar::Project.stub :from_cli_argument, project do
      diff = Gemstar::Commands::Diff.new(project: @tmpdir, output_file: output_file)
      diff.stub :output_renderer, FakeRenderer.new do
        output = capture_io { diff.run }.first

        assert_includes output, "Changelog report created: file://#{output_file.gsub(" ", "%20")}"
      end
    end
  end

  def test_markdown_output_puts_considered_commits_after_package_entries
    diff_command = Struct.new(:project_name, :updates, :from, :to, :since, :considered_commits, :since_cutoff_commit) do
      def format_commit(commit, fallback_revision:)
        return fallback_revision.to_s if commit.nil?

        "#{commit[:short_sha]} #{commit[:subject]} (#{commit[:authored_at].split("T").first})"
      end
    end.new(
      "demo-app",
      {
        "react" => {
          old: "18.2.0",
          new: "19.0.0",
          version_label: "18.2.0 → 19.0.0",
          package_scope: "js"
        }
      },
      "abc123",
      nil,
      "3 weeks ago",
      [
        {
          id: "def4567890",
          short_sha: "def4567",
          authored_at: "2026-04-01T12:00:00+02:00",
          subject: "Update frontend packages"
        }
      ],
      {
        id: "abc123456789",
        short_sha: "abc1234",
        authored_at: "2026-04-02T10:30:00+02:00",
        subject: "Update dependency baseline"
      }
    )

    output = Gemstar::Outputs::Markdown.new.render_diff(diff_command)

    assert_includes output, "Since cutoff `3 weeks ago` resolved to abc1234 Update dependency baseline (2026-04-02)."
    assert_includes output, "- `def4567` 2026-04-01T12:00:00+02:00 Update frontend packages"
    assert_operator output.index("## react"), :<, output.index("## Commits Considered")
  end
end
