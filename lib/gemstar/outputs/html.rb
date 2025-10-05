# frozen_string_literal: true

require_relative "basic"
require "pathname"
require "kramdown"

module Gemstar
  module Outputs
    class HTML < Basic
      def render_diff(diff_command)
        body = diff_command.updates.sort.map do |gem_name, info|
          icon = info[:homepage_url]&.include?("github.com") ? "🐙" : "💎"
          tooltip = info[:description] ? "title=\"#{info[:description].gsub('"', "&quot;")}\"" : ""
          link = "<a href=\"#{info[:homepage_url]}\" #{tooltip} target=\"_blank\">#{gem_name}</a>"
          html = if info[:sections]
            info[:sections].map do |_version, lines|
              <<~HTML
                #{Kramdown::Document.new(lines.join).to_html}
              HTML
            end.join("\n")
          elsif info[:release_urls]
            "" # the changelog wasn't found, but we have release links — skip the message
          else
            "<p><strong>#{gem_name}:</strong> No changelog entries found</p>"
          end

          <<~HTML
            <section>
              <h2>#{icon} #{link}: #{info[:old] || "new"} → #{info[:new]}</h2>
              #{"<p><a href='#{info[:release_page]}' target='_blank'>View all GitHub release notes</a></p>" if info[:release_page]}
              #{html}
            </section>
          HTML
        end.join("\n")

        project_name = Pathname.getwd.basename.to_s

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
            <h1>#{project_name}: Gem Updates</h1>
            <p><i>Showing changes from #{diff_command.from} to #{diff_command.to || "now"}, generated on #{Time.now.strftime("%Y-%m-%d %H:%M:%S %z")}.</i></p>
            #{body}
          </body>
          </html>
        HTML
      end
    end
  end
end
