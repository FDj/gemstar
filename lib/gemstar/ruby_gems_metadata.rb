require "open-uri"
require "uri"
require "json"

module Gemstar
  class RubyGemsMetadata
    def initialize(gem_name)
      @gem_name = gem_name
    end

    attr_reader :gem_name

    def meta
      @meta ||=
        begin
          url = "https://rubygems.org/api/v1/gems/#{URI.encode_www_form_component(gem_name)}.json"
          Cache.fetch("rubygems-#{gem_name}") do
            URI.open(url).read
          end.then { |json|
            begin
              JSON.parse(json)
            rescue
              nil
            end }
        end
    end

    def extract_github_repo_url
      return nil unless meta

      url = meta["source_code_uri"] || meta["homepage_uri"] || ""
      return nil unless url.include?("github.com")
      url = url.gsub(/\.git$/, "")
      url[%r{https://github\.com/[^/]+/[^/]+}]
    end

  end
end
