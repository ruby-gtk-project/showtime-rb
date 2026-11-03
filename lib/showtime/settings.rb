# frozen_string_literal: true

require "digest"
require "json"
require "fileutils"

module Showtime
  # Settings holds the keys of upstream's GSettings schema,
  # data/org.gnome.Showtime.gschema.xml.in.
  #
  # Upstream declares two schemas there: `org.gnome.Showtime`, which is empty,
  # and `org.gnome.Showtime.State`, which carries the three keys the app
  # actually persists — the end-timestamp type (an enum of Duration and
  # Remaining), whether the window was maximized, and whether playback loops.
  #
  # GSettings needs the schema compiled and installed into a
  # glib-2.0/schemas directory before the app can read a single key, which
  # makes running from a checkout an install step. The same keys, defaults,
  # types and enum nicks are therefore backed by a small JSON file under
  # XDG_CONFIG_HOME instead.
  class Settings
    # The enum from the schema: `<value nick="Duration" value="0"/>` and
    # `<value nick="Remaining" value="1"/>`. Upstream reads it with
    # `get_enum`, i.e. as the integer, and stores the nick.
    END_TIMESTAMP_TYPES = %w[Duration Remaining].freeze

    DEFAULTS = {
      "end-timestamp-type" => "Duration",
      "is-maximized"       => false,
      "looping"            => false,
    }.freeze

    def initialize(path: nil)
      @path = path || default_path
      @values = DEFAULTS.merge(read)
      @listeners = {}
    end

    def location = @path

    def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

    def []=(key, value)
      @values[key.to_s] = value
      write
      notify(key.to_s)
      value
    end

    # `Gio::Settings#get_enum` / `#set_enum`: the key is stored as its nick and
    # read as the index of that nick.
    def get_enum(key) = END_TIMESTAMP_TYPES.index(self[key].to_s) || 0

    def set_enum(key, value)
      self[key] = END_TIMESTAMP_TYPES.fetch(value, END_TIMESTAMP_TYPES.first)
    end

    def get_boolean(key) = self[key] == true

    def set_boolean(key, value)
      self[key] = !!value
    end

    # `Gio::Settings#connect("changed::key")`. The block runs after the new
    # value has been written, so a listener reading the key sees it.
    def on_changed(key, &listener)
      @listeners[key.to_s] ||= []
      @listeners[key.to_s] << listener
      listener
    end

    # The play-position history upstream's main.py keeps beside the schema, in
    # `playback_history.json` under the state directory: the position in
    # nanoseconds of every video the app has played, keyed by the sha256 digest
    # of its URI, oldest entry dropped once the file holds more than
    # MAX_HISTORY_ITEMS of them.
    #
    # It is what makes the video page's resume-or-restart prompt appear:
    # `Window#play_video` reads the position back and only offers to resume
    # when there is one and it is more than a minute in.
    MAX_HISTORY_ITEMS = 1000

    HISTORY_FILE = "playback_history.json"

    def play_position(uri)
      digest = Digest::SHA256.hexdigest(uri.to_s)
      history[digest]
    end

    def save_play_position(uri, position)
      unless uri.to_s.empty?
        history[Digest::SHA256.hexdigest(uri.to_s)] = position
        trim_history
        write_history
      end
    end

    def history_location = @history_location ||= File.join(File.dirname(@path), HISTORY_FILE)

    def history = @history ||= read_history

    # Named accessors for every key, so callers do not repeat the strings.
    DEFAULTS.each_key do |key|
      method_name = key.tr("-", "_")
      define_method(method_name) { self[key] }
      define_method(:"#{method_name}=") { |value| self[key] = value }
      if DEFAULTS[key] == false
        define_method(:"#{method_name}?") { self[key] == true }
      end
    end

    private

      def notify(key)
        @listeners.fetch(key, []).each { |listener| listener.call(self[key]) }
      end

      def default_path
        File.join(
          ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config")),
          "showtime",
          "state.json",
        )
      end

      def read
        if File.exist?(@path)
          parse(File.read(@path))
        else
          {}
        end
      end

      def parse(text)
        parsed = JSON.parse(text)
        if parsed.is_a?(Hash)
          parsed.slice(*DEFAULTS.keys)
        else
          {}
        end
      rescue JSON::ParserError
        {}
      end

      def write
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, "#{JSON.pretty_generate(@values)}\n")
      end

      def read_history
        if File.exist?(history_location)
          parse_history(File.read(history_location))
        else
          {}
        end
      end

      def parse_history(text)
        parsed = JSON.parse(text)
        if parsed.is_a?(Hash)
          parsed
        else
          {}
        end
      rescue JSON::ParserError
        {}
      end

      # Ruby hashes keep insertion order, so the first key is the oldest
      # entry — the same thing upstream's `next(iter(hist))` picks.
      def trim_history
        [history.size - MAX_HISTORY_ITEMS, 0].max.times { history.delete(history.first.first) }
      end

      def write_history
        FileUtils.mkdir_p(File.dirname(history_location))
        File.write(history_location, "#{JSON.generate(history)}\n")
      end
  end
end
