module Gemstar
  class RequestLogger
    def initialize(app, io: $stderr)
      @app = app
      @io = io
    end

    def call(env)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status, headers, body = @app.call(env)
      log_request(env, status, started_at)
      [status, headers, body]
    rescue StandardError => e
      log_request(env, 500, started_at, error: e)
      raise
    end

    private

    def log_request(env, status, started_at, error: nil)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)
      path = env["PATH_INFO"].to_s
      query = env["QUERY_STRING"].to_s
      full_path = query.empty? ? path : "#{path}?#{query}"
      method = env["REQUEST_METHOD"].to_s
      suffix = error ? " #{error.class}: #{error.message}" : ""

      @io.puts "[gemstar] #{method} #{full_path} -> #{status} in #{duration_ms}ms#{suffix}"
    end
  end
end
