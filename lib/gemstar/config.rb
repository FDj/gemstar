require "fileutils"

module Gemstar
  module Config
    module_function

    def home_directory
      File.expand_path("~/.config/gemstar")
    end

    def ensure_home_directory!
      FileUtils.mkdir_p(home_directory)
    end
  end
end
