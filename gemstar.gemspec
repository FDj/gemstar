# frozen_string_literal: true

require_relative "lib/gemstar/version"

Gem::Specification.new do |s|
  s.name = "gemstar"
  s.version = Gemstar::VERSION
  s.authors = ["Florian Dejako"]
  s.email = ["fdejako@gmail.com"]
  s.homepage = "https://github.com/FDj/gemstar"
  s.summary = "Making sense of gems."
  s.description = "Gem changelog viewer."

  s.metadata = {
    "bug_tracker_uri" => "https://github.com/FDj/gemstar/issues",
    "changelog_uri" => "https://github.com/FDj/gemstar/blob/master/CHANGELOG.md",
    "documentation_uri" => "https://github.com/FDj/gemstar",
    "homepage_uri" => "https://github.com/FDj/gemstar",
    "source_code_uri" => "https://github.com/FDj/gemstar"
  }

  s.license = "MIT"

  s.files = Dir.glob("lib/**/*") + Dir.glob("bin/**/*") + %w[README.md LICENSE.txt CHANGELOG.md]
  s.require_paths = ["lib"]
  s.executables = %w(gemstar)
  s.required_ruby_version = ">= 3.3"

  s.add_development_dependency "bundler", ">= 1.15"
  s.add_development_dependency "combustion", ">= 1.1"
  s.add_development_dependency "rake", ">= 13.0"
  s.add_development_dependency "minitest", "~> 5.0"

  s.add_dependency "kramdown", "~> 2.0"
  s.add_dependency "kramdown-parser-gfm", "~> 1.0"
  s.add_dependency "rouge", ">= 4"
  s.add_dependency "concurrent-ruby", "~> 1.0"
  s.add_dependency "thor", "~> 1.4"
  s.add_dependency "nokogiri", ">= 1.18"
end
