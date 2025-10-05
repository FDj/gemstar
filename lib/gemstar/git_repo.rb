module Gemstar
  class GitRepo
    def initialize(specified_directory)
      @specified_directory = specified_directory || Dir.pwd
      @tree_root_directory = find_git_root(File.dirname(@specified_directory))
    end

    def find_git_root(directory)
      # return directory if File.directory?(File.join(directory, ".git"))
      # find_git_root(File.dirname(directory))

      run_git_command(%W[rev-parse --show-toplevel])
    end

    def git_client
      "git"
    end

    def run_git_command(command, in_directory: @specified_directory, strip: true)
      git_command = [git_client]
      git_command += ["-C", in_directory] if in_directory
      git_command += command

      puts %[run_git_command (joined): #{git_command.join(" ")}] if Gemstar.debug?

      output = IO.popen(git_command, err: [:child, :out],
        &:read)
      strip ? output.strip : output
    end

    def resolve_commit(revish, default_branch: "HEAD")
      # If it looks like a pure date (or you want to support "date only"),
      # map it to "latest commit before date on default_branch".
      if revish =~ /\d{4}-\d{2}-\d{2}/ || revish =~ /\d{1,2}:\d{2}/i
        sha = run_git_command(["rev-list", "-1", "--before", revish, default_branch])
        raise "No commit before #{revish} on #{default_branch}" if sha.empty?
        return sha
      end

      # Otherwise let Git parse whatever the user typed.
      sha = run_git_command(%W[rev-parse --verify #{revish}^{commit}])
      raise "Unknown revision: #{revish}" if sha.empty?
      sha
    end

    def show_blob_at(revish, path)
      commit = resolve_commit(revish)
      run_git_command(["show", "#{commit}:#{path}"])
    end

    def get_full_path(path)
      run_git_command(["ls-files", "--full-name", "--", path])
    end
  end
end
