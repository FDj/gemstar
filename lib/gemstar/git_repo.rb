require "open3"
require "pathname"

module Gemstar
  class GitRepo
    attr_reader :tree_root_directory

    def initialize(specified_directory)
      @specified_directory = specified_directory || Dir.pwd
      search_directory = if File.directory?(@specified_directory)
        @specified_directory
      else
        File.dirname(@specified_directory)
      end
      @tree_root_directory = find_git_root(search_directory)
    end

    def find_git_root(directory)
      try_git_command(%W[rev-parse --show-toplevel], in_directory: directory)
    end

    def git_client
      "git"
    end

    def build_git_command(command, in_directory: @specified_directory)
      git_command = [git_client]
      git_command += ["-C", in_directory] if in_directory
      git_command + command
    end

    def run_git_command(command, in_directory: @specified_directory, strip: true)
      git_command = build_git_command(command, in_directory:)

      puts %[run_git_command (joined): #{git_command.join(" ")}] if Gemstar.debug?

      output = IO.popen(git_command, err: [:child, :out],
        &:read)
      strip ? output.strip : output
    end

    def try_git_command(command, in_directory: @specified_directory, strip: true)
      git_command = build_git_command(command, in_directory:)

      puts %[try_git_command (joined): #{git_command.join(" ")}] if Gemstar.debug?

      output, status = Open3.capture2e(*git_command)
      return nil unless status.success?

      strip ? output.strip : output
    end

    def resolve_commit(revish, default_branch: "HEAD")
      # If it looks like a pure date (or you want to support "date only"),
      # map it to "latest commit before date on default_branch".
      if revish =~ /\d{4}-\d{2}-\d{2}/ || revish =~ /\d{1,2}:\d{2}/i
        return commit_before(revish, default_branch:)
      end

      # Otherwise let Git parse whatever the user typed.
      sha = run_git_command(%W[rev-parse --verify #{revish}^{commit}])
      raise "Unknown revision: #{revish}" if sha.empty?
      sha
    end

    def commit_before(time_expression, default_branch: "HEAD")
      sha = run_git_command(["rev-list", "-1", "--before", time_expression, default_branch])
      raise "No commit before #{time_expression} on #{default_branch}" if sha.empty?

      sha
    end

    def show_blob_at(revish, path)
      commit = resolve_commit(revish)
      run_git_command(["show", "#{commit}:#{path}"])
    end

    def get_full_path(path)
      run_git_command(["ls-files", "--full-name", "--", path])
    end

    def relative_path(path)
      return nil if tree_root_directory.nil? || tree_root_directory.empty?

      Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(tree_root_directory)).to_s
    rescue ArgumentError
      nil
    end

    def origin_repo_url
      remote = try_git_command(["remote", "get-url", "origin"])
      return nil if remote.nil? || remote.empty?

      normalize_remote_url(remote)
    end

    def log_for_paths(paths, limit: 20, reverse: false)
      return "" if tree_root_directory.nil? || tree_root_directory.empty? || paths.empty?

      format = "%H%x1f%h%x1f%aI%x1f%s"
      command = ["log"]
      command += ["-n", limit.to_s] if limit
      command << "--reverse" if reverse
      command += ["--pretty=format:#{format}", "--", *paths]

      run_git_command(command, in_directory: tree_root_directory)
    end

    def commits_between(from_revision, to_revision = "HEAD")
      return [] if tree_root_directory.nil? || tree_root_directory.empty?

      range = "#{from_revision}..#{to_revision || "HEAD"}"
      format = "%H%x1f%h%x1f%aI%x1f%s"
      output = try_git_command(["log", "--reverse", "--pretty=format:#{format}", range], in_directory: tree_root_directory)
      return [] if output.nil? || output.empty?

      output.lines.filter_map { |line| parse_commit_log_line(line) }
    end

    def commit_info(revision)
      return nil if tree_root_directory.nil? || tree_root_directory.empty?

      format = "%H%x1f%h%x1f%aI%x1f%s"
      output = try_git_command(["show", "-s", "--pretty=format:#{format}", revision], in_directory: tree_root_directory)
      return nil if output.nil? || output.empty?

      parse_commit_log_line(output)
    end

    private

    def parse_commit_log_line(line)
      full_sha, short_sha, authored_at, subject = line.strip.split("\u001f", 4)
      return nil if full_sha.nil? || full_sha.empty?

      {
        id: full_sha,
        short_sha: short_sha,
        authored_at: authored_at,
        subject: subject
      }
    end

    def normalize_remote_url(remote)
      normalized = remote.strip.sub(%r{\.git\z}, "")

      if normalized.start_with?("git@github.com:")
        path = normalized.delete_prefix("git@github.com:")
        return "https://github.com/#{path}"
      end

      if normalized.start_with?("ssh://git@github.com/")
        path = normalized.delete_prefix("ssh://git@github.com/")
        return "https://github.com/#{path}"
      end

      normalized.sub(%r{\Ahttp://}, "https://")
    end
  end
end
