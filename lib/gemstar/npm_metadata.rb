require "open-uri"
require "uri"
require "json"

module Gemstar
  class NpmMetadata
    def initialize(package_name)
      @gem_name = package_name
    end

    attr_reader :gem_name

    def cache_key
      "npm-#{gem_name}"
    end

    def meta(cache_only: false, force_refresh: false)
      return @meta if !cache_only && defined?(@meta)

      json = if cache_only
        Cache.peek(cache_key)
      else
        url = "https://registry.npmjs.org/#{URI.encode_www_form_component(gem_name)}"
        Cache.fetch(cache_key, force: force_refresh) do
          URI.open(url, read_timeout: 8).read
        end
      end

      parsed = begin
        JSON.parse(json) if json
      rescue
        nil
      end

      normalized = normalize_meta(parsed)
      @meta = normalized unless cache_only
      normalized
    end

    def repo_uri(cache_only: false, force_refresh: false)
      resolved_meta = meta(cache_only: cache_only, force_refresh: force_refresh)
      return nil unless resolved_meta

      return @repo_uri if !cache_only && defined?(@repo_uri)

      repo = begin
        uri = resolved_meta["source_code_uri"]
        uri ||= resolved_meta["homepage_uri"] if resolved_meta["homepage_uri"].to_s.include?("github.com")
        uri ||= ""

        uri = uri.sub(/\Agit\+/, "")
        uri = uri.sub("git://", "https://")
        uri = uri.sub("http://", "https://")
        uri = uri.gsub(/\.git$/, "")

        if uri.include?("github.com")
          uri = uri[%r{\Ahttps?://github\.com/[^/]+/[^/]+}] || uri
        end

        uri
      end

      @repo_uri = repo unless cache_only
      repo
    end

    private

    def normalize_meta(parsed)
      return nil unless parsed.is_a?(Hash)

      latest_version = parsed.dig("dist-tags", "latest").to_s
      version_meta = parsed.dig("versions", latest_version)
      source_code_uri = repository_url(version_meta || parsed)
      homepage_uri = homepage_url(version_meta || parsed)

      {
        "name" => parsed["name"],
        "version" => latest_version.empty? ? nil : latest_version,
        "info" => (version_meta || parsed)["description"],
        "homepage_uri" => homepage_uri,
        "source_code_uri" => source_code_uri,
        "project_uri" => "https://www.npmjs.com/package/#{parsed["name"]}",
        "documentation_uri" => homepage_uri
      }
    end

    def repository_url(meta)
      repository = meta["repository"]
      case repository
      when Hash
        repository["url"]
      when String
        repository
      end
    end

    def homepage_url(meta)
      meta["homepage"]
    end
  end
end
