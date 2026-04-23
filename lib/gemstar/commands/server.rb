require_relative "command"
require "socket"
require "shellwords"
require "rbconfig"

module Gemstar
  module Commands
    class Server < Command
      DEFAULT_BIND = "127.0.0.1"
      DEFAULT_PORT = 2112
      RELOAD_ENV_VAR = "GEMSTAR_RELOAD_ACTIVE"
      RELOAD_GLOB = "{lib/**/*.rb,lib/gemstar/web/templates/**/*,bin/gemstar,README.md}"
      RELOAD_DIRS = %w[lib bin].freeze

      attr_reader :bind
      attr_reader :port
      attr_reader :project_inputs
      attr_reader :reload
      attr_reader :open_browser
      attr_reader :explicit_port

      def initialize(options)
        super

        @bind = options[:bind] || DEFAULT_BIND
        @explicit_port = !options[:port].nil?
        @port = (options[:port] || DEFAULT_PORT).to_i
        @project_inputs = normalize_project_inputs(options[:project])
        @reload = options[:reload]
        @open_browser = options[:open]
      end

      def run
        restart_with_rerun if reload_requested?

        require "rackup"
        require "webrick"
        require "gemstar/request_logger"
        require "gemstar/webrick_logger"
        require "gemstar/web/app"

        Gemstar::Config.ensure_home_directory!
        @port = resolve_port

        projects = load_projects
        log_loaded_projects(projects)
        cache_warmer = build_cache_warmer
        app = Gemstar::Web::App.build(projects: projects, config_home: Gemstar::Config.home_directory, cache_warmer: cache_warmer)
        app = Gemstar::RequestLogger.new(app, io: $stderr) if debug_request_logging?

        puts "Gemstar server listening on http://#{bind}:#{port}"
        puts "Config home: #{Gemstar::Config.home_directory}"
        Rackup::Server.start(
          app: app,
          server: "webrick",
          Host: bind,
          Port: port,
          AccessLog: [],
          Logger: Gemstar::WEBrickLogger.new($stderr, WEBrick::BasicLog::INFO),
          StartCallback: server_start_callback(projects, cache_warmer)
        )
      end

      private

      def normalize_project_inputs(project_option)
        inputs = Array(project_option).compact.map(&:to_s)
        return ["."] if inputs.empty?

        inputs.uniq
      end

      def reload_requested?
        reload && ENV[RELOAD_ENV_VAR] != "1"
      end

      def restart_with_rerun
        rerun_executable = find_rerun_executable
        unless rerun_executable
          raise Thor::Error, "The `rerun` gem is not installed. Run `bundle install` and try `gemstar server --reload` again."
        end

        puts "Starting gemstar server in reload mode..."
        puts "Watching directories #{RELOAD_DIRS.join(", ")} with glob #{RELOAD_GLOB.inspect}"

        env = ENV.to_h.merge(RELOAD_ENV_VAR => "1")
        exec env, *rerun_command(rerun_executable)
      end

      def find_rerun_executable
        Gem.bin_path("rerun", "rerun")
      rescue Gem::Exception
        nil
      end

      def rerun_command(rerun_executable)
        [
          rerun_executable,
          "--dir",
          RELOAD_DIRS.join(","),
          "--pattern",
          RELOAD_GLOB,
          "--signal",
          "INT,KILL",
          "--wait",
          "1",
          "--name",
          "Gemstar",
          "--background",
          "--",
          *server_runner_command,
          *server_arguments_without_reload
        ]
      end

      def server_runner_command
        return %w[bundle exec gemstar] if ENV["BUNDLE_GEMFILE"]

        repo_executable = File.expand_path("../../../bin/gemstar", __dir__)
        return [repo_executable] if File.exist?(repo_executable)

        gem_executable = Gem.bin_path("gemstar", "gemstar")
        return [gem_executable] if gem_executable

        ["gemstar"]
      rescue Gem::Exception
        ["gemstar"]
      end

      def server_arguments_without_reload
        args = [
          "server",
          "--bind", bind
        ]
        args += ["--port", port.to_s] if explicit_port
        args << "--open" if open_browser
        project_inputs.each do |project|
          args << "--project"
          args << project
        end
        args
      end

      def load_projects
        project_inputs.map { |input| Gemstar::Project.from_cli_argument(input) }
      end

      def log_loaded_projects(projects)
        return unless debug_request_logging?

        $stderr.puts "[gemstar] project inputs: #{project_inputs.inspect}"
        $stderr.puts "[gemstar] loaded projects (#{projects.count}): #{projects.map(&:directory).inspect}"
      end

      def debug_request_logging?
        ENV["DEBUG"] == "1"
      end

      def resolve_port
        return port if explicit_port

        find_available_port(starting_at: port)
      end

      def find_available_port(starting_at:, limit: 100)
        starting_at.upto(starting_at + limit - 1) do |candidate|
          return candidate if port_available?(candidate)
        end

        raise Thor::Error, "No available port found from #{starting_at} to #{starting_at + limit - 1}"
      end

      def port_available?(candidate)
        server = TCPServer.new(bind, candidate)
        server.close
        true
      rescue Errno::EADDRINUSE, Errno::EACCES, SocketError
        false
      end

      def build_cache_warmer
        Gemstar::CacheWarmer.new(io: $stderr, debug: debug_request_logging? || Gemstar.debug?, thread_count: 10)
      end

      def start_background_cache_refresh(projects, cache_warmer)
        package_states = projects.flat_map do |project|
          project.gem_states(from_revision_id: "worktree", to_revision_id: "worktree")
        end

        return nil if package_states.empty?

        cache_warmer.enqueue_many(package_states)
      end

      def server_start_callback(projects, cache_warmer)
        proc do
          Thread.new do
            sleep 0.15
            start_background_cache_refresh(projects, cache_warmer)
            launch_browser
          end
        end
      end

      def launch_browser
        return unless open_browser

        command = browser_command(root_url)
        return unless command

        pid = spawn(*command, out: File::NULL, err: File::NULL)
        Process.detach(pid)
      rescue StandardError => e
        warn "Could not open browser automatically: #{e.message}"
      end

      def browser_command(url)
        host_os = RbConfig::CONFIG["host_os"].to_s

        if host_os.include?("darwin")
          [find_executable("open") || "/usr/bin/open", url]
        elsif host_os.match?(/linux|bsd/)
          executable = find_executable("xdg-open")
          executable ? [executable, url] : nil
        elsif host_os.match?(/mswin|mingw|cygwin/)
          ["cmd", "/c", "start", "", url]
        end
      end

      def find_executable(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
          candidate = File.join(directory, name)
          return candidate if File.file?(candidate) && File.executable?(candidate)
        end

        nil
      end

      def root_url
        "http://#{bind}:#{port}/"
      end
    end
  end
end
