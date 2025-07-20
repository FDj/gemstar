# frozen_string_literal: true

module Gemstar
  class ChangeLog

    def parse_changelog_sections(content)
      sections = {}
      current = nil
      current_lines = []

      content.each_line do |line|
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

    def extract_relevant_sections(sections, old_version, new_version)
      from = Gem::Version.new(old_version.gsub(/-[\w\-]+$/, '')) rescue Gem::Version.new("0.0.0")
      to   = Gem::Version.new(new_version.gsub(/-[\w\-]+$/, '')) rescue Gem::Version.new("9999.9999.9999")
      sections.select do |version, _|
        begin
          v = Gem::Version.new(version.gsub(/-[\w\-]+$/, ''))
          v > from && v <= to
        rescue
          false
        end
      end.sort_by { |v, _| Gem::Version.new(v.gsub(/-[\w\-]+$/, '')) rescue Gem::Version.new("0.0.0") }.reverse.to_h
    end

    def generate_version_range(from_str, to_str)
      from = Gem::Version.new(from_str.gsub(/-[\w\-]+$/, ''))
      to   = Gem::Version.new(to_str.gsub(/-[\w\-]+$/, ''))
      result = Set.new

      # Generate known version steps up to 2000 iterations max (safety limit)
      queue = [from]
      2000.times do
        v = queue.pop
        break if v.nil? || v >= to

        patch = Gem::Version.new("#{v.segments[0]}.#{v.segments[1]}.#{v.segments[2] + 1}")
        minor = Gem::Version.new("#{v.segments[0]}.#{v.segments[1] + 1}.0")
        major = Gem::Version.new("#{v.segments[0] + 1}.0.0")

        [patch, minor, major].each do |next_v|
          next if next_v > to || result.include?(next_v)
          result << next_v
          queue << next_v
        end
      end

      result.select { |v| v > from && v <= to }.sort.map(&:to_s)
    end

  end
end
