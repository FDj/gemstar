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

    def revision_history(limit: 20)
      return [] if git_root.nil? || git_root.empty?

      tracked_paths = [gemfile_path, lockfile_path].filter_map do |path|
        next unless File.file?(path)

        git_repo.relative_path(path)
      end

      return [] if tracked_paths.empty?

      output = git_repo.log_for_paths(tracked_paths.uniq, limit:)
      return [] if output.nil? || output.empty?

      output.lines.filter_map do |line|
        full_sha, short_sha, authored_at, subject = line.strip.split("\u001f", 4)
        next if full_sha.nil?

        {
          full_sha: full_sha,
          short_sha: short_sha,
          authored_at: Time.iso8601(authored_at),
          subject: subject
        }
      end
    rescue ArgumentError
      []
    end
  end
end
