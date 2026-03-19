module Gemstar
  class WEBrickLogger < WEBrick::Log
    EXPECTED_DISCONNECT_ERRORS = [
      Errno::ECONNRESET,
      Errno::ECONNABORTED,
      Errno::EPIPE
    ].freeze

    def error(message)
      return if expected_disconnect?(message)

      super
    end

    private

    def expected_disconnect?(message)
      EXPECTED_DISCONNECT_ERRORS.any? { |error_class| message.is_a?(error_class) } ||
        message.to_s.start_with?("Errno::ECONNRESET:", "Errno::ECONNABORTED:", "Errno::EPIPE:")
    end
  end
end
