require "open-uri"
require "uri"
require "json"

module Gemstar
  class RubyGemsMetadata
    def initialize(gem_name)
      @gem_name = gem_name
    end

    attr_reader :gem_name

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

  end
end
