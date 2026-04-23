# frozen_string_literal: true

require_relative "basic"
require "pathname"
require "cgi"
require "nokogiri"

module Gemstar
  module Outputs
    class Markdown < Basic
      def render_diff(diff_command)
        project_name = diff_command.project_name
        body = diff_command.updates.sort.map do |gem_name, info|
          render_entry(gem_name, info)
        end.join("\n\n---\n\n")

        <<~MARKDOWN
          # #{project_name}: Package Updates

          _Showing changes from #{diff_command.from} to #{diff_command.to || "now"}, generated on #{Time.now.strftime("%Y-%m-%d %H:%M:%S %z")}._

          #{range_details(diff_command)}

          #{body}

          #{considered_commits(diff_command)}
        MARKDOWN
      end

      private

      def render_entry(gem_name, info)
        title = if info[:homepage_url]
          "## [#{gem_name}](#{info[:homepage_url]})"
        else
          "## #{gem_name}"
        end

        parts = []
        parts << title
        parts << ""
        parts << "*#{info[:version_label] || "#{info[:old] || "new"} → #{info[:new]}"}*"
        parts << ""
        parts << info[:description].to_s unless info[:description].to_s.empty?
        parts << "" unless info[:description].to_s.empty?

        parts.concat(link_lines(info))

        if info[:sections]
          parts << render_sections(info[:sections])
        elsif info[:release_urls]
          parts << "No changelog entries found for this version."
        else
          parts << "No changelog entries found."
        end

        parts.join("\n").strip
      end

      def range_details(diff_command)
        return "" unless diff_command.since

        cutoff = diff_command.format_commit(diff_command.since_cutoff_commit, fallback_revision: diff_command.from)
        "## Diff Range\n\nSince cutoff `#{diff_command.since}` resolved to #{cutoff}."
      end

      def considered_commits(diff_command)
        commits = Array(diff_command.considered_commits)
        lines = ["## Commits Considered", ""]

        if commits.empty?
          lines << "No commits found in this range."
        else
          lines.concat(commits.map do |commit|
            "- `#{commit[:short_sha] || commit[:id]}` #{commit[:authored_at]} #{commit[:subject]}"
          end)
        end

        lines.join("\n")
      end

      def link_lines(info)
        lines = []
        lines << "[Compare changes](#{info[:compare_url]})" if info[:compare_url]
        lines << "[View all GitHub release notes](#{info[:release_page]})" if info[:release_page]
        lines << "" unless lines.empty?
        lines
      end

      def render_sections(sections)
        sections.map do |_version, lines|
          Array(lines).flatten.map { |chunk| markdownize_chunk(chunk) }.join
        end.join("\n\n").strip
      end

      def markdownize_chunk(chunk)
        text = chunk.to_s
        return text unless html_fragment?(text)

        fragment = Nokogiri::HTML::DocumentFragment.parse(text)
        markdown = fragment.children.map { |node| node_to_markdown(node) }.join
        markdown.gsub(/\n{3,}/, "\n\n").strip + "\n"
      rescue StandardError
        text
      end

      def html_fragment?(text)
        text.match?(%r{</?[a-z][^>]*>}i)
      end

      def node_to_markdown(node, list_depth: 0)
        return CGI.unescapeHTML(node.text) if node.text?
        return "" unless node.element?

        case node.name
        when "p"
          "#{inline_children(node).strip}\n\n"
        when "br"
          "  \n"
        when "strong", "b"
          "**#{inline_children(node).strip}**"
        when "em", "i"
          "*#{inline_children(node).strip}*"
        when "code"
          if node.ancestors.any? { |ancestor| ancestor.name == "pre" }
            CGI.unescapeHTML(node.text)
          else
            "`#{CGI.unescapeHTML(node.text)}`"
          end
        when "pre"
          code = CGI.unescapeHTML(node.text).rstrip
          "```\n#{code}\n```\n\n"
        when "a"
          text = inline_children(node).strip
          href = node["href"].to_s
          return text if href.empty?

          "[#{text.empty? ? href : text}](#{href})"
        when "ul"
          list_children(node, ordered: false, list_depth: list_depth)
        when "ol"
          list_children(node, ordered: true, list_depth: list_depth)
        when "li"
          "#{inline_children(node).strip}\n"
        when /\Ah[1-6]\z/
          level = node.name.delete_prefix("h").to_i
          "#{"#" * level} #{inline_children(node).strip}\n\n"
        when "blockquote"
          quote = inline_children(node).strip.lines.map { |line| "> #{line.rstrip}" }.join("\n")
          "#{quote}\n\n"
        when "hr"
          "\n---\n\n"
        else
          children_to_markdown(node, list_depth: list_depth)
        end
      end

      def children_to_markdown(node, list_depth: 0)
        node.children.map { |child| node_to_markdown(child, list_depth: list_depth) }.join
      end

      def inline_children(node)
        children_to_markdown(node).gsub(/\s+/, " ").strip
      end

      def list_children(node, ordered:, list_depth:)
        index = 0

        rendered = node.element_children.filter_map do |child|
          next unless child.name == "li"

          index += 1
          marker = ordered ? "#{index}." : "-"
          prefix = "#{"  " * list_depth}#{marker} "

          item_parts = child.children.map do |grandchild|
            if %w[ul ol].include?(grandchild.name)
              "\n" + list_children(grandchild, ordered: grandchild.name == "ol", list_depth: list_depth + 1).rstrip
            else
              node_to_markdown(grandchild, list_depth: list_depth + 1)
            end
          end.join

          "#{prefix}#{item_parts.strip}\n"
        end

        rendered.join + "\n"
      end
    end
  end
end
