require "json"
require "open-uri"
require "time"
require "uri"

module Gemstar
  class PyPIMetadata
    def initialize(package_name)
      @package_name = package_name
    end

    attr_reader :package_name

    alias_method :gem_name, :package_name

    def cache_key
      "pypi-#{package_name}"
    end

    def meta(cache_only: false, force_refresh: false)
      return @meta if !cache_only && defined?(@meta)

      json = if cache_only
        Cache.peek(cache_key)
      else
        url = "https://pypi.org/pypi/#{URI.encode_www_form_component(package_name)}/json"
        Cache.fetch(cache_key, force: force_refresh) do
          URI.parse(url).open(read_timeout: 8).read
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

      uri = resolved_meta["source_code_uri"]
      uri ||= resolved_meta["homepage_uri"] if resolved_meta["homepage_uri"].to_s.include?("github.com")
      uri = normalize_repo_uri(uri)

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
      Array(parsed&.dig("releases")).each_with_object({}) do |(version, files), dates|
        uploaded_at = Array(files).filter_map { |file| file["upload_time_iso_8601"] || file["upload_time"] }.min
        next if version.to_s.empty? || uploaded_at.to_s.empty?

        dates[version] = Time.parse(uploaded_at).utc.strftime("%b %-d, %Y")
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
      candidates = [raw, (raw.start_with?("v") ? raw : "v#{raw}")]
      candidates << "release_#{raw}"
      candidates << "release_v#{raw}" unless raw.start_with?("v")

      if raw.match?(/\A\d+\.\d\z/)
        padded_minor = "#{raw}0"
        candidates << padded_minor
        candidates << "v#{padded_minor}"
        candidates << "release_#{padded_minor}"
        candidates << "release_v#{padded_minor}"
      end

      if raw.match?(/\A\d{4}\.\d{1,2}\.\d{1,2}\z/)
        year, month, day = raw.split(".")
        dotted_date = [year, month.rjust(2, "0"), day.rjust(2, "0")].join(".")
        candidates << dotted_date
        candidates << "v#{dotted_date}"
        candidates << "release_#{dotted_date}"
        candidates << "release_v#{dotted_date}"
      end

      candidates.uniq
    end

    def github_tag_matches?(_tag_name)
      true
    end

    private

    def raw_meta(cache_only: false, force_refresh: false)
      json = if cache_only
        Cache.peek(cache_key)
      else
        url = "https://pypi.org/pypi/#{URI.encode_www_form_component(package_name)}/json"
        Cache.fetch(cache_key, force: force_refresh) do
          URI.parse(url).open(read_timeout: 8).read
        end
      end

      JSON.parse(json) if json
    end

    def normalize_meta(parsed)
      return nil unless parsed.is_a?(Hash)

      info = parsed["info"] || {}
      project_urls = info["project_urls"] || {}
      source_code_uri = project_url(project_urls, "Source", "Source Code", "Code", "Repository", "GitHub")
      homepage_uri = info["home_page"].to_s.empty? ? nil : info["home_page"]
      homepage_uri ||= project_url(project_urls, "Homepage", "Home", "homepage")
      changelog_uri = project_url(project_urls, "Changelog", "Change Log", "Changes", "Release Notes", "Release notes", "History")

      {
        "name" => info["name"] || package_name,
        "version" => info["version"],
        "info" => info["summary"] || info["description"],
        "homepage_uri" => homepage_uri,
        "source_code_uri" => source_code_uri,
        "project_uri" => info["package_url"] || "https://pypi.org/project/#{package_name}/",
        "documentation_uri" => project_url(project_urls, "Documentation", "Docs", "documentation"),
        "changelog_uri" => changelog_uri
      }
    end

    def project_url(project_urls, *names)
      normalized_urls = project_urls.transform_keys { |key| key.to_s.downcase.gsub(/[\s_-]+/, "") }
      names.each do |name|
        value = normalized_urls[name.to_s.downcase.gsub(/[\s_-]+/, "")]
        return value unless value.to_s.empty?
      end

      nil
    end

    def normalize_repo_uri(uri)
      value = uri.to_s
      return "" if value.empty?

      value = value.sub(/\Agit\+/, "")
      value = value.sub(/\Agit:\/\//, "https://")
      value = value.sub(/\Ahttp:\/\//, "https://")
      value = value.gsub(/\.git\z/, "")

      if value.include?("github.com")
        value = value[%r{\Ahttps?://github\.com/[^/]+/[^/]+}] || value
      end

      value
    end
  end
end
