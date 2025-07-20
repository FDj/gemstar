# frozen_string_literal: true

module Gemstar
  class GitHub
    def fetch_changelog_content(repo_url, gem_name)
      if repo_url =~ %r{https://github\.com/aws/aws-sdk-ruby}
        base = "https://raw.githubusercontent.com/aws/aws-sdk-ruby/refs/heads/version-3/gems/#{gem_name}"
        aws_style = true
      else
        base = repo_url.sub("https://github.com", "https://raw.githubusercontent.com")
        aws_style = false
      end

      paths = aws_style ? ["CHANGELOG.md"] : %w[
    CHANGELOG.md Changelog.md changelog.md ChangeLog.md
    CHANGES.md Changes.md changes.md
    HISTORY.md History.md history.md
  ]
      branches = aws_style ? [""] : find_main_branch(base)

      paths.product(branches).each do |file, branch|
        url = aws_style ? "#{base}/#{file}" : "#{base}/#{branch}/#{file}"
        # puts "Fetching changelog for #{url}"
        content = cache_fetch("changelog-#{url}") do
          URI.open(url, read_timeout: 8).read rescue nil
        end
        return content if content
      end

      nil
    end
  end
end
