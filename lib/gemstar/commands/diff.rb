# frozen_string_literal: true

require_relative "command"
require "concurrent-ruby"
require "tmpdir"
require "pathname"
require "uri"

module Gemstar
  module Commands
    class Diff < Command
      attr_reader :updates
      attr_reader :failed
      attr_reader :from
      attr_reader :to
      attr_reader :lockfile
      attr_reader :git_repo
      attr_reader :lockfile_full_path
      attr_reader :output_file
      attr_reader :output_format
      attr_reader :project
      attr_reader :ecosystem
      attr_reader :since
      attr_reader :considered_commits
      attr_reader :since_cutoff_commit

      def initialize(options)
        super

        @debug_gem_regex = Regexp.new(options[:debug_gem_regex] || ENV["GEMSTAR_DEBUG_GEM_REGEX"] || ".*")

        @since = normalize_since(options[:since])
        @from = options[:from] || "HEAD"
        @to = options[:to]
        @lockfile = options[:lockfile] || "Gemfile.lock"
        @output_format = normalize_output_format(options[:format] || options[:output_format])
        @output_file = options[:output_file] || default_output_file
        @project = options[:project] ? Gemstar::Project.from_cli_argument(options[:project]) : nil
        @ecosystem = normalize_ecosystem(options[:ecosystem])
        @considered_commits = []
        @since_cutoff_commit = nil

        @git_repo = project ? project.git_repo : Gemstar::GitRepo.new(File.dirname(@lockfile))
        @from = resolve_since_commit if since
      end

      def run
        project ? run_project_diff : run_lockfile_diff
        @considered_commits = collect_considered_commits

        rendered_output = output_renderer.render_diff(self)
        File.write(output_file, rendered_output)
        puts "✅ Changelog report created: #{output_file_url}"

        if failed.any?
          puts "\n⚠️ The following gems failed to process:"
          failed.each { |gem, msg| puts "  - #{gem}: #{msg}" }
        end
      end

      private

      def normalize_output_format(value)
        format = value.to_s.strip.downcase
        return :markdown if %w[md markdown].include?(format)

        :html
      end

      def normalize_ecosystem(value)
        normalized = value.to_s.strip.downcase
        return "all" if normalized.empty?
        return normalized if %w[all gems js].include?(normalized)

        raise Thor::Error, "Unsupported ecosystem #{value.inspect}. Expected one of: all, gems, js"
      end

      def normalize_since(value)
        normalized = value.to_s.strip
        return nil if normalized.empty?

        if @options[:from].to_s.strip != ""
          raise Thor::Error, "--since cannot be combined with --from"
        end

        normalized.match?(/\bago\z/i) ? normalized : "#{normalized} ago"
      end

      def resolve_since_commit
        commit = git_repo.commit_before(since)
        @since_cutoff_commit = git_repo.commit_info(commit)
        commit
      end

      def log_since_cutoff
        return unless since

        puts "Since cutoff: #{since} -> #{format_commit(since_cutoff_commit, fallback_revision: from)}"
      end

      def default_output_file
        extension = output_format == :markdown ? "md" : "html"
        File.join(Dir.tmpdir, "gem_update_changelog.#{extension}")
      end

      def output_file_url
        "file://#{URI::DEFAULT_PARSER.escape(File.expand_path(output_file))}"
      end

      def output_renderer
        @output_renderer ||= case output_format
        when :markdown
          Outputs::Markdown.new
        else
          Outputs::HTML.new
        end
      end

      def collect_considered_commits
        git_repo.commits_between(from, commit_log_to_revision)
      rescue StandardError => e
        warn "Could not collect considered commits: #{e.message}"
        []
      end

      def format_commit(commit, fallback_revision:)
        return fallback_revision.to_s if commit.nil?

        date = commit[:authored_at].to_s.split("T").first
        label = [commit[:short_sha] || commit[:id], commit[:subject]].compact.join(" ")
        date.empty? ? label : "#{label} (#{date})"
      end

      public :format_commit

      def commit_log_to_revision
        return "HEAD" if to.nil? || to == "worktree"

        to
      end

      def project_name
        return project.name if project

        Pathname.getwd.basename.to_s
      end

      public :project_name

      def build_entry(package_state:)
        package_name = package_state[:name]
        old_version = package_state[:old_version]
        new_version = package_state[:new_version]
        metadata = metadata_for(package_state)
        repo_url = metadata.repo_uri
        changelog = Gemstar::ChangeLog.new(metadata)
        sections = changelog.extract_relevant_sections(old_version, new_version)

        compare_url = if repo_url && old_version
          tag_from_v = "v#{old_version}"
          tag_to_v = "v#{new_version}"
          tag_from_raw = old_version
          tag_to_raw = new_version

          url_v = "#{repo_url}/compare/#{tag_from_v}...#{tag_to_v}"
          url_raw = "#{repo_url}/compare/#{tag_from_raw}...#{tag_to_raw}"

          begin
            URI.open(url_v, read_timeout: 4) # TODO use a real HTTP client
            url_v
          rescue
            url_raw
          end
        end

        homepage_url = metadata.meta["homepage_uri"] || metadata.meta["source_code_uri"] || "https://rubygems.org/gems/#{package_name}"
        description = metadata.meta["info"]

        entry = {
          old: old_version,
          new: new_version,
          homepage_url: homepage_url,
          description: description,
          package_scope: package_state[:package_scope],
          package_type_label: package_state[:package_type_label],
          version_label: package_state[:version_label]
        }
        entry[:sections] = sections unless sections.nil? || sections.empty?
        entry[:compare_url] = compare_url if compare_url

        if entry[:sections].nil? && repo_url && new_version
          entry[:release_url] = "#{repo_url}/releases/tag/#{new_version}"
        end
        entry[:release_page] = "#{repo_url}/releases" if repo_url && (!sections || sections.empty?)

        if repo_url && new_version
          version_list = sections ? sections.keys : []
          if version_list.empty?
            version_list = [new_version]
          end

          entry[:release_urls] = version_list.map do |ver|
            "#{repo_url}/releases/tag/#{ver}"
          end
        end

        entry
      end

      def metadata_for(package_state)
        if package_state[:package_scope] == "js"
          Gemstar::NpmMetadata.new(package_state[:name])
        else
          Gemstar::RubyGemsMetadata.new(package_state[:name])
        end
      end

      def run_lockfile_diff
        validate_lockfile_ecosystem!

        @lockfile_full_path = git_repo.get_full_path(File.basename(lockfile))
        puts "Lockfile path: #{lockfile_full_path}"
        log_since_cutoff

        old = LockFile.new(content: git_repo.show_blob_at(@from, lockfile_full_path))
        new = @to ?
                LockFile.new(content: git_repo.show_blob_at(@to, lockfile_full_path)) :
                LockFile.new(path: lockfile)

        collect_lockfile_updates(new_lockfile: new, old_lockfile: old)
      end

      def run_project_diff
        puts "Project path: #{project.directory}"
        log_since_cutoff

        changed_states = project.gem_states(from_revision_id: from, to_revision_id: to || "worktree")
          .select { |package_state| include_package_state?(package_state) }
          .reject { |package_state| package_state[:status] == :unchanged }
        changed_states = disambiguate_duplicate_names(changed_states)
        collect_project_updates(changed_states)
      end

      def collect_lockfile_updates(new_lockfile:, old_lockfile:)
        package_states = new_lockfile.specs.keys.sort.map do |gem_name|
          old_version = old_lockfile.specs[gem_name]
          new_version = new_lockfile.specs[gem_name]
          next if old_version == new_version

          {
            name: gem_name,
            display_name: gem_name,
            package_scope: "gems",
            package_type_label: "Gem",
            old_version: old_version,
            new_version: new_version,
            version_label: version_label(old_version, new_version)
          }
        end.compact

        collect_project_updates(package_states)
      end

      def collect_project_updates(package_states)
        @updates = {}
        @failed = []
        mutex = Mutex.new
        pool = Concurrent::FixedThreadPool.new(10)

        package_states.each do |package_state|
          pool.post do
            package_name = package_state[:name]
            next unless @debug_gem_regex.match?(package_name)

            puts "#{package_state[:display_name] || package_name} (#{package_state[:version_label]})..."

            begin
              entry = build_entry(package_state: package_state)
              display_name = package_state[:display_name] || package_name

              mutex.synchronize { updates[display_name] = entry }
            rescue => e
              mutex.synchronize { failed << [package_name, e.message] }
              puts "⚠️ Failed to process #{package_name}: #{e.message}"
            end
          end
        end

        pool.shutdown
        pool.wait_for_termination

        @updates = updates
      end

      def include_package_state?(package_state)
        ecosystem == "all" || package_state[:package_scope] == ecosystem
      end

      def validate_lockfile_ecosystem!
        return if %w[all gems].include?(ecosystem)

        raise Thor::Error, "--ecosystem=#{ecosystem} requires --project because lockfile mode only supports gems"
      end

      def disambiguate_duplicate_names(package_states)
        counts = package_states.each_with_object(Hash.new(0)) do |package_state, index|
          index[package_state[:name]] += 1
        end

        package_states.map do |package_state|
          next package_state.merge(display_name: package_state[:name]) if counts[package_state[:name]] == 1

          suffix = case package_state[:package_source_file]
          when :importmap
            "importmap"
          when :package_lock
            "package-lock"
          else
            package_state[:package_scope]
          end

          package_state.merge(display_name: "#{package_state[:name]} (#{suffix})")
        end
      end

      def version_label(old_version, new_version)
        return "new → #{new_version}" if old_version.nil? && !new_version.nil?
        return "#{old_version} → removed" if !old_version.nil? && new_version.nil?
        return new_version.to_s if old_version == new_version

        "#{old_version} → #{new_version}"
      end

    end
  end
end
