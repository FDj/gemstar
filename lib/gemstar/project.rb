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
      lockfile_revision_history(limit: 1).first&.dig(:id) ||
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
      return current_lockfile if revision_id.nil? || revision_id == "worktree"
      return nil unless lockfile?

      relative_lockfile_path = git_repo.relative_path(lockfile_path)
      return nil if relative_lockfile_path.nil?

      content = git_repo.try_git_command(["show", "#{revision_id}:#{relative_lockfile_path}"])
      return nil if content.nil? || content.empty?

      Gemstar::LockFile.new(content: content)
    end

    def gem_states(from_revision_id: default_from_revision_id, to_revision_id: "worktree")
      from_specs = lockfile_for_revision(from_revision_id)&.specs || {}
      to_specs = lockfile_for_revision(to_revision_id)&.specs || {}

      (from_specs.keys | to_specs.keys).map do |gem_name|
        old_version = from_specs[gem_name]
        new_version = to_specs[gem_name]

        {
          name: gem_name,
          old_version: old_version,
          new_version: new_version,
          status: gem_status(old_version, new_version),
          version_label: version_label(old_version, new_version)
        }
      end.sort_by do |gem|
        [status_rank(gem[:status]), gem[:name]]
      end
    end

    private

    def history_for_paths(paths, limit: 20)
      return [] if git_root.nil? || git_root.empty?
      return [] if paths.empty?

      output = git_repo.log_for_paths(paths, limit: limit)
      return [] if output.nil? || output.empty?

      output.lines.filter_map do |line|
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
      return "new -> #{new_version}" if old_version.nil? && !new_version.nil?
      return "#{old_version} -> removed" if !old_version.nil? && new_version.nil?
      return new_version.to_s if old_version == new_version

      "#{old_version} -> #{new_version}"
    end

    def status_rank(status)
      {
        upgrade: 0,
        added: 1,
        downgrade: 2,
        removed: 3,
        changed: 4,
        unchanged: 5
      }.fetch(status, 9)
    end

    def compare_versions(left, right)
      Gem::Version.new(left.to_s.gsub(/-[\w\-]+$/, "")) <=> Gem::Version.new(right.to_s.gsub(/-[\w\-]+$/, ""))
    rescue ArgumentError
      left.to_s <=> right.to_s
    end
  end
end
