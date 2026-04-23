# lib/gemstar/cli.rb
require "thor"

module Gemstar
  class CLI < Thor
    package_name "gemstar"

    map "-D" => "diff"

    class_option :verbose, type: :boolean, default: false, desc: "Enable verbose output"
    class_option :lockfile, type: :string, default: "Gemfile.lock", desc: "Lockfile path"

    desc "diff", "Show changelogs for updated gems"
    method_option :from, type: :string, desc: "Git ref or lockfile"
    method_option :to, type: :string, desc: "Git ref or lockfile"
    method_option :since, type: :string, desc: "Set --from to the latest commit before this relative time (for example: '3 weeks')"
    method_option :project, type: :string, desc: "Project directory or supported project file path"
    method_option :ecosystem, type: :string, desc: "Filter packages by ecosystem (all, gems, js)"
    method_option :format, type: :string, desc: "Output format (html or markdown)"
    method_option :output_file, type: :string, desc: "Output file path"
    method_option :debug_gem_regex, type: :string, desc: "Debug matching gems", hide: true
    def diff
      Gemstar::Commands::Diff.new(options).run
    end

    desc "server", "Start the interactive web server"
    method_option :bind, type: :string, default: "127.0.0.1", desc: "Bind address"
    method_option :port, type: :numeric, default: 2112, desc: "Port"
    method_option :project, type: :string, repeatable: true, desc: "Project directories or Gemfile paths"
    method_option :reload, type: :boolean, default: false, desc: "Restart automatically when files change"
    method_option :open, type: :boolean, default: false, desc: "Open the server root in a browser after startup"
    def server
      Gemstar::Commands::Server.new(options).run
    end

    desc "cache SUBCOMMAND ...ARGS", "Manage gemstar caches"
    subcommand "cache", Gemstar::CacheCLI

    # desc "pick", "Interactively cherry-pick and upgrade gems"
    # option :gem, type: :string, desc: "Gem name to cherry-pick"
    # def pick
    #   Gemstar::Commands::Pick.new(options).run
    # end
    #
    # desc "audit", "Run security and vulnerability checks"
    # def audit
    #   Gemstar::Commands::Audit.new.run
    # end
    #
    # desc "diff", "Show lockfile diff or GitHub comparison"
    # option :from, type: :string
    # option :to, type: :string
    # def diff
    #   Gemstar::Commands::Diff.new(options).run
    # end

    # desc "init", "Setup gem hygiene for a project"
    # def init
    #   Gemstar::Commands::Init.new.run
    # end

    def self.exit_on_failure?
      true
    end
  end

end
