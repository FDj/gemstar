# frozen_string_literal: true

module Gemstar
  class GemfileDiffer

    def run_diff(gemfile_path)
      #+++ edit_gitignore

      # Save previous lockfile from git
      old_lockfile = IO.popen(%w[git show HEAD:Gemfile.lock], &:read)
      File.write("Gemfile.lock.old", old_lockfile)

      old = parse_lockfile("Gemfile.lock.old")
      new = parse_lockfile("Gemfile.lock")

      updates = {}
      failed = []
      mutex = Mutex.new
      pool = Concurrent::FixedThreadPool.new(10)

      (new.keys).each do |gem_name|
        pool.post do
          old_version = old[gem_name]
          new_version = new[gem_name]
          next if old_version == new_version

          puts "Processing #{gem_name} (#{old_version || 'new'} → #{new_version})..."

          begin
            meta = fetch_rubygems_metadata(gem_name)
            repo = meta ? extract_github_repo_url(meta) : nil
            changelog = repo ? fetch_changelog_content(repo, gem_name) : nil
            sections = changelog ? extract_relevant_sections(parse_changelog_sections(changelog), old_version, new_version) : nil

            release_versions = []
            if repo && (!sections || sections.empty?)
              release_versions = generate_version_range(old_version || "0.0.0", new_version)
            end

            release_urls = if repo && release_versions.any?
                             release_versions.map { |ver| "#{repo}/releases/tag/#{ver}" }
                           else
                             []
                           end

            # puts "Versions in changelog for #{gem_name}: #{sections.keys.inspect}" if sections

            compare_url = if repo && old_version
                            tag_from_v = "v#{old_version}"
                            tag_to_v = "v#{new_version}"
                            tag_from_raw = old_version
                            tag_to_raw = new_version

                            url_v = "#{repo}/compare/#{tag_from_v}...#{tag_to_v}"
                            url_raw = "#{repo}/compare/#{tag_from_raw}...#{tag_to_raw}"

                            begin
                              URI.open(url_v, read_timeout: 4)
                              url_v
                            rescue
                              url_raw
                            end
                          end

            homepage_url = meta["homepage_uri"] || meta["source_code_uri"] || "https://rubygems.org/gems/#{gem_name}"
            description = meta["info"]

            entry = {
              old: old_version,
              new: new_version,
              homepage_url: homepage_url,
              description: description
            }
            entry[:sections] = sections unless sections.nil? || sections.empty?
            entry[:compare_url] = compare_url if compare_url

            if entry[:sections].nil? && repo && new_version
              entry[:release_url] = "#{repo}/releases/tag/#{new_version}"
            end
            entry[:release_page] = "#{repo}/releases" if repo && (!sections || sections.empty?)

            if repo && new_version
              version_list = sections ? sections.keys : []
              if version_list.empty?
                version_list = [new_version]
              end

              entry[:release_urls] = version_list.map do |ver|
                "#{repo}/releases/tag/#{ver}"
              end
            end

            mutex.synchronize { updates[gem_name] = entry }
          rescue => e
            mutex.synchronize { failed << [gem_name, e.message] }
            puts "⚠️ Failed to process #{gem_name}: #{e.message}"
          end
        end
      end

      pool.shutdown
      pool.wait_for_termination

      html = render_html(updates.sort.to_h)
      File.write("gem_update_changelog.html", html)
      puts "✅ Written to gem_update_changelog.html"

      if failed.any?
        puts "\n⚠️ The following gems failed to process:"
        failed.each { |gem, msg| puts "  - #{gem}: #{msg}" }
      end

      File.delete("Gemfile.lock.old") if File.exist?("Gemfile.lock.old")

    end

    def render_html(updates)
      body = updates.map do |gem_name, info|
        icon = info[:homepage_url]&.include?("github.com") ? "🐙" : "💎"
        tooltip = info[:description] ? "title=\"#{info[:description].gsub('"', '&quot;')}\"" : ""
        link = "<a href=\"#{info[:homepage_url]}\" #{tooltip} target=\"_blank\">#{gem_name}</a>"
        html = if info[:sections]
                 info[:sections].map do |version, lines|
                   <<~HTML
                     #{Kramdown::Document.new(lines.join).to_html}
                   HTML
                 end.join("\n")
               elsif info[:release_urls]
                 "" # changelog not found, but we have release links — skip message
               else
                 "<p><strong>#{gem_name}:</strong> No changelog entries found</p>"
               end

        <<~HTML
          <section>
            <h2>#{icon} #{link}: #{info[:old] || 'new'} → #{info[:new]}</h2>
            #{info[:release_page] ? "<p><a href='#{info[:release_page]}' target='_blank'>View all GitHub release notes</a></p>" : ""}
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
          #{body}
          <p>Generated on #{DateTime.now.strftime("%Y-%m-%d %H:%M:%S %z")}</p>
        </body>
        </html>
      HTML
    end

  end
end
