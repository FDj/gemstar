require "open-uri"
require "uri"
require "json"
require "date"
require "time"
require_relative "remote_repository"

module Gemstar
  class RubyGemsMetadata
    RUBY_GEMS_METADATA_PATH = File.expand_path("data/ruby_gems_metadata.json", __dir__)

    def initialize(gem_name)
      @gem_name = gem_name
    end

    attr_reader :gem_name

    def self.package_metadata
      @package_metadata ||= begin
        JSON.parse(File.read(RUBY_GEMS_METADATA_PATH))
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end
    end

    def cache_key
      "rubygems-#{gem_name}"
    end

    def meta(cache_only: false, force_refresh: false)
      return @meta if !cache_only && defined?(@meta)

      json = if cache_only
        Cache.peek(cache_key)
      else
        url = "https://rubygems.org/api/v1/gems/#{URI.encode_www_form_component(gem_name)}.json"
        Cache.fetch(cache_key, force: force_refresh) do
          URI.open(url).read
        end
      end

      parsed = begin
        JSON.parse(json) if json
      rescue
        nil
      end

      @meta = parsed unless cache_only
      parsed
    end

    def repo_uri(cache_only: false, force_refresh: false)
      resolved_meta = meta(cache_only: cache_only, force_refresh: force_refresh)
      return nil unless resolved_meta

      return @repo_uri if !cache_only && defined?(@repo_uri)

      repo = begin
               uri = resolved_meta["source_code_uri"]

               if uri.nil?
                 uri = resolved_meta["homepage_uri"]
                 if uri&.include?("github.com")
                   uri = uri[%r{http[s?]://github\.com/[^/]+/[^/]+}]
                 end
               end

               uri ||= ""

               uri = uri.sub("http://", "https://")

               uri = uri.gsub(/\.git$/, "")

               if uri.include?("github.io")
                 uri = uri.sub(%r{\Ahttps?://([\w-]+)\.github\.io/([^/]+)}) do
                   "https://github.com/#{$1}/#{$2}"
                 end
               end

               if uri.include?("github.com")
                 uri = uri[%r{\Ahttps?://github\.com/[^/]+/[^/]+}] || uri
               end

               uri
             end

      @repo_uri = repo unless cache_only
      repo
    end

    def changelog_sections(versions: nil, cache_only: false, force_refresh: false)
      Gemstar::ChangeLog.new(self).sections(cache_only: cache_only, force_refresh: force_refresh)
    end

    def registry_release_dates(cache_only: false, force_refresh: false)
      cache_key = "rubygems-versions-#{gem_name}"
      json = if cache_only
        Cache.peek(cache_key)
      else
        url = "https://rubygems.org/api/v1/versions/#{URI.encode_www_form_component(gem_name)}.json"
        Cache.fetch(cache_key, force: force_refresh) do
          URI.open(url, read_timeout: 8).read
        end
      end

      Array(JSON.parse(json)).each_with_object({}) do |version, dates|
        number = version["number"].to_s
        created_at = version["created_at"].to_s
        next if number.empty? || created_at.empty?

        dates[number] = format_registry_release_date(created_at)
      end.compact
    rescue JSON::ParserError
      {}
    end

    def warm_cache(versions: nil)
      meta
      repo_uri
      changelog_sections(versions: versions)
    end

    def discover_github_tag_sections?
      false
    end

    def github_tag_candidates(version)
      raw = version.to_s
      [raw, (raw.start_with?("v") ? raw : "v#{raw}")].uniq
    end

    def github_tag_matches?(tag_name)
      true
    end

    def changelog_source(repo_uri:, cache_only: false, force_refresh: false)
      override = package_metadata.dig("changelog")
      if override
        override_paths = Array(override["paths"]).compact
        override_branches = Array(override["branches"]).compact
        override_branches = [""] if override_branches.empty? && override["raw_base"]
        return {
          base: expand_metadata_template(override["raw_base"] || github_raw_base(repo_uri)),
          paths: override_paths.empty? ? Gemstar::ChangeLog::DEFAULT_CHANGELOG_PATHS : override_paths,
          branches: override_branches.empty? ? RemoteRepository.new(github_raw_base(repo_uri)).find_main_branch(cache_only: cache_only, force_refresh: force_refresh) : override_branches
        }
      end

      base = github_raw_base(repo_uri)
      {
        base: base,
        paths: Gemstar::ChangeLog::DEFAULT_CHANGELOG_PATHS,
        branches: RemoteRepository.new(base).find_main_branch(cache_only: cache_only, force_refresh: force_refresh)
      }
    end

    def package_metadata
      self.class.package_metadata.find do |pattern, _metadata|
        File.fnmatch?(pattern, gem_name)
      end&.last || {}
    end

    private

    def github_raw_base(repo_uri)
      repo_uri.sub("https://github.com", "https://raw.githubusercontent.com").chomp("/")
    end

    def expand_metadata_template(value)
      value.to_s.gsub("{gem_name}", gem_name)
    end

    def format_registry_release_date(datetime)
      if datetime.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        date = Date.strptime(datetime.to_s, "%Y-%m-%d")
        return date.strftime("%b #{date.day}, %Y")
      end

      time = Time.parse(datetime.to_s).utc
      time.strftime("%b #{time.day}, %Y")
    rescue ArgumentError
      nil
    end

  end
end
