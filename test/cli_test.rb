# frozen_string_literal: true

require "minitest/autorun"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "gemstar"

class CLITest < Minitest::Test
  def test_version_option_prints_current_version
    stdout, stderr = capture_io do
      Gemstar::CLI.start(["--version"])
    end

    assert_equal "#{Gemstar::VERSION}\n", stdout
    assert_equal "", stderr
  end
end
