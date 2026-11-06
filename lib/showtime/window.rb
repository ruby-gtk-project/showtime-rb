# frozen_string_literal: true

require "adwaita"
require "digest"
require_relative "about_dialog"
require_relative "drag_overlay"
require_relative "options"
require_relative "placeholder_page"
require_relative "play"
require_relative "primary_menu"
require_relative "settings"
require_relative "translations"
require_relative "utils"
require_relative "video_page"

module Showtime
  # Window is the port of upstream's showtime/widgets/window.py and its
  # template, showtime/gtk/window.blp: the single application window, which
  # holds both the placeholder page (ported separately as PlaceholderPage) and
  # the video page (VideoPage) in a Gtk::Stack, and owns the GStreamer
  # pipeline (Play) that drives whichever one is showing.
  #
  # Where upstream reaches its widgets as `Gtk.Template.Child` fields on a
  # `$Window` subclass, this port builds the same tree declaratively and talks
  # to VideoPage, PlaceholderPage, Play and the rest of the already-ported
  # pieces entirely through the callbacks and setters each of them already
  # exposes — this class supplies every callback VideoPage's constructor takes
  # and every one PlaceholderPage's `show_error` / `show_missing_plugin` take.
  #
  # Three upstream behaviours are intentionally not ported, each noted at its
  # call site below: the PackageKit-backed "Install Plugin" button (no
  # installer exists to drive in this environment, so the missing-plugin page
  # always shows the "could not be found" wording); session inhibition while
  # playing (`app.inhibit_win` / `uninhibit_win`, which this port's
  # Application has no counterpart for); and opening a second window to retry
  # a failed stream (`_try_again` just replays the file in this window).
  class Window
    # From upstream's window.blp template: a 16:9 aspect ratio at the minimum
    # height, and 360px wide, which is what the metainfo file requires.
    DEFAULT_WIDTH = 800
    DEFAULT_HEIGHT = 500
    MIN_WIDTH = 360
    MIN_HEIGHT = 202

    # For large enough monitors, occupy 40% of the screen area when opening a
    # window with a video; for small ones (1280×1024 or smaller), 80%.
    DEFAULT_OCCUPY_SCREEN = 0.4
    SMALL_SCREEN_AREA = 1280 * 1024
    SMALL_OCCUPY_SCREEN = 0.8

    # Below this many pixels of difference, a resize from a media-info change
    # is not worth animating.
    SMALL_SIZE_CHANGE = 10

    # The seek scale runs 0..500 rather than 0..1, matching VideoPage's own
    # SCALE_MULT, so that dragging it is not rough.
    SCALE_MULT = VideoPage::SCALE_MULT

    MINUTE_IN_NS = 60_000_000_000
    SEEK_STEP_NS = 10_000_000_000
    VOLUME_STEP = 0.05

    RATES = Options::RATES.keys.freeze

    # `GLib.MAXUINT16`, upstream's index for "no subtitles".
    NO_SUBTITLES = 65_535

    def initialize(app, settings: Settings.new)
      @app = app
      @settings = settings
      @paused = true
      @stopped = true
      @buffering = false
      @seeking = false
      @reveal_animations = {}
      @hide_animations = {}
      @overlay_motions = []
      @prev_motion_xy = [nil, nil]
      @already_shown_missing_plugin = false
    end

    attr_reader :app

    def build
      unless @built
        @built = true
        window_group.add_window(window)

        window.tap do |win|
          win.content = toast_overlay

          toast_overlay.child = drag_overlay.build

          drag_overlay.tap do |overlay|
            overlay.child = stack
            overlay.overlayed = drag_highlight
            overlay.drop_target = drop_target
            overlay.add_controller(drop_target)
          end

          stack.tap do |pages|
            pages.add_child(placeholder_page.build)
            pages.add_child(video_page.build)
          end

          win.add_controller(escape_controller)

          win.signal_connect("notify::maximized") do
            @settings.is_maximized = win.maximized?
          end
        end

        play.build
        wire_play
        wire_video_page_overlays
        connect_resize
        create_actions
        install_breakpoints

        placeholder_page.show_open
      end
      window
    end

    def present = window.present

    # The GStreamer half of the window — exposed so a future MPRIS
    # integration (or a test) can read it without reaching past this class.
    def play = @play ||= Play.new(video_page.picture)

    def paused? = @paused
    def stopped? = @stopped

    # Memoized widgets

    def window
      @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
        win.title = Translations.translate("Video Player")
        win.set_default_size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
        win.width_request = MIN_WIDTH
        win.height_request = MIN_HEIGHT
        win.maximized = @settings.is_maximized
      end
    end

    def window_group = @window_group ||= Gtk::WindowGroup.new

    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new

    def drag_overlay = @drag_overlay ||= DragOverlay.new

    def stack = @stack ||= Gtk::Stack.new

    def primary_menu = @primary_menu ||= PrimaryMenu.new.build

    def placeholder_page = @placeholder_page ||= PlaceholderPage.new(menu_model: primary_menu)

    def video_page
      @video_page ||= VideoPage.new(
        menu_model:             primary_menu,
        on_motion:              ->(x = nil, y = nil) { on_motion(x, y) },
        on_seek:                ->(value) { seek_to(value) },
        on_primary_click:       ->(gesture, presses) { on_primary_click(gesture, presses) },
        on_secondary_click:     ->(gesture, x, y) { secondary_click(gesture, x, y) },
        on_cycle_end_timestamp: -> { cycle_end_timestamp_type },
        on_resume:              -> { unpause },
        on_restart:             -> { play.seek(0); unpause },
        on_rotate_left:         -> { play.rotate_left },
        on_rotate_right:        -> { play.rotate_right },
        on_rate:                ->(rate) { play.rate = rate.to_f },
        on_mute:                ->(muted) { play.mute = muted },
        on_volume:              ->(value) { GLib::Idle.add { play.cubic_volume = value; false } },
      )
    end

    def about_dialog = @about_dialog ||= AboutDialog.new.build

    # The drop-target highlight DragOverlay shows while a video is dragged
    # over the window: upstream's `Adw.Bin { can-target: false; styles
    # ["background"]; child: Adw.StatusPage { ... } }`.
    def drag_highlight
      @drag_highlight ||= Adwaita::Bin.new.tap do |bin|
        bin.can_target = false
        bin.add_css_class("background")
        bin.child = drag_status_page
      end
    end

    def drag_status_page
      @drag_status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.title = Translations.translate("Drop Video to Play")
        page.icon_name = "video-x-generic-symbolic"
        page.add_css_class("showtime-dragging-area-highlight")
      end
    end

    def drop_target
      @drop_target ||= Gtk::DropTarget.new(Gio::File.gtype, :copy).tap do |target|
        target.signal_connect("drop") do |_target, gfile, _x, _y|
          play_video(gfile)
          true
        end
      end
    end

    def open_video_dialog
      @open_video_dialog ||= Gtk::FileDialog.new.tap do |dialog|
        dialog.default_filter = Gtk::FileFilter.new.tap do |filter|
          filter.name = Translations.translate("Video")
          filter.add_mime_type("video/*")
        end
      end
    end

    def choose_subtitles_dialog
      @choose_subtitles_dialog ||= Gtk::FileDialog.new.tap do |dialog|
        dialog.default_filter = Gtk::FileFilter.new.tap do |filter|
          filter.name = Translations.translate("Subtitles")
          %w[application/x-subrip text/x-ssa text/vtt].each { |type| filter.add_mime_type(type) }
          %w[srt ssa ass vtt].each { |suffix| filter.add_suffix(suffix) }
        end
      end
    end

    def escape_controller
      @escape_controller ||= Gtk::ShortcutController.new.tap do |controller|
        controller.add_shortcut(escape_shortcut)
      end
    end

    # Unfullscreen on Escape: no action carries this, so it is a callback
    # shortcut exactly like upstream's `Gtk.CallbackAction`.
    def escape_shortcut
      @escape_shortcut ||= Gtk::Shortcut.new(
        Gtk::KeyvalTrigger.new(Gdk::Keyval::KEY_Escape, 0),
        Gtk::CallbackAction.new { window.unfullscreen; true },
      )
    end

    private

      # Play wiring

      def wire_play
        play.connect("state-changed") { |state| on_playback_state_changed(state) }
        play.connect("duration-changed") { |duration| on_duration_changed(duration) }
        play.connect("position-updated") { |position| on_position_updated(position) }
        play.connect("seek-done") { on_seek_done }
        play.connect("media-info-updated") { |media_info| on_media_info_updated(media_info) }
        play.connect("volume-changed") { on_volume_changed }
        play.connect("end-of-stream") { on_end_of_stream }
        play.connect("warning") { |warning| on_warning(warning) }
        play.connect("error") { |error| on_error(error) }
        play.connect("missing-plugin") { |message| on_missing_plugin(message) }
      end

      def on_playback_state_changed(state)
        if state == GstPlay::PlayState::BUFFERING
          @buffering = true
          GLib::Timeout.add_seconds(1) do
            if @buffering
              reveal_overlay(video_page.spinner)
            end
            false
          end
        else
          @buffering = false
          hide_overlay(video_page.spinner)
          case state
          when GstPlay::PlayState::PAUSED
            self.paused = true
          when GstPlay::PlayState::STOPPED
            self.paused = true
            @stopped = true
          when GstPlay::PlayState::PLAYING
            self.paused = false
          end
        end
      end

      def paused=(value)
        @stopped = @stopped && value
        unless @paused == value
          @paused = value
          video_page.paused = value
        end
      end

      def on_duration_changed(duration)
        set_end_timestamp_label(play.position, duration)
      end

      def on_position_updated(position)
        duration = play.duration
        if duration.positive?
          video_page.progress = position.to_f / duration
        else
          video_page.progress = 0.0
        end
        video_page.position = position
        set_end_timestamp_label(position, duration)
      end

      def on_seek_done
        position = play.position
        duration = play.duration
        if duration.positive?
          video_page.progress = position.to_f / duration
        else
          video_page.progress = 0.0
        end
        video_page.position = position
        set_end_timestamp_label(position, duration)
      end

      def on_media_info_updated(media_info)
        video_page.title = Utils.get_title(media_info.uri, media_info.title).to_s
        video_page.options.schedule_menus
        GLib::Timeout.add(500) do
          video_page.options.build_menus(
            audio_streams:    Play.audio_streams(media_info),
            subtitle_streams: Play.subtitle_streams(media_info),
          )
          false
        end
      end

      def on_volume_changed
        volume = play.cubic_volume
        unless @prev_volume == volume
          @prev_volume = volume
          video_page.sound_options.volume = volume
        end
      end

      def on_end_of_stream
        unless @settings.looping?
          pause
        end
        play.seek(0)
      end

      # Upstream logs the warning; this port has no logger (see
      # AboutDialog's note on `debug_info`), so there is nothing else for a
      # GStreamer warning to do.
      def on_warning(_warning); end

      def on_error(error)
        unless placeholder_page.showing_missing_plugin?
          placeholder_page.show_error(
            on_try_again:    -> { try_again },
            on_copy_details: -> { copy_error_details(error) },
          )
          stack.visible_child = placeholder_page.toolbar_view
        end
      end

      def copy_error_details(error)
        display = Gdk::Display.default
        if display
          display.clipboard.set(error.message.to_s)
          toast_overlay.add_toast(Adwaita::Toast.new(Translations.translate("Details copied")))
        end
      end

      # Upstream reopens the file in a brand new window and closes this one;
      # this port has no multi-window `do_activate(gfile)` path, so it simply
      # replays the same file here.
      def try_again
        if @playing_gfile
          play_video(@playing_gfile)
        end
      end

      # Upstream offers to install the missing codec through PackageKit. No
      # installer is driven here, so the page always falls back to its
      # "could not be found" wording (`on_install: nil` is a real, complete
      # branch of PlaceholderPage#show_missing_plugin, not a stub).
      def on_missing_plugin(message)
        unless @already_shown_missing_plugin
          @already_shown_missing_plugin = true
          partially_missing = play.prerolled?
          if partially_missing
            pause
          end

          description = GstPbutils.missing_plugin_message_get_description(message).to_s
          placeholder_page.show_missing_plugin(
            description:,
            on_install:    nil,
            on_try_anyway: partially_missing ? -> { try_anyway } : nil,
          )
          stack.visible_child = placeholder_page.toolbar_view
        end
      end

      def try_anyway
        placeholder_page.missing_plugin_status_page.child = nil
        stack.visible_child = video_page.root
        unpause
      end

      def set_end_timestamp_label(position, duration)
        if @settings.get_enum("end-timestamp-type").zero?
          video_page.end_timestamp = Utils.nanoseconds_to_timestamp(duration)
        else
          video_page.end_timestamp = "-#{Utils.nanoseconds_to_timestamp(duration - position)}"
        end
      end

      # Playback

      def play_video(gfile)
        save_current_play_position
        @playing_gfile = gfile
        @already_shown_missing_plugin = false

        uri = uri_for(gfile)
        @resume_position = @settings.play_position(uri)

        stack.visible_child = video_page.root
        select_subtitles(0)
        video_page.options.rate = "1.0"

        play.uri = uri
        pause
        on_motion
        enable_post_play_actions

        if @resume_position && @resume_position >= MINUTE_IN_NS
          offer_resume
        end
        unless @resume_position && @resume_position >= MINUTE_IN_NS
          unpause
        end
      end

      # A symlink plays from the file it points at, so that two symlinks to
      # the same video share one play-position entry — upstream's own reason
      # for resolving the link before taking `get_uri`.
      def uri_for(gfile)
        info = query_symlink_info(gfile)
        if info && info.symlink?
          target = info.symlink_target
        else
          target = nil
        end
        if target
          Gio::File.new_for_path(target).uri
        else
          gfile.uri
        end
      end

      def query_symlink_info(gfile)
        gfile.query_info("standard::is-symlink,standard::symlink-target", :nofollow_symlinks)
      rescue StandardError
        nil
      end

      def save_current_play_position
        uri = play.uri
        if uri
          @settings.save_play_position(uri, play.position)
        end
      end

      def offer_resume
        reveal_overlay(video_page.restore_overlay)
        hide_overlay(video_page.controls_box)
        play.seek(@resume_position)
      end

      def enable_post_play_actions
        window.lookup_action("screenshot")&.enabled = true
        window.lookup_action("show-in-files")&.enabled = true
      end

      def unpause
        hide_overlay(video_page.restore_overlay)
        reveal_overlay(video_page.controls_box)
        play.start
      end

      def pause
        play.pause
      end

      def step_rate(step)
        if RATES.include?(video_page.options.rate)
          current = video_page.options.rate
        else
          current = "1.0"
        end
        index = RATES.index(current)
        video_page.options.rate = RATES[(index + step).clamp(0, RATES.size - 1)]
      end

      def select_subtitles(index)
        action = window.lookup_action("select-subtitles")
        action&.activate(GLib::Variant.new(index, GLib::VariantType.new("q")))
      end

      def seek_to(value)
        unless @seeking
          @seeking = true
          @seek_paused = @paused
        end
        unless @paused
          pause
        end
        play.seek([play.duration * (value / SCALE_MULT.to_f), 0].max)

        @last_seek = monotonic_now
        seeked_at = @last_seek
        GLib::Timeout.add(250) do
          if seeked_at == @last_seek
            unless @seek_paused
              unpause
            end
            @seeking = false
          end
          false
        end
      end

      def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Overlay reveal/hide, cursor and resize

      def on_motion(x = nil, y = nil)
        moved = x.nil? || y.nil? || [x, y] != @prev_motion_xy
        if moved
          unless x.nil? || y.nil?
            @prev_motion_xy = [x, y]
          end
          window.set_cursor_from_name(nil)
          video_page.overlay_widgets.each { |widget| reveal_overlay(widget) }

          @last_reveal = monotonic_now
          revealed_at = @last_reveal
          GLib::Timeout.add_seconds(2) { hide_overlays(revealed_at); false }
        end
      end

      def secondary_click(gesture, x, y)
        video_page.options.on_secondary_click_pressed(
          window,
          gesture,
          x,
          y,
        )
      end

      def on_primary_click(gesture, presses)
        gesture.state = :claimed
        on_motion
        if presses.even?
          window.fullscreened = !window.fullscreened?
        end
      end

      def hide_overlays(timestamp)
        busy = timestamp != @last_reveal ||
               video_page.overlay_motions.any?(&:contains_pointer?) ||
               video_page.overlay_menu_buttons.any?(&:active?) ||
               video_page.restore_overlay.can_target?
        unless busy
          video_page.overlay_widgets.each { |widget| hide_overlay(widget) }
          if video_page.pointer_over_video?
            window.set_cursor_from_name("none")
          end
        end
      end

      def cycle_end_timestamp_type
        @settings.set_enum("end-timestamp-type", @settings.get_enum("end-timestamp-type").zero? ? 1 : 0)
        set_end_timestamp_label(play.position, play.duration)
      end

      def reveal_overlay(widget) = set_overlay_revealed(widget, true)
      def hide_overlay(widget) = set_overlay_revealed(widget, false)

      def set_overlay_revealed(widget, reveal)
        if reveal
          animations = @reveal_animations
        else
          animations = @hide_animations
        end
        current = animations[widget]
        if current.nil? || current.state != :playing
          widget.can_target = reveal
          animations[widget] = Adwaita::TimedAnimation.new(
            widget,
            widget.opacity,
            reveal ? 1 : 0,
            250,
            Adwaita::PropertyAnimationTarget.new(widget, "opacity"),
          )
          animations[widget].play
        end
      end

      # Upstream's `_resize_window`: the GStreamer paintable reports its
      # intrinsic size once a stream has one, and the window grows or shrinks
      # to roughly match it, centred on the screen it first opens on.
      def connect_resize
        play.paintable.signal_connect("invalidate-size") do
          if window.visible?
            GLib::Timeout.add(100) { resize_window(play.paintable); false }
          else
            handler_id = nil
            handler_id = window.signal_connect("map") do
              resize_window(play.paintable, initial: true)
              window.signal_handler_disconnect(handler_id)
            end
          end
        end
      end

      def resize_window(paintable, initial: false)
        video_width = paintable.intrinsic_width
        video_height = paintable.intrinsic_height
        if video_width.positive? && video_height.positive?
          surface = window.surface
          monitor = surface && window.display&.get_monitor_at_surface(surface)
          if monitor
            apply_resize(
              video_width,
              video_height,
              monitor,
              surface,
              initial,
            )
          end
        end
      end

      def apply_resize(video_width, video_height, monitor, surface, initial)
        video_area = video_width * video_height
        init_width = window.default_width
        init_height = window.default_height

        if initial
          size = initial_size(
            video_width,
            video_height,
            video_area,
            monitor,
            surface,
          )
        else
          size = scaled_size(video_width, video_height, init_width * init_height)
        end

        nat_width = size.first.round
        nat_height = size.last.round

        worth_animating = initial ||
                           (init_width - nat_width).abs >= SMALL_SIZE_CHANGE ||
                           (init_height - nat_height).abs >= SMALL_SIZE_CHANGE

        if worth_animating
          animate_resize(
            "default-width",
            init_width,
            nat_width,
            initial,
          )
          animate_resize(
            "default-height",
            init_height,
            nat_height,
            initial,
          )
        end
      end

      # Algorithm copied from Loupe (by way of upstream):
      # https://gitlab.gnome.org/GNOME/loupe/-/blob/4ca5f9e/src/widgets/image/rendering.rs#L151
      def initial_size(video_width, video_height, video_area, monitor, surface)
        hidpi_scale = surface.scale_factor
        monitor_width = monitor.geometry.width
        monitor_height = monitor.geometry.height
        monitor_area = monitor_width * monitor_height
        logical_monitor_area = monitor_area * (hidpi_scale**2)

        if logical_monitor_area <= SMALL_SCREEN_AREA
          occupy = SMALL_OCCUPY_SCREEN
        else
          occupy = DEFAULT_OCCUPY_SCREEN
        end
        size_scale = Math.sqrt((monitor_area.to_f / video_area) * occupy)
        target_scale = [1, size_scale].min

        width = video_width * target_scale
        height = video_height * target_scale

        max_width = monitor_width - 20
        if width > max_width
          width = max_width
          height = video_height * width / video_width
        end

        max_height = monitor_height - ((50 + 35 + 20) * hidpi_scale)
        if height > max_height
          height = max_height
          width = video_width * height / video_height
        end

        [width, height]
      end

      def scaled_size(video_width, video_height, prev_area)
        if video_width > video_height
          ratio = video_width.to_f / video_height
          width = Math.sqrt(prev_area * ratio)
          height = width / ratio
        else
          ratio = video_height.to_f / video_width
          width = Math.sqrt(prev_area / ratio)
          height = width * ratio
        end
        [width, height]
      end

      def animate_resize(property, from, to, initial)
        animation = Adwaita::TimedAnimation.new(
          window,
          from,
          to,
          500,
          Adwaita::PropertyAnimationTarget.new(window, property),
        )
        animation.easing = :ease_out_expo
        if initial
          animation.skip
        else
          animation.play
        end
      end

      # The widgets that fade with the pointer also keep the overlays up
      # while any of their own popovers or hover state is active; VideoPage
      # exposes the current list through `overlay_motions`, built once its
      # `build` has run.
      def wire_video_page_overlays
        video_page.overlay_motions
      end

      # Breakpoints

      def install_breakpoints
        window.add_breakpoint(wide_breakpoint)
      end

      def wide_breakpoint
        @wide_breakpoint ||= Adwaita::Breakpoint.new(
          Adwaita::BreakpointCondition.parse("min-width: 550px"),
        ).tap do |point|
          point.add_setter(video_page.toolbar_box, "margin-bottom", int_value(24))
          point.add_setter(video_page.toolbar_box, "margin-start", int_value(24))
          point.add_setter(video_page.toolbar_box, "margin-end", int_value(24))
          point.add_setter(video_page.restore_overlay, "margin-bottom", int_value(90))
        end
      end

      def int_value(value) = GLib::Value.new(GLib::Type::INT, value)

      # Actions

      def create_actions
        add_action("close-window", %w[<primary>w q]) { window.close }
        add_action("about") { about_dialog.present(window) }
        add_action("toggle-fullscreen", %w[F11 f]) { window.fullscreened = !window.fullscreened? }
        add_action("toggle-playback", %w[p k space]) { @paused ? unpause : pause }
        add_action("increase-volume", %w[Up]) { play.volume = [play.volume + VOLUME_STEP, 1.0].min }
        add_action("decrease-volume", %w[Down]) { play.volume = [play.volume - VOLUME_STEP, 0.0].max }
        add_action("toggle-mute", %w[m]) { self.mute = !mute }
        add_action("backwards", %w[Left]) { play.seek([play.position - SEEK_STEP_NS, 0].max) }
        add_action("forwards", %w[Right]) { play.seek(play.position + SEEK_STEP_NS) }
        add_action("decrease-rate", %w[bracketleft]) { step_rate(-1) }
        add_action("increase-rate", %w[bracketright]) { step_rate(1) }
        add_action("screenshot", ["<primary><alt>s"]) { take_screenshot }.enabled = false
        add_action("show-in-files") { show_in_files }.enabled = false
        add_action("open-video", %w[<primary>o]) { open_video }
        add_action("choose-subtitles") { open_choose_subtitles }

        create_select_subtitles_action
        create_select_language_action
        create_toggle_loop_action
      end

      def add_action(name, accelerators = [], &callback)
        Gio::SimpleAction.new(name, nil).tap do |action|
          action.signal_connect("activate") { callback.call }
          window.add_action(action)
          unless accelerators.empty?
            app.set_accels_for_action("win.#{name}", accelerators)
          end
        end
      end

      def mute = play.mute?

      def mute=(value)
        play.mute = value
        video_page.sound_options.mute = value
      end

      def create_select_subtitles_action
        Gio::SimpleAction.new(
          "select-subtitles",
          GLib::VariantType.new("q"),
          GLib::Variant.new(0, GLib::VariantType.new("q")),
        ).tap do |action|
          action.signal_connect("activate") do |a, index|
            a.state = GLib::Variant.new(index, GLib::VariantType.new("q"))
            if index == NO_SUBTITLES
              play.disable_subtitles
            else
              play.select_subtitle_track(index)
            end
          end
          window.add_action(action)
        end
      end

      def create_select_language_action
        Gio::SimpleAction.new(
          "select-language",
          GLib::VariantType.new("q"),
          GLib::Variant.new(0, GLib::VariantType.new("q")),
        ).tap do |action|
          action.signal_connect("activate") do |a, index|
            a.state = GLib::Variant.new(index, GLib::VariantType.new("q"))
            play.select_audio_track(index)
          end
          window.add_action(action)
        end
      end

      def create_toggle_loop_action
        Gio::SimpleAction.new(
          "toggle-loop",
          nil,
          GLib::Variant.new(@settings.looping?),
        ).tap do |action|
          toggle = lambda do |a, *_|
            value = !a.state
            a.state = GLib::Variant.new(value)
            @settings.looping = value
          end
          action.signal_connect("activate", &toggle)
          action.signal_connect("change-state", &toggle)
          window.add_action(action)
        end
      end

      def take_screenshot
        paintable = video_page.picture.paintable
        if paintable
          texture = Utils.screenshot(paintable, window)
          if texture
            save_screenshot(texture)
          end
        end
      end

      def save_screenshot(texture)
        title = Utils.get_title(play.uri, play.media_info&.title) || Translations.translate("Unknown Title")
        timestamp = Utils.nanoseconds_to_timestamp(play.position, hours: true)
        dialog = Gtk::FileDialog.new.tap { |d| d.initial_name = "#{title} #{timestamp}.png" }
        dialog.save(window, nil) do |_dialog, result|
          begin
            gfile = dialog.save_finish(result)
            gfile.replace_contents(
              texture.save_to_png_bytes.to_s,
              nil,
              false,
              :replace_destination,
              nil,
            )
            show_screenshot_toast(gfile)
          rescue StandardError
            nil
          end
        end
      end

      def show_screenshot_toast(gfile)
        toast = Adwaita::Toast.new(Translations.translate("Screenshot captured"))
        toast.priority = :high
        toast.button_label = Translations.translate("Show in Files")
        toast.signal_connect("button-clicked") { Gtk::FileLauncher.new(gfile).open_containing_folder(window, nil) }
        toast_overlay.add_toast(toast)
      end

      def show_in_files
        uri = play.uri
        if uri
          Gtk::FileLauncher.new(Gio::File.new_for_uri(uri)).open_containing_folder(window, nil)
        end
      end

      def open_video
        open_video_dialog.open(window, nil) do |dialog, result|
          begin
            gfile = dialog.open_finish(result)
            if gfile
              play_video(gfile)
            end
          rescue StandardError
            nil
          end
        end
      end

      def open_choose_subtitles
        choose_subtitles_dialog.initial_folder = @playing_gfile&.parent
        choose_subtitles_dialog.open(window, nil) do |dialog, result|
          begin
            gfile = dialog.open_finish(result)
            if gfile
              play.subtitle_uri = gfile.uri
              select_subtitles(0)
            end
          rescue StandardError
            nil
          end
        end
      end
  end
end
