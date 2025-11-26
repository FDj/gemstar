# frozen_string_literal: true

module Gemstar # :nodoc:
  VERSION = "0.0.2"

  def self.debug?
    return @debug if defined?(@debug)
    @debug = ENV["GEMSTAR_DEBUG"] == "true"
  end
end
