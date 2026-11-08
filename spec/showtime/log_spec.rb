# frozen_string_literal: true

require "tmpdir"

RSpec.describe Showtime::Log do
  around do |example|
    Dir.mktmpdir("showtime-log-spec") do |dir|
      original_state_home = ENV["XDG_STATE_HOME"]
      ENV["XDG_STATE_HOME"] = dir
      example.run
    ensure
      ENV["XDG_STATE_HOME"] = original_state_home
    end
  end

  describe "#location" do
    it "puts the log file under XDG_STATE_HOME/showtime/showtime.log" do
      log = described_class.new

      expect(log.location).to eq(File.join(ENV.fetch("XDG_STATE_HOME"), "showtime", "showtime.log"))
      expect(Dir.exist?(File.dirname(log.location))).to eq(true)
    end
  end

  describe "#info / #debug / #warn / #error" do
    it "write the message to both the console and the log file" do
      log = described_class.new(development: true)

      log.info("hello from the spec")

      expect(File.read(log.location)).to include("hello from the spec")
    end

    it "omits DEBUG-level messages when not in development" do
      log = described_class.new(development: false)

      log.debug("should not appear")

      expect(File.read(log.location)).not_to include("should not appear")
    end
  end

  describe ".default / .info / .debug / .warn / .error" do
    it "memoize one instance and delegate the four severities to it" do
      expect(described_class.default).to be_a(described_class)
      expect { described_class.info("via the class method") }.not_to raise_error
    end
  end
end
