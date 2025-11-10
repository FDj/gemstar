# frozen_string_literal: true

module Gemstar
  class ChangeLog
    def initialize(metadata)
      @metadata = metadata
    end

    attr_reader :metadata

    def content
      @content ||= fetch_changelog_content
    end

    def sections
      @sections ||= parse_changelog_sections
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

    def changelog_uri_candidates
      candidates = [@metadata.meta["changelog_uri"]]

      if @metadata.repo_uri =~ %r{https://github\.com/aws/aws-sdk-ruby}
        base = "https://raw.githubusercontent.com/aws/aws-sdk-ruby/refs/heads/version-3/gems/#{@metadata.gem_name}"
        aws_style = true
      else
        base = @metadata.repo_uri.sub("https://github.com", "https://raw.githubusercontent.com")
        aws_style = false
      end

      base = base.chomp("/")

      paths = aws_style ? ["CHANGELOG.md"] : %w[
        CHANGELOG.md Changelog.md changelog.md ChangeLog.md
        CHANGES.md Changes.md changes.md
        HISTORY.md History.md history.md
        releases.md History CHANGELOG.rdoc
      ]

      remote_repository = RemoteRepository.new(base)

      branches = aws_style ? [""] : remote_repository.find_main_branch

      candidates += paths.product(branches).map do |file, branch|
        uri = aws_style ? "#{base}/#{file}" : "#{base}/#{branch}/#{file}"
      end

      candidates.flatten!
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

        !content.nil?
      end

      pp content if Gemstar.debug?

      content
    end

    def parse_changelog_sections
      sections = {}
      current = nil
      current_lines = []

      content&.each_line do |line|
        # Convert rdoc to markdown:
        line = line.gsub(/^=+/) do |m|
          "#" * m.length
        end

        if line =~ /^\s*(?:#+|=+)\s*(?:Version\s+)?\[?v?(\d[\w.-]+)\]?(?:\s*[-(].*)?/i
          version = $1
          if current && !current_lines.empty?
            sections[current] = current_lines.dup
          end
          current = version
          current_lines = [line]
        elsif line =~ /^\s*(?:Version\s+)?v?(\d[\w.\-]+)(?:\s*[-(].*)?/i
          # fallback for lines like "1.4.0 (2025-06-02)"
          version = $1
          if current && !current_lines.empty?
            sections[current] = current_lines.dup
          end
          current = version
          current_lines = [line]
        elsif current
          current_lines << line
        end
      end

      if current && !current_lines.empty?
        sections[current] = current_lines
      end

      sections
    end
  end
end
