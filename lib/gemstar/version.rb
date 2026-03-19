# frozen_string_literal: true

module Gemstar # :nodoc:
  VERSION = "1.0"

  def self.debug?
    return @debug if defined?(@debug)
    @debug = ENV["GEMSTAR_DEBUG"] == "true"
  end
end
