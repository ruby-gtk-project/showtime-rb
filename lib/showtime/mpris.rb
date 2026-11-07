# frozen_string_literal: true

require "gio2"
require_relative "options"
require_relative "translations"
require_relative "utils"

module Showtime
  # Mpris is the port of upstream's showtime/mpris.py: the org.mpris.MediaPlayer2
  # D-Bus interfaces that put the app on the desktop's system media controls.
  # Upstream's own comment credits GNOME Music for most of this file.
  #
  # Upstream's `DBusInterface` walks `Gio::DBusNodeInfo#interfaces` to register
  # whatever its class docstring's XML declares, converts camelCase method
  # names to snake_case, and reads/builds every GVariant generically from the
  # introspected signatures. ShellSearchProvider-style genericism like that
  # needs `GLib::Variant#unpack`, tuple-typed `GLib::Variant.new` and
  # `GLib::VariantBuilder`, none of which this environment's gio2/glib2 gem
  # has — each raises `NotImplementedError: TODO: Ruby -> GVariant(...)` or
  # `NameError: uninitialized constant GLib::VariantBuilder`.
  #
  # `GLib::Variant.parse(text, type)` — GVariant *text* format in, a typed
  # Variant out — has no such gap, so this port builds every tuple, `a{sv}`
  # dict and signal body that way instead, one method/property name at a
  # time rather than generically off the introspected signature. This is the
  # same shape blanket-rb's `Mpris` already ships and drives in its own
  # `test/drive_app.rb`, which is what establishes `GLib::Variant.parse` as
  # the house answer to this binding gap rather than a reason to skip MPRIS.
  class Mpris
    OBJECT_PATH = "/org/mpris/MediaPlayer2"
    INTROSPECTABLE_IFACE = "org.freedesktop.DBus.Introspectable"
    PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"
    MEDIA_PLAYER_IFACE = "org.mpris.MediaPlayer2"
    PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"

    INTERFACES = [INTROSPECTABLE_IFACE, PROPERTIES_IFACE, MEDIA_PLAYER_IFACE, PLAYER_IFACE].freeze

    # Upstream's `RATE_SLOW`/`RATE_NORMAL`/`RATE_FASTER`/`RATE_FASTEST`: the
    # thresholds `_set`'s `Rate` branch buckets an arbitrary MPRIS rate into
    # one of the five toggle-group rates Options offers.
    RATE_SLOW = 0.75
    RATE_NORMAL = 1.125
    RATE_FASTER = 1.375
    RATE_FASTEST = 1.75

    NODE_XML = <<~XML
      <node>
        <interface name="org.freedesktop.DBus.Introspectable">
          <method name="Introspect">
            <arg name="data" direction="out" type="s"/>
          </method>
        </interface>
        <interface name="org.freedesktop.DBus.Properties">
          <method name="Get">
            <arg name="interface" direction="in" type="s"/>
            <arg name="property" direction="in" type="s"/>
            <arg name="value" direction="out" type="v"/>
          </method>
          <method name="Set">
            <arg name="interface_name" direction="in" type="s"/>
            <arg name="property_name" direction="in" type="s"/>
            <arg name="value" direction="in" type="v"/>
          </method>
          <method name="GetAll">
            <arg name="interface" direction="in" type="s"/>
            <arg name="properties" direction="out" type="a{sv}"/>
          </method>
          <signal name="PropertiesChanged">
            <arg name="interface_name" type="s"/>
            <arg name="changed_properties" type="a{sv}"/>
            <arg name="invalidated_properties" type="as"/>
          </signal>
        </interface>
        <interface name="org.mpris.MediaPlayer2">
          <method name="Raise"/>
          <method name="Quit"/>
          <property name="CanQuit" type="b" access="read"/>
          <property name="Fullscreen" type="b" access="readwrite"/>
          <property name="CanRaise" type="b" access="read"/>
          <property name="HasTrackList" type="b" access="read"/>
          <property name="Identity" type="s" access="read"/>
          <property name="DesktopEntry" type="s" access="read"/>
          <property name="SupportedUriSchemes" type="as" access="read"/>
          <property name="SupportedMimeTypes" type="as" access="read"/>
        </interface>
        <interface name="org.mpris.MediaPlayer2.Player">
          <method name="Next"/>
          <method name="Previous"/>
          <method name="Pause"/>
          <method name="PlayPause"/>
          <method name="Stop"/>
          <method name="Play"/>
          <method name="Seek">
            <arg direction="in" name="Offset" type="x"/>
          </method>
          <method name="SetPosition">
            <arg direction="in" name="TrackId" type="o"/>
            <arg direction="in" name="Position" type="x"/>
          </method>
          <method name="OpenUri">
            <arg direction="in" name="Uri" type="s"/>
          </method>
          <signal name="Seeked">
            <arg name="Position" type="x"/>
          </signal>
          <property name="PlaybackStatus" type="s" access="read"/>
          <property name="LoopStatus" type="s" access="readwrite"/>
          <property name="Rate" type="d" access="readwrite"/>
          <property name="Shuffle" type="b" access="readwrite"/>
          <property name="Metadata" type="a{sv}" access="read"/>
          <property name="Position" type="x" access="read"/>
          <property name="MinimumRate" type="d" access="read"/>
          <property name="MaximumRate" type="d" access="read"/>
          <property name="CanGoNext" type="b" access="read"/>
          <property name="CanGoPrevious" type="b" access="read"/>
          <property name="CanPlay" type="b" access="read"/>
          <property name="CanPause" type="b" access="read"/>
          <property name="CanSeek" type="b" access="read"/>
          <property name="CanControl" type="b" access="read"/>
        </interface>
      </node>
    XML

    # `app` is the port's Application — the one object MPRIS needs, since it
    # delegates window, play and playback-state reads the way this class's
    # own callers already do (see application.rb's "Delegated" comment).
    def initialize(app)
      @app = app

      app.play.connect("state-changed") { on_player_state_changed }
      app.play.connect("media-info-updated") { on_media_info_updated }
      app.play.connect("volume-changed") { on_volume_changed }
      app.play.connect("seek-done") { on_seeked }
      app.play.play.signal_connect("notify::rate") { on_rate_changed }
    end

    # Registers every interface on the session bus and owns the well-known
    # name. Separate from #initialize so a drive script can build the
    # server and call its handler directly without a running main loop —
    # the same reason blanket-rb's Mpris splits #build out.
    def build
      @build ||= bus.tap do |connection|
        INTERFACES.each do |name|
          connection.register_object(OBJECT_PATH, interface_info(name)) do |*closure_args|
            handle_method_call(*closure_args.last(4))
          end
        end

        Gio.bus_own_name_on_connection(connection, bus_name, Gio::BusNameOwnerFlags::NONE)
      end
    end

    def bus = @bus ||= Gio.bus_get_sync(Gio::BusType::SESSION)

    def bus_name = "org.mpris.MediaPlayer2.#{Application::APP_ID}"

    def interface_info(name) = Gio::DBusNodeInfo.new(NODE_XML).lookup_interface(name)

    private

      def handle_method_call(interface_name, method_name, parameters, invocation)
        case [interface_name, method_name]
        when [INTROSPECTABLE_IFACE, "Introspect"]
          invocation.return_value(GLib::Variant.parse("(#{quote(NODE_XML)},)", "(s)"))
        when [PROPERTIES_IFACE, "Get"]
          handle_get(parameters, invocation)
        when [PROPERTIES_IFACE, "Set"]
          handle_set(parameters, invocation)
        when [PROPERTIES_IFACE, "GetAll"]
          handle_get_all(parameters, invocation)
        when [MEDIA_PLAYER_IFACE, "Raise"]
          @app.window.present
          invocation.return_value(nil)
        when [MEDIA_PLAYER_IFACE, "Quit"]
          @app.app.quit
          invocation.return_value(nil)
        when [PLAYER_IFACE, "Next"], [PLAYER_IFACE, "Previous"], [PLAYER_IFACE, "OpenUri"]
          # Upstream's own `_next`/`_previous`/`_open_uri`: a single-track
          # player with nothing to switch to and no "open by URI" path of
          # its own, so each is an intentional no-op, not an unfinished one.
          invocation.return_value(nil)
        when [PLAYER_IFACE, "Pause"], [PLAYER_IFACE, "Stop"]
          @app.pause
          if method_name == "Stop"
            @app.play.seek(0)
          end
          invocation.return_value(nil)
        when [PLAYER_IFACE, "Play"]
          @app.unpause
          invocation.return_value(nil)
        when [PLAYER_IFACE, "PlayPause"]
          @app.paused? ? @app.unpause : @app.pause
          invocation.return_value(nil)
        when [PLAYER_IFACE, "Seek"]
          handle_seek(parameters, invocation)
        when [PLAYER_IFACE, "SetPosition"]
          handle_set_position(parameters, invocation)
        else
          invocation.return_dbus_error("#{interface_name}.UnknownMethod", "Unknown method #{method_name}")
        end
      rescue StandardError => e
        invocation.return_dbus_error("#{interface_name}.Error", e.message)
      end

      # `parameters` arrives already unwrapped to a Ruby Array of its
      # tuple's own already-unwrapped values, the same auto-conversion the
      # "change-state"/"activate" action signals get.
      def handle_get(parameters, invocation)
        _interface, name = parameters
        invocation.return_value(GLib::Variant.parse("(#{property_text(name)},)", "(v)"))
      end

      def handle_set(parameters, invocation)
        interface_name, property_name, value = parameters
        apply_set(interface_name, property_name, value)
        invocation.return_value(nil)
      end

      def handle_get_all(parameters, invocation)
        interface, = parameters
        names = property_names(interface)
        body = names.map { |name| "#{quote(name)}: #{property_text(name)}" }.join(", ")
        invocation.return_value(GLib::Variant.parse("({#{body}},)", "(a{sv})"))
      end

      def handle_seek(parameters, invocation)
        offset_usecond, = parameters
        play = @app.play
        play.seek([play.position + (offset_usecond * 1000), 0].max)
        invocation.return_value(nil)
      end

      def handle_set_position(parameters, invocation)
        _track_id, position_usecond = parameters
        @app.play.seek(position_usecond * 1000)
        invocation.return_value(nil)
      end

      def apply_set(interface_name, property_name, value)
        if interface_name == PLAYER_IFACE
          case property_name
          when "Rate"
            @app.rate = rate_bucket(value)
          when "Volume"
            GLib::Idle.add { @app.play.volume = value; false }
          when "LoopStatus", "Shuffle"
            # Upstream's own `_set`: advertised as readwrite, but neither
            # value is wired to anything, matching the real MPRIS
            # implementations this port's clients already talk to.
          end
        end
      end

      def rate_bucket(value)
        if value < RATE_SLOW
          "0.5"
        elsif value < RATE_NORMAL
          "1.0"
        elsif value < RATE_FASTER
          "1.25"
        elsif value < RATE_FASTEST
          "1.5"
        else
          "2.0"
        end
      end

      def property_names(interface)
        case interface
        when MEDIA_PLAYER_IFACE
          %w[CanQuit Fullscreen CanRaise HasTrackList Identity DesktopEntry
             SupportedUriSchemes SupportedMimeTypes]
        when PLAYER_IFACE
          %w[PlaybackStatus LoopStatus Rate Shuffle Metadata Volume Position MinimumRate
             MaximumRate CanGoNext CanGoPrevious CanPlay CanPause CanSeek CanControl]
        else
          []
        end
      end

      # The GVariant text format fragment for a property's *boxed* value —
      # what belongs inside the angle brackets of a variant.
      def property_text(name)
        case name
        when "CanQuit"
          "<true>"
        when "Fullscreen"
          "<#{@app.window.fullscreened?}>"
        when "CanRaise", "HasTrackList"
          "<false>"
        when "Identity"
          "<#{quote(Translations.translate("Video Player"))}>"
        when "DesktopEntry"
          "<#{quote(Application::APP_ID)}>"
        when "SupportedUriSchemes"
          "<@as ['file']>"
        when "SupportedMimeTypes"
          "<@as []>"
        when "PlaybackStatus"
          "<#{quote(playback_status)}>"
        when "LoopStatus"
          "<#{quote(loop_status)}>"
        when "Rate"
          "<#{current_rate}>"
        when "Shuffle"
          "<false>"
        when "Metadata"
          "<#{metadata_text}>"
        when "Volume"
          "<#{@app.play.volume}>"
        when "Position"
          "<@x #{position_usecond}>"
        when "MinimumRate"
          "<0.5>"
        when "MaximumRate"
          "<2.0>"
        when "CanGoNext", "CanGoPrevious"
          "<false>"
        when "CanPlay", "CanPause"
          "<#{can_play?}>"
        when "CanSeek", "CanControl"
          "<true>"
        else
          raise ArgumentError, "No such property '#{name}'"
        end
      end

      def playback_status
        if @app.stopped?
          "Stopped"
        elsif @app.paused?
          "Paused"
        else
          "Playing"
        end
      end

      def loop_status
        if @app.settings.looping?
          "Track"
        else
          "None"
        end
      end

      # `Options#rate` reads "" before the toggle group has a video to show a
      # rate for; upstream's own `win.rate` falls back to "1.0" the same way
      # `Window#step_rate` does.
      def current_rate
        rate = @app.rate
        if Options::RATES.key?(rate)
          rate
        else
          "1.0"
        end
      end

      def position_usecond = @app.play.position / 1000

      def can_play? = !@app.play.uri.to_s.empty?

      # Upstream's `_get_metadata`: no track-id scheme of its own beyond "the
      # one track this single-track player ever has", so a fixed object path
      # stands in once a video is loaded, same as when none is.
      def metadata_text
        media_info = (can_play? && @app.play.media_info) || nil
        fields = metadata_fields(media_info)
        "@a{sv} {#{fields.map { |key, value| "#{quote(key)}: #{value}" }.join(", ")}}"
      end

      TRACK_ID = "<@o '#{OBJECT_PATH}/TrackList/CurrentTrack'>".freeze

      def metadata_fields(media_info)
        if media_info
          title = Utils.get_title(media_info.uri, media_info.title) || Translations.translate("Unknown Title")
          {
            "mpris:trackid" => TRACK_ID,
            "xesam:url"     => "<#{quote(media_info.uri.to_s)}>",
            "mpris:length"  => "<@x #{@app.play.duration / 1000}>",
            "xesam:title"   => "<#{quote(title)}>",
          }
        else
          {"mpris:trackid" => TRACK_ID}
        end
      end

      def properties_changed(interface_name, changed_properties)
        body = changed_properties.map { |name| "#{quote(name)}: #{property_text(name)}" }.join(", ")

        bus.emit_signal(
          nil,
          OBJECT_PATH,
          PROPERTIES_IFACE,
          "PropertiesChanged",
          GLib::Variant.parse("(#{quote(interface_name)}, {#{body}}, @as [])", "(sa{sv}as)"),
        )
      end

      def on_player_state_changed
        properties_changed(PLAYER_IFACE, %w[PlaybackStatus CanPlay CanPause])
      end

      def on_media_info_updated
        properties_changed(PLAYER_IFACE, %w[Metadata CanPlay CanPause])
      end

      def on_volume_changed
        properties_changed(PLAYER_IFACE, %w[Volume])
      end

      def on_rate_changed
        properties_changed(PLAYER_IFACE, %w[Rate])
      end

      def on_seeked
        bus.emit_signal(
          nil,
          OBJECT_PATH,
          PLAYER_IFACE,
          "Seeked",
          GLib::Variant.parse("(#{position_usecond},)", "(x)"),
        )
      end

      ESCAPES = {"\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n"}.freeze

      def quote(value) = %("#{value.to_s.gsub(/[\\"\n]/) { |char| ESCAPES.fetch(char) }}")
  end
end
