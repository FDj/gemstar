require "time"

module Gemstar
  class Project
    attr_reader :directory
    attr_reader :gemfile_path
    attr_reader :lockfile_path
    attr_reader :name

    def self.from_cli_argument(input)
      expanded_input = File.expand_path(input)
      gemfile_path = if File.directory?(expanded_input)
        File.join(expanded_input, "Gemfile")
      else
        expanded_input
      end

      raise ArgumentError, "No Gemfile found for #{input}" unless File.file?(gemfile_path)
      raise ArgumentError, "#{gemfile_path} is not a Gemfile" unless File.basename(gemfile_path) == "Gemfile"

      new(gemfile_path)
    end

    def initialize(gemfile_path)
      @gemfile_path = File.expand_path(gemfile_path)
      @directory = File.dirname(@gemfile_path)
      @lockfile_path = File.join(@directory, "Gemfile.lock")
      @name = File.basename(@directory)
      @lockfile_cache = {}
      @gem_states_cache = {}
      @gem_added_on_cache = {}
      @history_cache = {}
    end

    def git_repo
      @git_repo ||= Gemstar::GitRepo.new(directory)
    end

    def git_root
      git_repo.tree_root_directory
    end

    def lockfile?
      File.file?(lockfile_path)
    end

    def current_lockfile
      return nil unless lockfile?

      @current_lockfile ||= Gemstar::LockFile.new(path: lockfile_path)
    end

    def revision_history(limit: 20)
      history_for_paths(tracked_git_paths, limit: limit)
    end

    def lockfile_revision_history(limit: 20)
      return [] unless lockfile?

      relative_path = git_repo.relative_path(lockfile_path)
      return [] if relative_path.nil?

      history_for_paths([relative_path], limit: limit)
    end

    def gemfile_revision_history(limit: 20)
      relative_path = git_repo.relative_path(gemfile_path)
      return [] if relative_path.nil?

      history_for_paths([relative_path], limit: limit)
    end

    def default_from_revision_id
      default_changed_lockfile_revision_id ||
        gemfile_revision_history(limit: 1).first&.dig(:id) ||
        "worktree"
    end

    def revision_options(limit: 20)
      [{ id: "worktree", label: "Worktree", description: "Current Gemfile.lock in the working tree" }] +
        revision_history(limit: limit).map do |revision|
          {
            id: revision[:id],
            label: revision[:short_sha],
            description: "#{revision[:subject]} (#{revision[:authored_at].strftime("%Y-%m-%d %H:%M")})"
          }
        end
    end

    def lockfile_for_revision(revision_id)
      cache_key = revision_id || "worktree"
      return @lockfile_cache[cache_key] if @lockfile_cache.key?(cache_key)
      return @lockfile_cache[cache_key] = current_lockfile if revision_id.nil? || revision_id == "worktree"
      return nil unless lockfile?

      relative_lockfile_path = git_repo.relative_path(lockfile_path)
      return nil if relative_lockfile_path.nil?

      content = git_repo.try_git_command(["show", "#{revision_id}:#{relative_lockfile_path}"])
      return nil if content.nil? || content.empty?

      @lockfile_cache[cache_key] = Gemstar::LockFile.new(content: content)
    end

    def gem_states(from_revision_id: default_from_revision_id, to_revision_id: "worktree")
      cache_key = [from_revision_id, to_revision_id]
      return @gem_states_cache[cache_key] if @gem_states_cache.key?(cache_key)

      from_lockfile = lockfile_for_revision(from_revision_id)
      to_lockfile = lockfile_for_revision(to_revision_id)
      from_specs = from_lockfile&.specs || {}
      to_specs = to_lockfile&.specs || {}

      @gem_states_cache[cache_key] = (from_specs.keys | to_specs.keys).map do |gem_name|
        old_version = from_specs[gem_name]
        new_version = to_specs[gem_name]
        bundle_origins = to_lockfile&.origins_for(gem_name) || []

        {
          name: gem_name,
          old_version: old_version,
          new_version: new_version,
          status: gem_status(old_version, new_version),
          version_label: version_label(old_version, new_version),
          bundle_origins: bundle_origins,
          bundle_origin_labels: bundle_origin_labels(bundle_origins)
        }
      end.sort_by { |gem| gem[:name] }
    end

    def gem_added_on(gem_name, revision_id: "worktree")
      cache_key = [gem_name, revision_id]
      return @gem_added_on_cache[cache_key] if @gem_added_on_cache.key?(cache_key)
      return nil unless lockfile?

      target_lockfile = lockfile_for_revision(revision_id)
      return @gem_added_on_cache[cache_key] = nil unless target_lockfile&.specs&.key?(gem_name)

      relative_path = git_repo.relative_path(lockfile_path)
      return @gem_added_on_cache[cache_key] = nil if relative_path.nil?

      first_seen_revision = history_for_paths([relative_path], limit: nil, reverse: true).find do |revision|
        lockfile = lockfile_for_revision(revision[:id])
        lockfile&.specs&.key?(gem_name)
      end

      return @gem_added_on_cache[cache_key] = worktree_added_on_info if first_seen_revision.nil? && revision_id == "worktree"
      return @gem_added_on_cache[cache_key] = nil unless first_seen_revision

      @gem_added_on_cache[cache_key] = {
        project_name: name,
        date: first_seen_revision[:authored_at].strftime("%Y-%m-%d"),
        revision: first_seen_revision[:short_sha],
        revision_url: revision_url(first_seen_revision[:id]),
        worktree: false
      }
    end

    private

    def default_changed_lockfile_revision_id
      return nil unless lockfile?

      current_specs = current_lockfile&.specs || {}

      lockfile_revision_history(limit: 20).find do |revision|
        revision_lockfile = lockfile_for_revision(revision[:id])
        revision_lockfile && revision_lockfile.specs != current_specs
      end&.dig(:id)
    end

    def history_for_paths(paths, limit: 20, reverse: false)
      return [] if git_root.nil? || git_root.empty?
      return [] if paths.empty?

      cache_key = [paths.sort, limit, reverse]
      return @history_cache[cache_key] if @history_cache.key?(cache_key)

      output = git_repo.log_for_paths(paths, limit: limit, reverse: reverse)
      return [] if output.nil? || output.empty?

      @history_cache[cache_key] = output.lines.filter_map do |line|
        full_sha, short_sha, authored_at, subject = line.strip.split("\u001f", 4)
        next if full_sha.nil?

        {
          id: full_sha,
          full_sha: full_sha,
          short_sha: short_sha,
          authored_at: Time.iso8601(authored_at),
          subject: subject
        }
      end
    rescue ArgumentError
      []
    end

    def tracked_git_paths
      [gemfile_path, lockfile_path].filter_map do |path|
        next unless File.file?(path)

        git_repo.relative_path(path)
      end.uniq
    end

    def gem_status(old_version, new_version)
      return :added if old_version.nil? && !new_version.nil?
      return :removed if !old_version.nil? && new_version.nil?
      return :unchanged if old_version == new_version

      comparison = compare_versions(new_version, old_version)
      return :upgrade if comparison.positive?
      return :downgrade if comparison.negative?

      :changed
    end

    def version_label(old_version, new_version)
      return "new → #{new_version}" if old_version.nil? && !new_version.nil?
      return "#{old_version} → removed" if !old_version.nil? && new_version.nil?
      return new_version.to_s if old_version == new_version

      "#{old_version} → #{new_version}"
    end

    def compare_versions(left, right)
      Gem::Version.new(left.to_s.gsub(/-[\w\-]+$/, "")) <=> Gem::Version.new(right.to_s.gsub(/-[\w\-]+$/, ""))
    rescue ArgumentError
      left.to_s <=> right.to_s
    end

    def bundle_origin_labels(origins)
      Array(origins).map do |origin|
        next "Gemfile" if origin[:type] == :direct

        ["Gemfile", *origin[:path]].join(" → ")
      end.compact.uniq
    end

    def worktree_added_on_info
      return nil unless File.file?(lockfile_path)

      {
        project_name: name,
        date: File.mtime(lockfile_path).strftime("%Y-%m-%d"),
        revision: "Worktree",
        revision_url: nil,
        worktree: true
      }
    end

    def revision_url(full_sha)
      repo_url = git_repo.origin_repo_url
      return nil unless repo_url&.include?("github.com")

      "#{repo_url}/commit/#{full_sha}"
    end
  end
end
