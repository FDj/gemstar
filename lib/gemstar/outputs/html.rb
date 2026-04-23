# frozen_string_literal: true

require_relative "basic"
require "pathname"
require "cgi"
require "kramdown"
begin
  require "kramdown-parser-gfm"
rescue LoadError
  # Optional dependency: if not available, we'll gracefully fall back to the default parser
end

module Gemstar
  module Outputs
    class HTML < Basic
      def render_diff(diff_command)
        body = diff_command.updates.sort.map do |gem_name, info|
          icon = icon_for(info)
          tooltip = info[:description] ? "title=\"#{info[:description].gsub('"', "&quot;")}\"" : ""
          link = "<a href=\"#{info[:homepage_url]}\" #{tooltip} target=\"_blank\">#{gem_name}</a>"
          html = if info[:sections]
            info[:sections].map do |_version, lines|
              html_chunk = begin
                opts = { hard_wrap: false }
                opts[:input] = "GFM" if defined?(Kramdown::Parser::GFM)
                Kramdown::Document.new(lines.join, opts).to_html
              rescue Kramdown::Error
                Kramdown::Document.new(lines.join, { hard_wrap: false }).to_html
              end
              <<~HTML
                #{html_chunk}
              HTML
            end.join("\n")
          elsif info[:release_urls]
            "" # the changelog wasn't found, but we have release links — skip the message
          else
            "<p><strong>#{gem_name}:</strong> No changelog entries found</p>"
          end

          <<~HTML
            <section>
              <h2>#{icon} #{link}: #{version_label(info)}</h2>
              #{"<p><a href='#{info[:release_page]}' target='_blank'>View all GitHub release notes</a></p>" if info[:release_page]}
              #{html}
            </section>
          HTML
        end.join("\n")

        project_name = diff_command.project_name

        <<~HTML
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="UTF-8">
            <title>#{project_name}: Gem Updates with Changelogs</title>
            <style>
              body { font-family: sans-serif; padding: 2em; background: #fdfdfd; }
              section { margin-bottom: 3em; border-bottom: 1px solid #ccc; padding-bottom: 1em; }
              h2 { color: #333; }
              h3 { margin-top: 1em; color: #444; }
              pre { background: #eee; padding: 1em; overflow-x: auto; }
              a { color: #0645ad; text-decoration: none; }
            </style>
          </head>
          <body>
            <h1>#{project_name}: Package Updates</h1>
            <p><i>Showing changes from #{diff_command.from} to #{diff_command.to || "now"}, generated on #{Time.now.strftime("%Y-%m-%d %H:%M:%S %z")}.</i></p>
            #{range_details(diff_command)}
            #{body}
            #{considered_commits(diff_command)}
          </body>
          </html>
        HTML
      end

      private

      def icon_for(info)
        return "📦" if info[:package_scope] == "js"
        return "🐙" if info[:homepage_url]&.include?("github.com")

        "💎"
      end

      def version_label(info)
        info[:version_label] || "#{info[:old] || "new"} → #{info[:new]}"
      end

      def range_details(diff_command)
        return "" unless diff_command.since

        cutoff = diff_command.format_commit(diff_command.since_cutoff_commit, fallback_revision: diff_command.from)
        <<~HTML
          <section>
            <h2>Diff Range</h2>
            <p>Since cutoff <code>#{h(diff_command.since)}</code> resolved to #{h(cutoff)}.</p>
          </section>
        HTML
      end

      def considered_commits(diff_command)
        commits = Array(diff_command.considered_commits)
        items = commits.map do |commit|
          %(<li><code>#{h(commit[:short_sha] || commit[:id])}</code> #{h(commit[:authored_at])} #{h(commit[:subject])}</li>)
        end.join("\n")
        items = "<li>No commits found in this range.</li>" if items.empty?

        <<~HTML
          <section>
            <h2>Commits Considered</h2>
            <ul>
              #{items}
            </ul>
          </section>
        HTML
      end

      def h(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
