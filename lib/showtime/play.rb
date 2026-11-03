# frozen_string_literal: true

require "gtk4"
require "gstreamer"
require "gobject-introspection"
require_relative "utils"

# GstPlay and GstPbutils ship GObject-Introspection typelibs but have no
# ruby-gnome gem of their own, so the two namespaces are declared here as empty
# top-level modules and filled from their typelibs by
# `Showtime::Play.init` — the same shape `Gst` itself has, one module per GI
# namespace.
module GstPlay; end
module GstPbutils; end

module Showtime
  # Play is the port of upstream's showtime/play.py: the GStreamer half of the
  # app, and the thing every reading on the video page comes from.
  #
  # Upstream's module has two parts. `gst_play_setup` builds the sink that
  # renders into a `Gtk.Picture`, hands its paintable to the picture, wraps the
  # sink in a `glsinkbin` when a GL context is available, and builds the
  # `GstPlay.Play` around it; that is this class's `build`, with each piece a
  # memoized accessor. The `Messenger` GObject, which watches the two buses and
  # re-emits ten signals, is the nested class below.
  #
  # Upstream also tracks `gtk-xft-dpi` so subtitles are rendered at the user's
  # text scale, and filters out qtdemux's unknown-fourcc missing-plugin
  # messages; both are ported.
  class Play
    # The element that renders a video frame into a Gdk::Paintable, from
    # gst-plugins-rs.
    SINK = "gtk4paintablesink"

    # The bin that keeps frames on the GPU when the paintable has a GL context.
    GL_SINK = "glsinkbin"

    # GstStreamVolume's cubic scale is what upstream reads and writes for the
    # volume slider: `pipeline.get_volume(GstAudio.StreamVolumeFormat.CUBIC)`.
    # The GstAudio typelib cannot be loaded by the Ruby GI loader — its
    # GstStreamVolume interface trips over a private INVOKERS constant inside
    # GObjectIntrospection::Loader — so the conversion is done here, with the
    # definition gst_stream_volume_convert_volume uses: cubic to linear is the
    # cube, linear to cubic the cube root.
    CUBIC_EXPONENT = 3.0

    # Raised when the sink cannot be made, which is upstream's
    # `RuntimeError("Cannot make gtk4paintablesink")`.
    class Error < StandardError; end

    class << self
      # `Gst.init()` plus the two namespaces that have no gem. Idempotent, so
      # the application can call it at startup and a second Play still works.
      def init
        unless @initialized
          Gst.init
          GObjectIntrospection::Loader.load("GstPbutils", GstPbutils)
          GObjectIntrospection::Loader.load("GstPlay", GstPlay)
          @initialized = true
        end
      end

      def init? = @initialized == true

      # The audio streams of `media_info`, in the shape `Options#build_menus`
      # takes: the language, the stream's own title tag and its channel count,
      # which are the three things upstream's `build_menus` reads off a
      # `GstPlayAudioInfo`.
      def audio_streams(media_info)
        media_info.audio_streams.map do |stream|
          {
            language: stream.language,
            title:    stream_title(stream),
            channels: stream.channels,
          }
        end
      end

      def subtitle_streams(media_info)
        media_info.subtitle_streams.map do |stream|
          {
            language: stream.language,
            title:    stream_title(stream),
          }
        end
      end

      # `stream.get_tags().get_string("title")`. The Ruby binding returns the
      # C out-parameters as a pair — `[found, value]` — so the value is the
      # last element, and a stream with no tag list has no title at all.
      def stream_title(stream)
        tags = stream.tags
        if tags
          last_of(tags.get_string("title"))
        end
      end

      # The last of a GI multiple-return, which is how the bindings hand back a
      # function's out-parameters, or the value itself when there is only one.
      def last_of(value)
        if value.is_a?(Array)
          value.last
        else
          value
        end
      end

      def first_of(value)
        if value.is_a?(Array)
          value.first
        else
          value
        end
      end
    end

    def initialize(picture)
      @picture = picture
    end

    attr_reader :picture

    def build
      tap do
        Play.init
        picture.paintable = paintable
        messenger.build
        track_subtitle_font_desc
      end
    end

    # Upstream's `connect` on the Messenger, forwarded so the window only ever
    # talks to the Play object.
    def connect(signal, &handler) = messenger.connect(signal, &handler)

    def paintable_sink = @paintable_sink ||= make_paintable_sink
    def paintable = @paintable ||= paintable_sink.get_property("paintable")
    def sink = @sink ||= gl_sink || paintable_sink

    def renderer
      @renderer ||= GstPlay::PlayVideoOverlayVideoRenderer.new_with_sink(nil, sink)
    end

    def play = @play ||= GstPlay::Play.new(renderer)
    def pipeline = @pipeline ||= play.pipeline
    def messenger = @messenger ||= Messenger.new(play, pipeline)

    # The video's URI, and the position and duration the overlays show, in
    # nanoseconds.
    def uri = play.uri

    def uri=(uri)
      play.uri = uri
    end

    def position = play.position
    def duration = play.duration
    def media_info = play.media_info

    def start
      play.play
    end

    def pause
      play.pause
    end

    def seek(position)
      play.seek([position, 0].max)
    end

    def rate = play.rate

    def rate=(rate)
      play.rate = rate
    end

    def mute? = play.mute?

    def mute=(mute)
      play.mute = mute
    end

    def volume = play.volume

    def volume=(volume)
      play.volume = volume
    end

    def cubic_volume = volume**(1.0 / CUBIC_EXPONENT)

    def cubic_volume=(value)
      self.volume = value**CUBIC_EXPONENT
    end

    def subtitle_uri=(uri)
      play.suburi = uri
    end

    def select_subtitle_track(index)
      play.set_subtitle_track(index)
      play.set_subtitle_track_enabled(true)
    end

    def disable_subtitles
      play.set_subtitle_track_enabled(false)
    end

    def select_audio_track(index)
      play.set_audio_track(index)
    end

    # The sink's idea of how large the window is, which it needs to pick a
    # scaling path. Upstream sets it from `do_size_allocate`.
    def window_size=(size)
      paintable_sink.set_property("window-width", size.first)
      paintable_sink.set_property("window-height", size.last)
    end

    # Upstream's `_rotate_left` / `_rotate_right`: the paintable's orientation
    # is a GdkGL-style EXIF value, and the two tables below are the cycles
    # upstream's `match` statements spell out.
    ROTATE_LEFT = {
      0 => 4,
      1 => 4,
      5 => 8,
    }.freeze

    ROTATE_RIGHT = {
      0 => 2,
      4 => 1,
      8 => 5,
    }.freeze

    def rotate_left
      self.orientation = ROTATE_LEFT.fetch(orientation, orientation - 1)
    end

    def rotate_right
      self.orientation = ROTATE_RIGHT.fetch(orientation, orientation + 1)
    end

    def orientation = paintable.get_property("orientation").to_i

    def orientation=(orientation)
      paintable.set_property("orientation", orientation)
    end

    # `pipeline.get_state(Gst.CLOCK_TIME_NONE)[0] != Gst.StateChangeReturn.FAILURE`,
    # which is how upstream tells a partially missing plugin set — the pipeline
    # still prerolled — from a completely missing one.
    def prerolled?
      Play.first_of(pipeline.get_state(Gst::CLOCK_TIME_NONE)) != Gst::StateChangeReturn::FAILURE
    end

    # Messenger is upstream's `Messenger` GObject: it puts a signal watch on
    # both of GstPlay's buses and turns their messages into the ten signals the
    # window listens to.
    #
    # Upstream declares them as real GObject signals so Blueprint could bind
    # them; nothing binds them, each has exactly one listener — the window — so
    # here they are callbacks registered by name with `connect`, and the names
    # are upstream's verbatim.
    #
    # The pipeline bus is watched through an idle callback, exactly as upstream
    # does: a missing-plugin message arrives on a GStreamer streaming thread,
    # and the handler puts widgets on screen.
    class Messenger
      SIGNALS = %w[
        state-changed
        duration-changed
        position-updated
        seek-done
        media-info-updated
        volume-changed
        end-of-stream
        warning
        error
        missing-plugin
      ].freeze

      # qtdemux invents {audio,video,text,meta}/x-gst-fourcc-<fourcc> caps for
      # any fourcc it does not recognise in a QuickTime/MP4 file. If a decoder
      # existed, qtdemux would know the fourcc and emit proper caps, so these
      # messages are not actionable from the missing-plugin page and upstream
      # filters them out.
      FOURCC = "x-gst-fourcc"

      DETAIL = "detail"

      def initialize(play, pipeline)
        @play = play
        @pipeline = pipeline
        @handlers = {}
      end

      def connect(signal, &handler)
        @handlers[signal.to_s] ||= []
        @handlers[signal.to_s] << handler
        handler
      end

      def build
        tap do
          @play.message_bus.tap do |bus|
            bus.add_signal_watch
            bus.signal_connect("message") do |_bus, message|
              on_play_bus_message(message)
            end
          end

          @pipeline.bus.tap do |bus|
            bus.add_signal_watch
            bus.signal_connect("message") do |_bus, message|
              GLib::Idle.add do
                on_pipeline_bus_message(message)
                false
              end
            end
          end
        end
      end

      private

        def on_play_bus_message(message)
          case GstPlay::PlayMessage.parse_type(message)
          when GstPlay::PlayMessage::STATE_CHANGED
            emit("state-changed", GstPlay::PlayMessage.parse_state_changed(message))
          when GstPlay::PlayMessage::DURATION_CHANGED
            emit("duration-changed", GstPlay::PlayMessage.parse_duration_changed(message))
          when GstPlay::PlayMessage::POSITION_UPDATED
            emit("position-updated", GstPlay::PlayMessage.parse_position_updated(message))
          when GstPlay::PlayMessage::SEEK_DONE
            emit("seek-done")
          when GstPlay::PlayMessage::MEDIA_INFO_UPDATED
            emit("media-info-updated", GstPlay::PlayMessage.parse_media_info_updated(message))
          when GstPlay::PlayMessage::VOLUME_CHANGED
            emit("volume-changed")
          when GstPlay::PlayMessage::END_OF_STREAM
            emit("end-of-stream")
          when GstPlay::PlayMessage::WARNING
            emit("warning", Play.first_of(GstPlay::PlayMessage.parse_warning(message)))
          when GstPlay::PlayMessage::ERROR
            emit("error", Play.first_of(GstPlay::PlayMessage.parse_error(message)))
          end
        end

        def on_pipeline_bus_message(message)
          if actionable_missing_plugin?(message)
            emit("missing-plugin", message)
          end
        end

        def actionable_missing_plugin?(message)
          GstPbutils.missing_plugin_message?(message) && !unknown_fourcc?(message)
        end

        def unknown_fourcc?(message)
          structure = message.structure
          if structure&.has_field?(DETAIL)
            fourcc_caps?(structure[DETAIL])
          else
            false
          end
        end

        def fourcc_caps?(caps) = caps.is_a?(Gst::Caps) && caps.to_s.include?(FOURCC)

        def emit(signal, *arguments)
          @handlers.fetch(signal, []).each { |handler| handler.call(*arguments) }
        end
    end

    private

      def make_paintable_sink
        Gst::ElementFactory.make(SINK).tap do |sink|
          unless sink
            raise(Error, "Cannot make #{SINK}")
          end
        end
      end

      # Upstream wraps the sink in a `glsinkbin` whenever the paintable has a
      # GL context. Its second condition — that the system is not Darwin,
      # where OpenGL misbehaves — is dropped: this port is packaged for Linux
      # only, which the flake's `meta.platforms` states.
      def gl_sink
        if gl_context?
          make_gl_sink
        end
      end

      def gl_context? = !paintable.get_property("gl-context").nil?

      def make_gl_sink
        Gst::ElementFactory.make(GL_SINK).tap do |bin|
          bin&.set_property("sink", paintable_sink)
        end
      end

      def track_subtitle_font_desc
        Gtk::Settings.default&.signal_connect("notify::gtk-xft-dpi") do
          apply_subtitle_font_desc
        end
        apply_subtitle_font_desc
      end

      def apply_subtitle_font_desc
        font_desc = Utils.subtitle_font_desc
        if font_desc
          pipeline.set_property("subtitle-font-desc", font_desc)
        end
      end

  end
end
