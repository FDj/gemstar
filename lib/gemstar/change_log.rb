# frozen_string_literal: true
require "cgi"
require "date"
require "json"
require "time"

module Gemstar
  class ChangeLog
    @@candidates_found = Hash.new(0)
    DEFAULT_CHANGELOG_PATHS = %w[
      CHANGELOG.md releases.md CHANGES.md
      Changelog.md changelog.md ChangeLog.md
      Changes.md changes.md
      HISTORY.md History.md history.md
      History CHANGELOG.rdoc
    ].freeze

    def initialize(metadata)
      @metadata = metadata
    end

    attr_reader :metadata

    def content(cache_only: false, force_refresh: false)
      return @content if !cache_only && defined?(@content)

      result = fetch_changelog_content(cache_only: cache_only, force_refresh: force_refresh)
      @content = result unless cache_only
      result
    end

    def sections(cache_only: false, force_refresh: false)
      return @sections if !cache_only && defined?(@sections) && !force_refresh

      metadata_key = @metadata.respond_to?(:cache_key) ? @metadata.cache_key : @metadata.gem_name
      cache_key = "sections-v5-#{metadata_key}"
      serialized = if cache_only
        Cache.peek(cache_key)
      else
        Cache.fetch(cache_key, force: force_refresh) do
          JSON.generate(compute_sections(force_refresh: force_refresh))
        end
      end

      result = if serialized
        decode_sections(serialized)
      elsif cache_only
        nil
      else
        compute_sections(force_refresh: force_refresh)
      end

      @sections = result unless cache_only
      result
    end

    def sections_for_versions(versions, cache_only: false, force_refresh: false)
      requested_versions = normalize_requested_versions(versions)
      return {} if requested_versions.empty?

      cached_sections = sections(cache_only: true) || {}
      result = cached_sections.select { |version, _| requested_versions.include?(normalize_version_key(version)) }
      return result if cache_only

      changelog_sections = parse_changelog_sections(cache_only: false, force_refresh: force_refresh) || {}
      changelog_sections.each do |version, lines|
        result[version] ||= lines if requested_versions.include?(normalize_version_key(version))
      end

      repo_uri = @metadata&.repo_uri(cache_only: false, force_refresh: force_refresh)
      if repo_uri&.include?("github.com")
        missing_versions = requested_versions - result.keys.map { |version| normalize_version_key(version) }
        missing_versions.each do |version|
          specific_release = parse_specific_github_release_pages(
            repo_uri,
            version,
            cache_only: false,
            force_refresh: force_refresh
          )
          result.merge!(specific_release) if specific_release
        end
      end

      result
    end

    def release_dates(versions: nil, cache_only: false, force_refresh: false)
      requested_versions = normalize_requested_versions(versions)
      metadata_key = @metadata.respond_to?(:cache_key) ? @metadata.cache_key : @metadata.gem_name
      cache_key = "release-dates-v2-#{metadata_key}"
      serialized = if cache_only
        Cache.peek(cache_key)
      else
        Cache.fetch(cache_key, force: force_refresh) do
          JSON.generate(compute_release_dates(force_refresh: force_refresh))
        end
      end

      dates = if serialized
        decode_sections(serialized) || {}
      elsif cache_only
        {}
      else
        compute_release_dates(force_refresh: force_refresh)
      end

      return dates if requested_versions.empty?

      dates.select { |version, _date| requested_versions.include?(normalize_version_key(version)) }
    end

    def compute_sections(force_refresh: false)
      changelog_sections = parse_changelog_sections(cache_only: false, force_refresh: force_refresh) || {}
      github_sections = parse_github_release_sections(cache_only: false, force_refresh: force_refresh) || {}

      sections = merge_section_sources(changelog_sections, github_sections)

      pp @@candidates_found if Gemstar.debug?

      sections
    end

    def compute_release_dates(force_refresh: false)
      registry_dates = if @metadata.respond_to?(:registry_release_dates)
        @metadata.registry_release_dates(cache_only: false, force_refresh: force_refresh)
      else
        {}
      end
      return registry_dates unless registry_dates.nil? || registry_dates.empty?

      changelog_dates = parse_changelog_release_dates(cache_only: false, force_refresh: force_refresh)
      return changelog_dates unless changelog_dates.nil? || changelog_dates.empty?

      repo_uri = @metadata&.repo_uri(cache_only: false, force_refresh: force_refresh)
      return {} unless repo_uri&.include?("github.com")

      parse_github_tag_dates(repo_uri, cache_only: false, force_refresh: force_refresh)
    end

    def decode_sections(serialized)
      JSON.parse(serialized)
    rescue JSON::ParserError
      nil
    end

    def merge_section_sources(changelog_sections, github_sections)
      return github_sections if changelog_sections.nil? || changelog_sections.empty?
      changelog_sections
    end

    def extract_relevant_sections(old_version, new_version)
      from = Gem::Version.new(old_version.gsub(/-[\w\-]+$/, "")) rescue nil if old_version
      from ||= Gem::Version.new("0.0.0")
      to = Gem::Version.new(new_version.gsub(/-[\w\-]+$/, "")) rescue nil if new_version
      to ||= Gem::Version.new("9999.9999.9999")

      sections.select do |version, _|
        v = Gem::Version.new(version.gsub(/-[\w\-]+$/, ""))
        v > from && v <= to
      rescue => e
        false
      end.sort_by do |k, _|
        Gem::Version.new(k.gsub(/-[\w\-]+$/, ""))
      rescue => e
        Gem::Version.new("0.0.0")
      end.reverse.to_h
    end

    private

    def normalize_requested_versions(versions)
      Array(versions).filter_map { |version| normalize_version_key(version) }.uniq
    end

    def normalize_version_key(version)
      value = version.to_s.strip
      return nil if value.empty?

      value.sub(/\Av/i, "")
    end

    # Extract a version token from a heading line, preferring explicit version forms
    # and avoiding returning a date string when both are present.
    def extract_version_from_heading(line)
      return nil unless line
      heading = line.to_s
      version_token = /(\d+\.\d+(?:\.\d+)?(?:[-.][A-Za-z0-9]+)*)/
      # 1) Prefer version inside parentheses after a date: "### 2025-11-07 (2.16.0)"
      #    Ensure we ONLY treat it as a version if it actually looks like a version (has a dot),
      #    so we don't capture dates like (2025-11-21).
      return $1 if heading[/\(\s*v?#{version_token}(?![A-Za-z0-9])\s*\)/]
      # 2) Version-first with optional leading markers/labels: "## v1.2.6 - 2025-10-21"
      #    Require a dot in the numeric token to avoid capturing dates like 2025-11-21.
      return $1 if heading[/^\s*(?:[-*]\s+)?(?:#+|=+)?\s*(?:Version\s+)?\[*v?#{version_token}(?![A-Za-z0-9])\]*/i]
      # 3) Anywhere: first semver-like token with a dot
      return $1 if heading[/\bv?#{version_token}(?![A-Za-z0-9])\b/]
      nil
    end

    def extract_release_date_from_heading(line)
      return nil unless line

      raw_date = line.to_s[/\b(\d{4}-\d{2}-\d{2})\b/, 1]
      format_release_date(raw_date)
    end

    def changelog_uri_candidates(cache_only: false, force_refresh: false)
      candidates = []

      repo_uri = @metadata.repo_uri(cache_only: cache_only, force_refresh: force_refresh)
      return [] if repo_uri.nil? || repo_uri.empty?

      meta = @metadata.meta(cache_only: cache_only, force_refresh: force_refresh)
      candidates += changelog_uri_markdown_candidates(meta["changelog_uri"]) if meta

      changelog_source = metadata_changelog_source(repo_uri, cache_only: cache_only, force_refresh: force_refresh)
      return [] unless changelog_source

      candidates += changelog_source[:paths].product(changelog_source[:branches]).map do |file, branch|
        [changelog_source[:base], branch, file].reject { |segment| segment.to_s.empty? }.join("/")
      end

      # Add the gem's changelog_uri last as it's usually not the most parsable:
      candidates += [Gemstar::GitHub::github_blob_to_raw(meta["changelog_uri"])] if meta

      candidates.flatten!
      candidates.uniq!
      candidates.compact!

      candidates
    end

    def changelog_uri_markdown_candidates(changelog_uri)
      raw_uri = Gemstar::GitHub::github_blob_to_raw(changelog_uri)
      return [] if raw_uri.to_s.empty?

      candidates = []
      candidates << raw_uri if raw_uri.match?(/\.(?:md|markdown|rdoc|txt)\z/i)

      begin
        uri = URI(raw_uri)
        path = uri.path.to_s
        if path.end_with?("/")
          uri.path = "#{path.chomp("/")}.md"
          candidates << uri.to_s
        elsif File.extname(path).empty?
          uri.path = "#{path}.md"
          candidates << uri.to_s
        end
      rescue URI::InvalidURIError
        nil
      end

      candidates
    end

    def metadata_changelog_source(repo_uri, cache_only:, force_refresh:)
      if @metadata.respond_to?(:changelog_source)
        return @metadata.changelog_source(repo_uri: repo_uri, cache_only: cache_only, force_refresh: force_refresh)
      end

      base = repo_uri.sub("https://github.com", "https://raw.githubusercontent.com").chomp("/")
      {
        base: base,
        paths: DEFAULT_CHANGELOG_PATHS,
        branches: RemoteRepository.new(base).find_main_branch(cache_only: cache_only, force_refresh: force_refresh)
      }
    end

    def fetch_changelog_content(cache_only: false, force_refresh: false)
      content = nil

      changelog_uri_candidates(cache_only: cache_only, force_refresh: force_refresh).find do |candidate|
        content = if cache_only
          Cache.peek("changelog-#{candidate}")
        else
          Cache.fetch("changelog-#{candidate}", force: force_refresh) do
            URI.open(candidate, read_timeout: 8)&.read
          rescue => e
            puts "#{candidate}: #{e}" if Gemstar.debug?
            nil
          end
        end

        # puts "fetch_changelog_content #{candidate}:\n#{content}" if Gemstar.debug?

        if content
          @@candidates_found[candidate.split("/").last] += 1
        end

        !content.nil?
      end

      content
    end

    VERSION_PATTERNS = [
      /^\s*(?:[-*]\s+)?(?:#+|=+)\s*\d{4}-\d{2}-\d{2}\s*\(\s*v?(\d+\.\d+(?:\.\d+)?(?:[-.][A-Za-z0-9]+)*)(?![A-Za-z0-9])\s*\)/, # prefer this
      /^\s*(?:[-*]\s+)?(?:#+|=+)\s*\[*v?(\d+\.\d+(?:\.\d+)?(?:[-.][A-Za-z0-9]+)*)(?![A-Za-z0-9])\]*\s*(?:—|–|-)\s*\d{4}-\d{2}-\d{2}\b/,
      /^\s*(?:[-*]\s+)?(?:#+|=+)\s*(?:Version\s+)?(?:(?:[^\s\d][^\s]*\s+)+)\[*v?(\d+\.\d+(?:\.\d+)?(?:[-.][A-Za-z0-9]+)*)(?![A-Za-z0-9])\]*(?:\s*[-(].*)?/i,
      /^\s*(?:[-*]\s+)?(?:#+|=+)\s*(?:Version\s+)?\[*v?(\d+\.\d+(?:\.\d+)?(?:[-.][A-Za-z0-9]+)*)(?![A-Za-z0-9])\]*(?:\s*[-(].*)?/i,
      /^\s*(?:[-*]\s+)?(?:Version\s+)?v?(\d+\.\d+(?:\.\d+)?(?:[-.][A-Za-z0-9]+)*)(?![A-Za-z0-9])(?:\s*[-(].*)?/i
    ]

    def parse_changelog_sections(cache_only: false, force_refresh: false)
      # If the fetched content looks like a GitHub Releases HTML page, return {}
      # so that the GitHub releases scraper can handle it. This avoids
      # accidentally parsing HTML from /releases pages as a markdown changelog.
      c = content(cache_only: cache_only, force_refresh: force_refresh)
      return {} if c.nil? || c.strip.empty?
      if (c.include?("<html") || c.include?("<!DOCTYPE html")) &&
         (c.include?('data-test-selector="body-content"') || c.include?("/releases/tag/"))
        puts "parse_changelog_sections #{@metadata.gem_name}: Detected GitHub Releases HTML; skipping to fallback" if Gemstar.debug?
        return {}
      end

      lines = c.lines

      if lines.count < 4
        # Skip changelog files that are too short to be useful
        # This is sometimes the case with changelogs just saying "please see GitHub releases"
        puts "parse_changelog_sections #{@metadata.gem_name}: Changelog too short; skipping" if Gemstar.debug?
        return {}
      end

      sections = {}
      current_key = nil
      current_lines = []

      lines.each do |line|
        # Convert rdoc to markdown:
        line = line.gsub(/^=+/) { |m| "#" * m.length }

        m = VERSION_PATTERNS.lazy.map { |re| line.match(re) }.find(&:itself)

        if m
          new_key = extract_version_from_heading(line) || $1

          if current_key
            sections[current_key] ||= []
            sections[current_key] << current_lines
            current_lines = []
          end

          current_key = new_key
        end

        current_lines << line if current_key
      end

      if current_key
        # Flush last section
        sections[current_key] ||= []
        sections[current_key] << current_lines
      end

      if Gemstar.debug?
        puts "parse_changelog_sections #{@metadata.gem_name}:"
        pp sections
      end

      sections
    end

    def parse_changelog_release_dates(cache_only: false, force_refresh: false)
      c = content(cache_only: cache_only, force_refresh: force_refresh)
      return {} if c.nil? || c.strip.empty?
      return {} if c.include?("<html") || c.include?("<!DOCTYPE html")

      c.lines.each_with_object({}) do |line, dates|
        line = line.gsub(/^=+/) { |m| "#" * m.length }
        next unless VERSION_PATTERNS.any? { |re| line.match?(re) }

        version = extract_version_from_heading(line)
        date = extract_release_date_from_heading(line)
        dates[version] ||= date if version && date
      end
    end

    def parse_github_release_sections(cache_only: false, force_refresh: false)
      begin
        require "nokogiri"
      rescue LoadError
        return {}
      end

      repo_uri = @metadata&.repo_uri(cache_only: cache_only, force_refresh: force_refresh)
      return {} unless repo_uri&.include?("github.com")

      url = github_releases_url(repo_uri)
      return {} unless url

      html = if cache_only
        Cache.peek("releases-#{url}")
      else
          Cache.fetch("releases-#{url}", force: force_refresh) do
            begin
              URI.open(url, read_timeout: 8)&.read
          rescue => e
            puts "#{url}: #{e}" if Gemstar.debug?
            nil
          end
        end
      end

      if (html.nil? || html.strip.empty?) && cache_only
        cached_content = content(cache_only: true)
        if cached_content&.include?("<html") &&
           (cached_content.include?('data-test-selector="body-content"') || cached_content.include?("/releases/tag/"))
          html = cached_content
        end
      end

      return {} if html.nil? || html.strip.empty?

      doc = begin
              Nokogiri::HTML5(html)
            rescue => _
              Nokogiri::HTML(html)
            end

      sections = {}

      # Preferred: iterate release sections that have an accessible h2 with the version (sr-only)
      doc.css('section[aria-labelledby]').each do |sec|
        heading = sec.at_css('h2.sr-only')
        next unless heading
        text = heading.text.to_s.strip
        next unless github_tag_matches_metadata?(text)
        next unless text[/v?(\d[\w.\-]+)/i]
        version = $1

        body = sec.at_css('[data-test-selector="body-content"] .markdown-body') ||
               sec.at_css('[data-test-selector="body-content"]') ||
               sec.at_css('.markdown-body')
        next unless body

        html_chunk = body.inner_html.to_s.strip
        next if html_chunk.empty?

        lines = ["## #{version}\n", html_chunk]
        sections[version] = lines
      end

      # Fallback: look for any body-content blocks across the page and try to infer nearby tag links
      if sections.empty?
        doc.css('[data-test-selector="body-content"]').each do |container|
          body = container.at_css('.markdown-body') || container
          # find a tag link near this container
          link = container.at_xpath('ancestor::*[self::section or self::div][.//a[contains(@href, "/releases/tag/")]][1]//a[contains(@href, "/releases/tag/")]')
          text = link&.text.to_s
          text = File.basename(URI(link["href"]).path) if (text.nil? || text.empty?) && link
          next unless github_tag_matches_metadata?(text)
          next unless text && text[/v?(\d[\w.\-]+)/i]
          version = $1

          html_chunk = body.inner_html.to_s.strip
          next if html_chunk.empty?
          lines = ["## #{version}\n", html_chunk]
          sections[version] = lines
        end
      end

      if sections.empty?
        current_version = @metadata&.meta(cache_only: cache_only, force_refresh: force_refresh)&.dig("version")
        current_release_sections = parse_specific_github_release_pages(
          repo_uri,
          current_version,
          cache_only: cache_only,
          force_refresh: force_refresh
        )
        tag_sections = parse_github_tag_sections(
          repo_uri,
          cache_only: cache_only,
          force_refresh: force_refresh
        )
        sections = tag_sections.merge(current_release_sections)
      elsif discover_github_tag_sections?
        tag_sections = parse_github_tag_sections(
          repo_uri,
          cache_only: cache_only,
          force_refresh: force_refresh
        )
        sections = tag_sections.merge(sections)
      end

      if Gemstar.debug?
        puts "parse_github_release_sections #{@metadata.gem_name}:"
        pp sections.keys
      end

      sections
    end

    def github_releases_url(repo_uri = @metadata&.repo_uri)
      return nil unless repo_uri
      repo = repo_uri.chomp("/")
      return nil if repo.empty?
      "#{repo}/releases"
    end

    def github_tags_url(repo_uri = @metadata&.repo_uri)
      return nil unless repo_uri
      repo = repo_uri.chomp("/")
      return nil if repo.empty?
      "#{repo}/tags"
    end

    def parse_specific_github_release_pages(repo_uri, version, cache_only:, force_refresh:)
      return {} unless repo_uri&.include?("github.com")
      return {} if version.to_s.empty?

      github_release_tag_urls(repo_uri, version).each do |url|
        html = if cache_only
          Cache.peek("releases-#{url}")
        else
          Cache.fetch("releases-#{url}", force: force_refresh) do
            begin
              URI.open(url, read_timeout: 8)&.read
            rescue => e
              puts "#{url}: #{e}" if Gemstar.debug?
              nil
            end
          end
        end

        next if html.nil? || html.strip.empty?

        section = parse_single_github_release_page(html, version)
        return { version => section } if section
      end

      {}
    end

    def parse_github_tag_sections(repo_uri, cache_only:, force_refresh:)
      return {} unless repo_uri&.include?("github.com")

      url = github_tags_url(repo_uri)
      return {} unless url

      sections = {}
      seen_urls = {}

      while url && !seen_urls[url]
        seen_urls[url] = true
        html = if cache_only
          Cache.peek("tags-#{url}")
        else
          Cache.fetch("tags-#{url}", force: force_refresh) do
            begin
              URI.open(url, read_timeout: 8)&.read
            rescue => e
              puts "#{url}: #{e}" if Gemstar.debug?
              nil
            end
          end
        end

        break if html.nil? || html.strip.empty?

        page_sections, next_url = parse_single_github_tags_page(html, repo_uri)
        sections.merge!(page_sections) { |_version, existing, _new| existing }
        url = next_url
      end

      sections.keys.each do |version|
        specific_release = parse_specific_github_release_pages(
          repo_uri,
          version,
          cache_only: cache_only,
          force_refresh: force_refresh
        )
        next if specific_release.nil? || specific_release.empty?

        sections[version] = specific_release[version] if specific_release[version]
      end

      sections
    end

    def parse_github_tag_dates(repo_uri, cache_only:, force_refresh:)
      return {} unless repo_uri&.include?("github.com")

      url = github_tags_url(repo_uri)
      return {} unless url

      dates = {}
      seen_urls = {}

      while url && !seen_urls[url]
        seen_urls[url] = true
        html = if cache_only
          Cache.peek("tags-#{url}")
        else
          Cache.fetch("tags-#{url}", force: force_refresh) do
            begin
              URI.open(url, read_timeout: 8)&.read
            rescue => e
              puts "#{url}: #{e}" if Gemstar.debug?
              nil
            end
          end
        end

        break if html.nil? || html.strip.empty?

        page_dates, next_url = parse_single_github_tag_dates_page(html, repo_uri)
        dates.merge!(page_dates) { |_version, existing, _new| existing }
        url = next_url
      end

      dates
    end

    def parse_single_github_tags_page(html, repo_uri)
      require "nokogiri"

      doc = begin
              Nokogiri::HTML5(html)
            rescue => _
              Nokogiri::HTML(html)
            end

      sections = {}
      repo_path = URI(repo_uri).path
      release_prefix = "#{repo_path}/releases/tag/"
      tree_prefix = "#{repo_path}/tree/"

      doc.css("a[href]").each do |link|
        href = link["href"].to_s
        tag_name =
          if href.start_with?(release_prefix)
            href.delete_prefix(release_prefix)
          elsif href.start_with?(tree_prefix)
            href.delete_prefix(tree_prefix)
          end
        next if tag_name.to_s.empty?
        next unless github_tag_matches_metadata?(tag_name)

        version = normalize_github_tag_version(tag_name)
        next if version.to_s.empty?

        sections[version] ||= [
          "## #{version}\n",
          "<p>No release information available. Check the release page for more information.</p>"
        ]
      end

      next_href =
        doc.at_css('a[rel="next"], a.next_page')&.[]("href") ||
        doc.css("a[href]").find do |link|
          href = link["href"].to_s
          text = link.text.to_s.gsub(/\s+/, " ").strip
          href.include?("/tags?after=") && text == "Next"
        end&.[]("href")
      next_url = if next_href && !next_href.empty?
        URI.join(repo_uri, next_href).to_s
      end

      [sections, next_url]
    rescue LoadError
      [{}, nil]
    end

    def parse_single_github_tag_dates_page(html, repo_uri)
      require "nokogiri"

      doc = begin
              Nokogiri::HTML5(html)
            rescue => _
              Nokogiri::HTML(html)
            end

      dates = {}
      repo_path = URI(repo_uri).path
      release_prefix = "#{repo_path}/releases/tag/"
      tree_prefix = "#{repo_path}/tree/"

      doc.css("a[href]").each do |link|
        href = link["href"].to_s
        tag_name =
          if href.start_with?(release_prefix)
            href.delete_prefix(release_prefix)
          elsif href.start_with?(tree_prefix)
            href.delete_prefix(tree_prefix)
          end
        next if tag_name.to_s.empty?
        next unless github_tag_matches_metadata?(tag_name)

        version = normalize_github_tag_version(tag_name)
        next if version.to_s.empty?

        datetime = github_tag_datetime_for(link)
        next if datetime.to_s.empty?

        dates[version] ||= format_release_date(datetime)
      end

      next_href =
        doc.at_css('a[rel="next"], a.next_page')&.[]("href") ||
        doc.css("a[href]").find do |link|
          href = link["href"].to_s
          text = link.text.to_s.gsub(/\s+/, " ").strip
          href.include?("/tags?after=") && text == "Next"
        end&.[]("href")
      next_url = if next_href && !next_href.empty?
        URI.join(repo_uri, next_href).to_s
      end

      [dates.compact, next_url]
    rescue LoadError
      [{}, nil]
    end

    def github_tag_datetime_for(link)
      container = link.at_xpath('ancestor::*[self::li or self::div][.//relative-time or .//time-ago][1]')
      time_node = container&.at_css("relative-time[datetime], time-ago[datetime]") ||
                  link.xpath('following::relative-time[@datetime] | following::time-ago[@datetime]').first
      time_node&.[]("datetime")
    end

    def format_release_date(datetime)
      if datetime.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        date = Date.strptime(datetime.to_s, "%Y-%m-%d")
        return date.strftime("%b #{date.day}, %Y")
      end

      time = Time.parse(datetime.to_s).utc
      time.strftime("%b #{time.day}, %Y")
    rescue ArgumentError
      nil
    end

    def parse_single_github_release_page(html, version)
      require "nokogiri"

      doc = begin
              Nokogiri::HTML5(html)
            rescue => _
              Nokogiri::HTML(html)
            end

      body = doc.at_css('[data-test-selector="body-content"] .markdown-body') ||
             doc.at_css('[data-test-selector="body-content"]') ||
             doc.at_css('.markdown-body')
      if body
        html_chunk = body.inner_html.to_s.strip
        return ["## #{version}\n", html_chunk] unless html_chunk.empty?
      end

      title = doc.at_css("title")&.text.to_s.strip
      synthetic_title = normalize_github_release_title(title, version)
      return nil if synthetic_title.nil? || synthetic_title.empty?

      ["## #{version}\n", "<p>#{CGI.escapeHTML(synthetic_title)}</p>"]
    rescue LoadError
      nil
    end

    def github_release_tag_urls(repo_url, version)
      github_tag_candidates(version).map do |tag|
        encoded_tag = URI.encode_www_form_component(tag)
        "#{repo_url}/releases/tag/#{encoded_tag}"
      end.uniq
    end

    def github_tag_candidates(version)
      return @metadata.github_tag_candidates(version) if @metadata.respond_to?(:github_tag_candidates)

      raw = version.to_s
      [raw, (raw.start_with?("v") ? raw : "v#{raw}")].uniq
    end

    def normalize_github_tag_version(tag_name)
      decoded = URI.decode_www_form_component(tag_name.to_s.split("?").first.to_s)
      match = decoded.match(/\A(?:.+@)?v?(\d[\w.\-]*)\z/i)
      match && match[1]
    end

    def github_tag_matches_metadata?(tag_name)
      return @metadata.github_tag_matches?(tag_name) if @metadata.respond_to?(:github_tag_matches?)

      true
    end

    def discover_github_tag_sections?
      @metadata.respond_to?(:discover_github_tag_sections?) && @metadata.discover_github_tag_sections?
    end

    def prefer_github_releases_first?(cache_only:, force_refresh:)
      meta = @metadata.meta(cache_only: cache_only, force_refresh: force_refresh)
      repo_uri = @metadata.repo_uri(cache_only: cache_only, force_refresh: force_refresh)

      repo_uri.to_s.include?("github.com") && meta["changelog_uri"].to_s.empty?
    rescue StandardError
      false
    end

    def normalize_github_release_title(title, version)
      return nil if title.to_s.empty?

      cleaned = title.sub(/\s*·\s*[^·]+\s*·\s*GitHub\z/, "")
      cleaned = cleaned.sub(/\ARelease\s+/, "")
      cleaned = cleaned.strip
      return nil if cleaned.empty? || cleaned == version.to_s

      cleaned
    end
  end
end
