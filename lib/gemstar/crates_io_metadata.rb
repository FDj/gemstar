# frozen_string_literal: true

require "json"
require "open-uri"
require "time"
require "uri"
require_relative "version"

module Gemstar
  class CratesIOMetadata
    USER_AGENT = "gemstar/#{Gemstar::VERSION} (+https://github.com/FDj/gemstar)"

    def initialize(crate_name)
      @crate_name = crate_name
    end

    attr_reader :crate_name

    alias_method :gem_name, :crate_name

    def cache_key
      "crates-io-#{crate_name}"
    end

    def meta(cache_only: false, force_refresh: false)
      return @meta if !cache_only && defined?(@meta)

      parsed = raw_meta(cache_only: cache_only, force_refresh: force_refresh)
      normalized = normalize_meta(parsed)
      @meta = normalized unless cache_only
      normalized
    end

    def repo_uri(cache_only: false, force_refresh: false)
      resolved_meta = meta(cache_only: cache_only, force_refresh: force_refresh)
      return nil unless resolved_meta
      return @repo_uri if !cache_only && defined?(@repo_uri)

      uri = normalize_repo_uri(resolved_meta["source_code_uri"])
      @repo_uri = uri unless cache_only
      uri
    end

    def changelog_sections(versions: nil, cache_only: false, force_refresh: false, use_github_cli: false)
      requested_versions = Array(versions).compact
      changelog = Gemstar::ChangeLog.new(self)
      if requested_versions.empty?
        changelog.sections(cache_only: cache_only, force_refresh: force_refresh)
      else
        changelog.sections_for_versions(requested_versions, cache_only: cache_only, force_refresh: force_refresh, use_github_cli: use_github_cli)
      end
    end

    def registry_release_dates(cache_only: false, force_refresh: false)
      parsed = raw_meta(cache_only: cache_only, force_refresh: force_refresh)
      Array(parsed&.dig("versions")).each_with_object({}) do |version, dates|
        number = version["num"]
        created_at = version["created_at"]
        next if number.to_s.empty? || created_at.to_s.empty?

        dates[number] = Time.parse(created_at).utc.strftime("%b %-d, %Y")
      end
    rescue JSON::ParserError, ArgumentError
      {}
    end

    def warm_cache(versions: nil)
      meta
      repo_uri
      changelog_sections(versions: versions)
    end

    def discover_github_tag_sections?
      true
    end

    def github_tag_candidates(version)
      raw = version.to_s
      [
        raw,
        (raw.start_with?("v") ? raw : "v#{raw}"),
        "#{crate_name}-#{raw}",
        "#{crate_name}-v#{raw}",
        "#{crate_name}@#{raw}"
      ].uniq
    end

    def github_tag_matches?(tag_name)
      decoded = URI.decode_www_form_component(tag_name.to_s.split("?").first.to_s)
      return true if decoded.match?(/\Av?\d/)

      decoded.match?(/\A#{Regexp.escape(crate_name)}(?:-|@)v?\d/i)
    end

    private

    def raw_meta(cache_only: false, force_refresh: false)
      json = if cache_only
        Cache.peek(cache_key)
      else
        url = "https://crates.io/api/v1/crates/#{URI.encode_www_form_component(crate_name)}"
        Cache.fetch(cache_key, force: force_refresh) do
          options = {read_timeout: 8}
          options["User-Agent"] = USER_AGENT
          URI.parse(url).open(options).read
        end
      end

      JSON.parse(json) if json
    end

    def normalize_meta(parsed)
      return nil unless parsed.is_a?(Hash)

      crate = parsed["crate"] || {}
      name = crate["name"] || crate["id"] || crate_name
      {
        "name" => name,
        "version" => crate["max_version"] || crate["newest_version"],
        "info" => crate["description"],
        "homepage_uri" => crate["homepage"],
        "source_code_uri" => crate["repository"],
        "project_uri" => "https://crates.io/crates/#{name}",
        "documentation_uri" => crate["documentation"]
      }
    end

    def normalize_repo_uri(uri)
      value = uri.to_s
      return "" if value.empty?

      value = value.sub(/\Agit\+/, "")
      value = value.sub(/\Agit:\/\//, "https://")
      value = value.sub(/\Ahttp:\/\//, "https://")
      value = value.gsub(/\.git\z/, "")
      value = value[%r{\Ahttps?://github\.com/[^/]+/[^/]+}] || value if value.include?("github.com")
      value
    end
  end
end
