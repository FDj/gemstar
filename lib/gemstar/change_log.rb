# frozen_string_literal: true

module Gemstar
  class ChangeLog
    def initialize(repo, gem_name)
      @repo = repo
      @gem_name = gem_name
    end

    attr_reader :repo, :gem_name

    def content
      @content ||= fetch_changelog_content
    end

    def sections
      @sections ||= parse_changelog_sections
    end

    def extract_relevant_sections(old_version, new_version)
      from = Gem::Version.new(old_version.gsub(/-[\w\-]+$/, '')) rescue Gem::Version.new("0.0.0")
      to = Gem::Version.new(new_version.gsub(/-[\w\-]+$/, '')) rescue Gem::Version.new("9999.9999.9999")
      sections.select do |version, _|
        v = Gem::Version.new(version.gsub(/-[\w\-]+$/, ''))
        v > from && v <= to
      rescue
        false
      end.sort_by { |v, _|
        begin
          Gem::Version.new(v.gsub(/-[\w\-]+$/, ''))
        rescue
          Gem::Version.new("0.0.0")
        end }.reverse.to_h
    end

    private

    def fetch_changelog_content
      return nil unless @repo

      if @repo =~ %r{https://github\.com/aws/aws-sdk-ruby}
        base = "https://raw.githubusercontent.com/aws/aws-sdk-ruby/refs/heads/version-3/gems/#{gem_name}"
        aws_style = true
      else
        base = @repo.sub("https://github.com", "https://raw.githubusercontent.com")
        aws_style = false
      end

      paths = aws_style ? ["CHANGELOG.md"] : %w[
        CHANGELOG.md Changelog.md changelog.md ChangeLog.md
        CHANGES.md Changes.md changes.md
        HISTORY.md History.md history.md
      ]

      remote_repository = RemoteRepository.new(base)

      branches = aws_style ? [""] : remote_repository.find_main_branch

      paths.product(branches).each do |file, branch|
        url = aws_style ? "#{base}/#{file}" : "#{base}/#{branch}/#{file}"
        # puts "Fetching changelog for #{url}"
        content = Cache.fetch("changelog-#{url}") do
          URI.open(url, read_timeout: 8)&.read
        rescue
          nil
        end
        return content if content
      end

      nil
    end

    def parse_changelog_sections
      sections = {}
      current = nil
      current_lines = []

      content&.each_line do |line|
        if line =~ /^#+\s*\[?v?(\d[\w.\-]+)\]?(?:\s*\(.*\))?/
          version = $1
          if current && !current_lines.empty?
            sections[current] = current_lines.dup
          end
          current = version
          current_lines = [line]
        elsif line =~ /^\s*v?(\d[\w.\-]+)\s*\(.*\)/
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
