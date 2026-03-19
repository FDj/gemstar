require_relative "command"

module Gemstar
  module Commands
    class Server < Command
      DEFAULT_BIND = "127.0.0.1"
      DEFAULT_PORT = 2112

      attr_reader :bind
      attr_reader :port
      attr_reader :project_inputs

      def initialize(options)
        super

        @bind = options[:bind] || DEFAULT_BIND
        @port = (options[:port] || DEFAULT_PORT).to_i
        @project_inputs = Array(options[:project]).compact
      end

      def run
        require "rackup"
        require "webrick"
        require "gemstar/web/app"

        Gemstar::Config.ensure_home_directory!

        projects = load_projects
        app = Gemstar::Web::App.build(projects: projects, config_home: Gemstar::Config.home_directory)

        puts "Gemstar server listening on http://#{bind}:#{port}"
        puts "Config home: #{Gemstar::Config.home_directory}"
        Rackup::Server.start(app: app, Host: bind, Port: port)
      end

      private

      def load_projects
        project_inputs.map { |input| Gemstar::Project.from_cli_argument(input) }
      end
    end
  end
end
