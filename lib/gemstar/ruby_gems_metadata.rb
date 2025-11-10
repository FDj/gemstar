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
              JSON.parse(json) if json
            rescue
              nil
            end }
        end
    end

    def repo_uri
      return nil unless meta

      @repo_uri ||= begin
                      uri = meta["source_code_uri"]

                      if uri.nil?
                        uri = meta["homepage_uri"]
                        if uri.include?("github.com")
                          uri = uri[%r{http[s?]://github\.com/[^/]+/[^/]+}]
                        end
                      end

                      uri ||= ""

                      uri = uri.sub("http://", "https://")

                      uri = uri.gsub(/\.git$/, "")

                      if uri.include?("github.io")
                        # Convert e.g. https://socketry.github.io/console/ to https://github.com/socketry/console/
                        uri = uri.sub(%r{\Ahttps?://([\w-]+)\.github\.io/([^/]+)}) do
                          "https://github.com/#{$1}/#{$2}"
                        end
                      end

                      uri
                    end
    end

  end
end
