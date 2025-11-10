# frozen_string_literal: true

require_relative "command"
require "concurrent-ruby"
require "tempfile"

module Gemstar
  module Commands
    class Diff < Command
      attr_reader :updates
      attr_reader :failed
      attr_reader :from
      attr_reader :to
      attr_reader :lockfile
      attr_reader :git_repo
      attr_reader :lockfile_full_path
      attr_reader :output_file

      def initialize(options)
        super

        @debug_gem_regex = Regexp.new(options[:debug_gem_regex] || ENV["GEMSTAR_DEBUG_GEM_REGEX"] || ".*")

        @from = options[:from] || "HEAD"
        @to = options[:to]
        @lockfile = options[:lockfile] || "Gemfile.lock"
        @output_file = options[:output_file] || "gem_update_changelog.html"

        @git_repo = Gemstar::GitRepo.new(File.dirname(@lockfile))
      end

      def run
        # logic to diff from/to, find updated gems, fetch changelogs

        #+++ edit_gitignore?

        @lockfile_full_path = git_repo.get_full_path(File.basename(lockfile))
        puts "Lockfile path: #{lockfile_full_path}"

        old = LockFile.new(content: git_repo.show_blob_at(@from, lockfile_full_path))
        new = @to ?
                LockFile.new(content: git_repo.show_blob_at(@to, lockfile_full_path)) :
                LockFile.new(path: lockfile)

        collect_updates(new_lockfile: new, old_lockfile: old)

        html = Outputs::HTML.new.render_diff(self)
        File.write(output_file, html)
        puts "✅ gem_update_changelog.html created."

        if failed.any?
          puts "\n⚠️ The following gems failed to process:"
          failed.each { |gem, msg| puts "  - #{gem}: #{msg}" }
        end
      end

      private

      def build_entry(gem_name:, old_version:, new_version:)
        metadata = Gemstar::RubyGemsMetadata.new(gem_name)
        repo_url = metadata.repo_uri
        changelog = Gemstar::ChangeLog.new(metadata)
        sections = changelog.extract_relevant_sections(old_version, new_version)

        compare_url = if repo_url && old_version
          tag_from_v = "v#{old_version}"
          tag_to_v = "v#{new_version}"
          tag_from_raw = old_version
          tag_to_raw = new_version

          url_v = "#{repo_url}/compare/#{tag_from_v}...#{tag_to_v}"
          url_raw = "#{repo_url}/compare/#{tag_from_raw}...#{tag_to_raw}"

          begin
            URI.open(url_v, read_timeout: 4) # TODO use a real HTTP client
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

        entry
      end

      def collect_updates(new_lockfile:, old_lockfile:)
        @updates = {}
        @failed = []
        mutex = Mutex.new
        pool = Concurrent::FixedThreadPool.new(10)

        new_lockfile.specs.keys.sort.each do |gem_name|
          pool.post do
            next unless @debug_gem_regex.match?(gem_name)

            old_version = old_lockfile.specs[gem_name]
            new_version = new_lockfile.specs[gem_name]
            next if old_version == new_version

            puts "#{gem_name} (#{old_version || "new"} → #{new_version})..."

            begin
              entry = build_entry(gem_name: gem_name, old_version: old_version, new_version: new_version)

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
      end
    end
  end
end
