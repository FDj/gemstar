module Gemstar
  class RubyGems
    def fetch_rubygems_metadata(gem_name)
      url = "https://rubygems.org/api/v1/gems/#{URI.encode_www_form_component(gem_name)}.json"
      cache_fetch("rubygems-#{gem_name}") do
        URI.open(url).read
      end.then { |json| JSON.parse(json) rescue nil }
    end

    def extract_github_repo_url(meta)
      url = meta["source_code_uri"] || meta["homepage_uri"] || ""
      return nil unless url.include?("github.com")
      url = url.gsub(/\.git$/, '')
      url[%r{https://github\.com/[^/]+/[^/]+}]
    end

  end
end