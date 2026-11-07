# frozen_string_literal: true

require "logger"
require "fileutils"

module Showtime
  # Log is the port of the logging setup in upstream's `main()`
  # (showtime/main.py): a `logging.basicConfig` with a `StreamHandler` (the
  # console) and a `RotatingFileHandler` capped at 1MB, both named "showtime"
  # and both at DEBUG in a development profile, INFO otherwise.
  #
  # Ruby's `Logger` does not fan a single logger out to two devices, so this
  # keeps one of each and `Log.info`/`Log.debug`/`Log.warn` write to both.
  class Log
    MAX_BYTES = 1_000_000

    def self.default = @default ||= new

    def self.info(message) = default.info(message)
    def self.debug(message) = default.debug(message)
    def self.warn(message) = default.warn(message)
    def self.error(message) = default.error(message)

    def initialize(development: ENV["SHOWTIME_DEBUG"] == "1")
      level = development ? Logger::DEBUG : Logger::INFO
      @console = Logger.new($stdout, level: level, formatter: formatter)
      @file = Logger.new(log_file, 1, MAX_BYTES, level: level, formatter: formatter)
    end

    def info(message) = log(:info, message)
    def debug(message) = log(:debug, message)
    def warn(message) = log(:warn, message)
    def error(message) = log(:error, message)

    def location = log_file

    private

      def log(severity, message)
        @console.public_send(severity, "showtime") { message }
        @file.public_send(severity, "showtime") { message }
      end

      def formatter
        proc { |severity, _datetime, progname, msg| "#{severity}: #{progname}: #{msg}\n" }
      end

      def log_file
        @log_file ||= File.join(state_dir, "showtime.log").tap { FileUtils.mkdir_p(state_dir) }
      end

      def state_dir
        File.join(ENV.fetch("XDG_STATE_HOME", File.expand_path("~/.local/state")), "showtime")
      end
  end
end
