require_relative "command"
require "shellwords"

module Gemstar
  module Commands
    class Server < Command
      DEFAULT_BIND = "127.0.0.1"
      DEFAULT_PORT = 2112
      RELOAD_ENV_VAR = "GEMSTAR_RELOAD_ACTIVE"
      RELOAD_GLOB = "{lib/**/*.rb,lib/gemstar/web/templates/**/*,bin/gemstar,README.md}"

      attr_reader :bind
      attr_reader :port
      attr_reader :project_inputs
      attr_reader :reload

      def initialize(options)
        super

        @bind = options[:bind] || DEFAULT_BIND
        @port = (options[:port] || DEFAULT_PORT).to_i
        @project_inputs = normalize_project_inputs(options[:project])
        @reload = options[:reload]
      end

      def run
        restart_with_rerun if reload_requested?

        require "rackup"
        require "webrick"
        require "gemstar/request_logger"
        require "gemstar/webrick_logger"
        require "gemstar/web/app"

        Gemstar::Config.ensure_home_directory!

        projects = load_projects
        log_loaded_projects(projects)
        cache_warmer = start_background_cache_refresh(projects)
        app = Gemstar::Web::App.build(projects: projects, config_home: Gemstar::Config.home_directory, cache_warmer: cache_warmer)
        app = Gemstar::RequestLogger.new(app, io: $stderr) if debug_request_logging?

        puts "Gemstar server listening on http://#{bind}:#{port}"
        puts "Config home: #{Gemstar::Config.home_directory}"
        Rackup::Server.start(
          app: app,
          Host: bind,
          Port: port,
          AccessLog: [],
          Logger: Gemstar::WEBrickLogger.new($stderr, WEBrick::BasicLog::INFO)
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
        puts "Watching changes matching #{RELOAD_GLOB.inspect}"

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
          "--pattern",
          RELOAD_GLOB,
          "--",
          Gem.ruby,
          File.expand_path($PROGRAM_NAME)
        ] + server_arguments_without_reload
      end

      def server_arguments_without_reload
        args = [
          "server",
          "--bind", bind,
          "--port", port.to_s
        ]
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

      def start_background_cache_refresh(projects)
        gem_names = projects.flat_map do |project|
          project.current_lockfile&.specs&.keys || []
        end.uniq.sort

        return nil if gem_names.empty?

        Gemstar::CacheWarmer.new(io: $stderr, debug: debug_request_logging? || Gemstar.debug?, thread_count: 10).enqueue_many(gem_names)
      end
    end
  end
end
