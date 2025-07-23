require_relative "command.rb"
require "concurrent-ruby"

module Gemstar
  module Commands
    class Diff < Command
      attr_reader :updates
      attr_reader :failed
      attr_reader :from
      attr_reader :to
      attr_reader :lockfile

      def initialize(options)
        super

        @from = options[:from]
        @to = options[:to]
        @lockfile = options[:lockfile]
      end

      def run
        # logic to diff from/to, find updated gems, fetch changelogs

        #+++ edit_gitignore

        # Save previous lockfile from git
        old_lockfile = IO.popen(%w[git show HEAD:Gemfile.lock], &:read)
        File.write("Gemfile.lock.old", old_lockfile)

        old = LockFile.new("Gemfile.lock.old")
        new = LockFile.new("Gemfile.lock")

        @updates = {}
        @failed = []
        mutex = Mutex.new
        pool = Concurrent::FixedThreadPool.new(10)

        (new.specs.keys).each do |gem_name|
          pool.post do
            old_version = old.specs[gem_name]
            new_version = new.specs[gem_name]
            next if old_version == new_version

            puts "Processing #{gem_name} (#{old_version || 'new'} → #{new_version})..."

            begin
              metadata = Gemstar::RubyGemsMetadata.new(gem_name)
              repo_url = metadata.extract_github_repo_url
              changelog = Gemstar::ChangeLog.new(repo_url, gem_name)
              sections = changelog.extract_relevant_sections(old_version, new_version)

              # release_versions = []
              # if repo_url && (!sections || sections.empty?)
              #   release_versions = generate_version_range(old_version || "0.0.0", new_version)
              # end

              # release_urls = if repo_url && release_versions.any?
              #                  release_versions.map { |ver| "#{repo_url}/releases/tag/#{ver}" }
              #                else
              #                  []
              #                end

              # puts "Versions in changelog for #{gem_name}: #{sections.keys.inspect}" if sections

              compare_url = if repo_url && old_version
                              tag_from_v = "v#{old_version}"
                              tag_to_v = "v#{new_version}"
                              tag_from_raw = old_version
                              tag_to_raw = new_version

                              url_v = "#{repo_url}/compare/#{tag_from_v}...#{tag_to_v}"
                              url_raw = "#{repo_url}/compare/#{tag_from_raw}...#{tag_to_raw}"

                              begin
                                URI.open(url_v, read_timeout: 4)
                                url_v
                              rescue
                                url_raw
                              end
                            end

              homepage_url = metadata.meta["homepage_uri"] || metadata.meta["source_code_uri"] || "https://rubygems.org/gems/#{gem_name}"
              description = metadata.meta["info"]

              entry = {
                old: old_version,
                new: new_version,
                homepage_url: homepage_url,
                description: description
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

              mutex.synchronize { updates[gem_name] = entry }
            rescue => e
              mutex.synchronize { failed << [gem_name, e.message] }
              puts "⚠️ Failed to process #{gem_name}: #{e.message}"
            end
          end
        end

        pool.shutdown
        pool.wait_for_termination

        @updates = updates

        html = Outputs::HTML.new.render_diff(self)
        File.write("gem_update_changelog.html", html)
        puts "✅ Written to gem_update_changelog.html"

        if failed.any?
          puts "\n⚠️ The following gems failed to process:"
          failed.each { |gem, msg| puts "  - #{gem}: #{msg}" }
        end

        File.delete("Gemfile.lock.old") if File.exist?("Gemfile.lock.old")

      end

    end
  end
end
