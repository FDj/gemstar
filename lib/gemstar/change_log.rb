# frozen_string_literal: true

module Gemstar
  class ChangeLog
    @@candidates_found = Hash.new(0)

    def initialize(metadata)
      @metadata = metadata
    end

    attr_reader :metadata

    def content
      @content ||= fetch_changelog_content
    end

    def sections
      @sections ||= begin
        s = parse_changelog_sections
        if s.nil? || s.empty?
          s = parse_github_release_sections
        end

        pp @@candidates_found if Gemstar.debug?

        s
      end
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

    # Extract a version token from a heading line, preferring explicit version forms
    # and avoiding returning a date string when both are present.
    def extract_version_from_heading(line)
      return nil unless line
      heading = line.to_s
      # 1) Prefer version inside parentheses after a date: "### 2025-11-07 (2.16.0)"
      return $1 if heading[/\(\s*v?(\d[\w.\-]+)\s*\)/]
      # 2) Version-first with optional leading markers/labels: "## v1.2.6 - 2025-10-21"
      return $1 if heading[/^\s*(?:#+|=+)?\s*(?:Version\s+)?\[?v?(\d[\w.\-]+)\]?/i]
      # 3) Anywhere: first semver-like token with a dot
      return $1 if heading[/\bv?(\d+\.\d+(?:\.\d+)?(?:[A-Za-z0-9.\-]+)?)\b/]
      nil
    end

    def changelog_uri_candidates
      candidates = []

      if @metadata.repo_uri =~ %r{https://github\.com/aws/aws-sdk-ruby}
        base = "https://raw.githubusercontent.com/aws/aws-sdk-ruby/refs/heads/version-3/gems/#{@metadata.gem_name}"
        aws_style = true
      else
        base = @metadata.repo_uri.sub("https://github.com", "https://raw.githubusercontent.com")
        aws_style = false
      end

      base = base.chomp("/")

      paths = aws_style ? ["CHANGELOG.md"] : %w[
        CHANGELOG.md releases.md CHANGES.md
        Changelog.md changelog.md ChangeLog.md
        Changes.md changes.md
        HISTORY.md History.md history.md
        History CHANGELOG.rdoc
      ]

      remote_repository = RemoteRepository.new(base)

      branches = aws_style ? [""] : remote_repository.find_main_branch

      candidates += paths.product(branches).map do |file, branch|
        uri = aws_style ? "#{base}/#{file}" : "#{base}/#{branch}/#{file}"
      end

      # Add the gem's changelog_uri last as it's usually not the most parsable:
      candidates += [Gemstar::GitHub::github_blob_to_raw(@metadata.meta["changelog_uri"])]

      candidates.flatten!
      candidates.uniq!
      candidates.compact!

      candidates
    end

    def fetch_changelog_content
      content = nil

      changelog_uri_candidates.find do |candidate|
        content = Cache.fetch("changelog-#{candidate}") do
          URI.open(candidate, read_timeout: 8)&.read
        rescue => e
          puts "#{candidate}: #{e}" if Gemstar.debug?
          nil
        end

        # puts "fetch_changelog_content #{candidate}:\n#{content}" if Gemstar.debug?

        if content
          @@candidates_found[candidate.split("/").last] += 1
        end

        !content.nil?
      end

      content
    end


    def parse_changelog_sections
      # If the fetched content looks like a GitHub Releases HTML page, return {}
      # so that the GitHub releases scraper can handle it. This avoids
      # accidentally parsing HTML from /releases pages as a markdown changelog.
      c = content
      return {} if c.nil? || c.strip.empty?
      if (c.include?("<html") || c.include?("<!DOCTYPE html")) &&
         (c.include?('data-test-selector="body-content"') || c.include?("/releases/tag/"))
        puts "parse_changelog_sections #{@metadata.gem_name}: Detected GitHub Releases HTML; skipping to fallback" if Gemstar.debug?
        return {}
      end

      sections = {}
      current_key = nil
      current_lines = []

      flush_current = lambda do
        return unless current_key && !current_lines.empty?
        key = current_key
        # If key looks like a date or non-version, try to extract a proper version
        if key =~ /\A\d{4}-\d{2}-\d{2}\z/ || key !~ /\A\d[\w.\-]*\z/
          v = extract_version_from_heading(current_lines.first)
          key = v if v
        end
        if sections.key?(key)
          # Collision: merge by appending with a separator to avoid losing data
          sections[key] += ["\n"] + current_lines
        else
          sections[key] = current_lines.dup
        end
      end

      c.each_line do |line|
        # Convert rdoc to markdown:
        line = line.gsub(/^=+/) { |m| "#" * m.length }

        new_key = nil
        # Keep-a-Changelog style: version first with trailing date, e.g. "## v1.2.6 - 2025-10-21"
        if line =~ /^\s*(?:#+|=+)\s*\[?v?(\d[\w.\-]+)\]?\s*(?:—|–|-)\s*\d{4}-\d{2}-\d{2}\b/
          new_key = extract_version_from_heading(line) || $1
        elsif line =~ /^\s*(?:#+|=+)\s*(?:Version\s+)?(?:(?:[^\s\d][^\s]*\s+)+)\[?v?(\d[\w.\-]+)\]?(?:\s*[-(].*)?/i
          new_key = extract_version_from_heading(line) || $1
        elsif line =~ /^\s*(?:#+|=+)\s*(?:Version\s+)?\[?v?(\d[\w.\-]+)\]?(?:\s*[-(].*)?/i
          # header without label words before the version
          new_key = extract_version_from_heading(line) || $1
        elsif line =~ /^\s*(?:#+|=+)\s*\d{4}-\d{2}-\d{2}\s*\(\s*v?(\d[\w.\-]+)\s*\)/
          # headings like "### 2025-11-07 (2.16.0)" — prefer the version in parentheses over the leading date
          new_key = extract_version_from_heading(line) || $1
        elsif line =~ /^\s*(?:Version\s+)?v?(\d[\w.\-]+)(?:\s*[-(].*)?/i
          # fallback for lines like "1.4.0 (2025-06-02)"
          new_key = extract_version_from_heading(line) || $1
        end

        if new_key
          # Flush previous section before starting a new one
          flush_current.call
          current_key = new_key
          current_lines = [line]
        elsif current_key
          current_lines << line
        end
      end

      # Flush the last captured section
      flush_current.call

      # Normalize keys: ensure all keys are versions; fix any leftover date-like keys conservatively
      begin
        normalized = {}
        sections.each do |k, lines|
          if k =~ /\A\d{4}-\d{2}-\d{2}\z/ || k !~ /\A\d[\w.\-]*\z/
            heading = lines.first.to_s
            # 1) Prefer version inside parentheses, e.g., "### 2025-11-07 (2.16.0)"
            if heading[/\(\s*v?(\d[\w.\-]+)\s*\)/]
              key = $1
              normalized[key] = if normalized.key?(key)
                                   normalized[key] + ["\n"] + lines
                                 else
                                   lines
                                 end
              next
            end
            # 2) Headings like "## v1.2.5 - 2025-10-21" or "## 1.2.5 — 2025-10-21"
            if heading[/^\s*(?:#+|=+)\s*(?:Version\s+)?\[?v?(\d+\.\d+(?:\.\d+)?(?:[A-Za-z0-9.\-]+)?)\]?/]
              key = $1
              normalized[key] = if normalized.key?(key)
                                   normalized[key] + ["\n"] + lines
                                 else
                                   lines
                                 end
              next
            end
            # 3) Anywhere in the heading, pick the first semver-like token with a dot
            if heading[/\bv?(\d+\.\d+(?:\.\d+)?(?:[A-Za-z0-9.\-]+)?)\b/]
              key = $1
              normalized[key] = if normalized.key?(key)
                                   normalized[key] + ["\n"] + lines
                                 else
                                   lines
                                 end
              next
            end
          end
          # Default: carry over, merging on collision to avoid loss
          if normalized.key?(k)
            normalized[k] += ["\n"] + lines
          else
            normalized[k] = lines
          end
        end
        sections = normalized unless normalized.empty?
      rescue => e
        # Be conservative; if normalization fails for any reason, keep original sections
        puts "Normalization error in parse_changelog_sections: #{e}" if Gemstar.debug?
      end

      if Gemstar.debug?
        puts "parse_changelog_sections #{@metadata.gem_name}:"
        pp sections
      end

      sections
    end

    def parse_github_release_sections
      begin
        require "nokogiri"
      rescue LoadError
        return {}
      end

      return {} unless @metadata&.repo_uri&.include?("github.com")

      url = github_releases_url
      return {} unless url

      html = Cache.fetch("releases-#{url}") do
        begin
          URI.open(url, read_timeout: 8)&.read
        rescue => e
          puts "#{url}: #{e}" if Gemstar.debug?
          nil
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
          next unless text && text[/v?(\d[\w.\-]+)/i]
          version = $1

          html_chunk = body.inner_html.to_s.strip
          next if html_chunk.empty?
          lines = ["## #{version}\n", html_chunk]
          sections[version] = lines
        end
      end

      if Gemstar.debug?
        puts "parse_github_release_sections #{@metadata.gem_name}:"
        pp sections.keys
      end

      sections
    end

    def github_releases_url
      return nil unless @metadata&.repo_uri
      repo = @metadata.repo_uri.chomp("/")
      return nil if repo.empty?
      "#{repo}/releases"
    end
  end
end
