# frozen_string_literal: true

module Gemstar # :nodoc:
  VERSION = "0.0.1"

  def self.debug?
    return @debug if defined?(@debug)
    @debug = ENV["GEMSTAR_DEBUG"] == "true"
  end
end
