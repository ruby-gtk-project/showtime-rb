# frozen_string_literal: true

require "tmpdir"

RSpec.describe Showtime::Settings do
  let(:dir) { Dir.mktmpdir("showtime-settings-spec") }
  let(:path) { File.join(dir, "state.json") }
  let(:settings) { described_class.new(path: path) }

  after { FileUtils.remove_entry(dir) }

  describe "defaults" do
    it "starts with upstream's three State-schema defaults" do
      expect(settings.end_timestamp_type).to eq("Duration")
      expect(settings.is_maximized).to eq(false)
      expect(settings.looping).to eq(false)
    end

    it "answers looping? as a predicate" do
      expect(settings.looping?).to eq(false)
    end
  end

  describe "#[]= and #[]" do
    it "persists a value to disk and reads it back on a new instance" do
      settings["looping"] = true

      expect(File.exist?(path)).to eq(true)
      expect(described_class.new(path: path).looping).to eq(true)
    end
  end

  describe "named accessors" do
    it "round-trip through the same keys #[] and #[]= use" do
      settings.looping = true

      expect(settings[:looping]).to eq(true)
      expect(settings.looping?).to eq(true)
    end
  end

  describe "#get_enum / #set_enum" do
    it "stores the nick and reads back its index, like Gio::Settings" do
      settings.set_enum("end-timestamp-type", 1)

      expect(settings["end-timestamp-type"]).to eq("Remaining")
      expect(settings.get_enum("end-timestamp-type")).to eq(1)
    end

    it "falls back to index 0 for an out-of-range value" do
      settings.set_enum("end-timestamp-type", 99)

      expect(settings.get_enum("end-timestamp-type")).to eq(0)
    end
  end

  describe "#on_changed" do
    it "runs the listener with the new value, after the write" do
      seen = []
      settings.on_changed("looping") { |value| seen << value }

      settings.looping = true

      expect(seen).to eq([true])
    end
  end

  describe "a corrupt or non-object state file" do
    it "falls back to the defaults instead of raising" do
      File.write(path, "not json")

      expect(described_class.new(path: path).looping).to eq(false)
    end
  end

  describe "play position history" do
    it "returns nil for a URI with no saved position" do
      expect(settings.play_position("file:///nope.mp4")).to be_nil
    end

    it "saves and reads back a play position, keyed by the URI's digest" do
      settings.save_play_position("file:///a.mp4", 123_456)

      expect(settings.play_position("file:///a.mp4")).to eq(123_456)
      expect(File.exist?(settings.history_location)).to eq(true)
    end

    it "never saves a position for an empty URI" do
      settings.save_play_position("", 123_456)

      expect(File.exist?(settings.history_location)).to eq(false)
    end

    it "trims the oldest entries once more than MAX_HISTORY_ITEMS are saved" do
      stub_const("#{described_class}::MAX_HISTORY_ITEMS", 2)

      settings.save_play_position("file:///1.mp4", 1)
      settings.save_play_position("file:///2.mp4", 2)
      settings.save_play_position("file:///3.mp4", 3)

      expect(settings.play_position("file:///1.mp4")).to be_nil
      expect(settings.play_position("file:///2.mp4")).to eq(2)
      expect(settings.play_position("file:///3.mp4")).to eq(3)
    end
  end
end
