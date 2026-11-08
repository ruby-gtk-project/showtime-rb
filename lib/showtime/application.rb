# frozen_string_literal: true

require "gtk4"
require "adwaita"

require_relative "icons"
require_relative "log"
require_relative "mpris"
require_relative "rb/version"
require_relative "settings"
require_relative "shortcuts_dialog"
require_relative "style"
require_relative "translations"
require_relative "window"

module Showtime
  # The port's application, ported from showtime/main.py.
  #
  # Upstream's `Application` sets the colour scheme, creates the `app.new-window`
  # and `app.quit` actions and opens a `Window` per video; the `app.shortcuts`
  # action comes free with Adw.Application, which picks the shortcuts dialog up
  # out of the GResource bundle. This port uses Gtk::Application — Adwaita's is
  # broken in the Ruby bindings — so the shortcuts action is created here, and
  # the dialog is the ported ShortcutsDialog.
  #
  # The window itself — the placeholder page, the video page, the GStreamer
  # pipeline and every window-level action — is the ported `Window` class;
  # this class owns only what upstream's `Application` owns: the app-level
  # actions, the colour scheme, and the one window `new-window` opens.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  #
  # Upstream's command-line handling (`do_handle_local_options`, `do_open`,
  # the `--new-window`/`-n` option) is ported here too. `Gio::Application`'s
  # `HANDLES_OPEN` flag is what routes `[VIDEO FILES]` arguments to the
  # `open` signal instead of `activate`; `handle-local-options` is what makes
  # a second, file-less invocation warn and exit instead of stealing focus
  # from the window a `--new-window`-less `showtime` already opened.
  class Application
    APP_ID = "org.rubygtkproject.Showtime"

    def build
      app.tap do
        app.signal_connect("startup") do
          Log.debug("Starting #{APP_ID} v#{Rb::VERSION}")
          if defined?(Gst) && Gst.respond_to?(:version)
            Log.debug("GStreamer version: #{Gst.version.join(".")}")
          end
          Adwaita::StyleManager.default.color_scheme = :prefer_dark
          Style.load
          Icons.load
          create_app_actions
        end

        app.signal_connect("handle-local-options") do |_app, options|
          handle_local_options(options)
        end

        app.signal_connect("activate") do
          activate(nil)
        end

        app.signal_connect("open") do |_app, files, _n_files, _hint|
          files.each { |file| activate(file) }
        end
      end
    end

    def settings = @settings ||= Settings.new

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app
      @app ||= Gtk::Application.new(APP_ID, :handles_open).tap do |application|
        application.add_main_option(
          "new-window", "n", GLib::OptionFlags::NONE, GLib::OptionArg::NONE,
          Translations.translate("Open the app with a new window"), nil,
        )
        application.set_option_context_parameter_string("[VIDEO FILES]")
      end
    end

    # The most recently built `Window` — what every delegate method below
    # reaches through. Not memoized with `||=`: `activate` (upstream's
    # `do_activate`) assigns a brand-new `Window` to `@window_controller` on
    # every call, the same as upstream's unconditional `Window.new`, so
    # `new-window`, each CLI file argument, and a retried file each get a
    # real second `Gtk::Window` rather than replaying the one window this
    # port used to keep for the app's whole lifetime.
    def window_controller = @window_controller

    # The MPRIS2 D-Bus surface, ported from showtime/mpris.py. Built once the
    # window exists, since every property and method it answers reads the
    # window's playback state.
    def mpris = @mpris ||= Mpris.new(self)

    # Delegated so existing callers (and this app's own tests) can keep
    # reaching the window and what it owns through the application, the way
    # they could before `Window` existed. Also what Mpris talks to — it
    # knows nothing about `Window` directly.
    def window = window_controller.window
    def placeholder_page = window_controller.placeholder_page
    def primary_menu = window_controller.primary_menu
    def about_dialog = window_controller.about_dialog
    def play = window_controller.play
    def paused? = window_controller.paused?
    def stopped? = window_controller.stopped?
    def pause = window_controller.pause
    def unpause = window_controller.unpause
    def rate = window_controller.video_page.options.rate
    def rate=(value)
      window_controller.video_page.options.rate = value
    end

    def shortcuts_dialog = @shortcuts_dialog ||= ShortcutsDialog.new.build

    private

      def create_app_actions
        add_action(app, "quit", %w[<primary>q]) { app.quit }
        add_action(app, "new-window", %w[<primary>n]) { app.activate }
        add_action(app, "shortcuts") { shortcuts_dialog.present(window) }
      end

      # Upstream's `_create_action`, carried over from when the window's
      # actions were also created here; only the app-level ones are left.
      def add_action(map, name, accelerators = [], &callback)
        Gio::SimpleAction.new(name, nil).tap do |action|
          action.signal_connect("activate") { callback.call }
          map.add_action(action)
          unless accelerators.empty?
            app.set_accels_for_action("app.#{name}", accelerators)
          end
        end
      end

      # Upstream's `do_activate`/`do_open`: construct a new window, build it,
      # play the given file (if any — a plain `activate` with no command-line
      # arguments passes `nil`), present, and bring MPRIS up. A fresh `Window`
      # on every call is what makes `new-window`, a second CLI file argument,
      # and `Window#try_again`'s retry each open a real second `Gtk::Window`,
      # matching upstream's own unconditional `Window.new` in `do_activate`.
      def activate(gfile)
        @window_controller = Window.new(app, settings: settings, on_retry: ->(retry_gfile) { retry_in_new_window(retry_gfile) })
        window_controller.build
        if gfile
          window_controller.play_video_file(gfile)
        end
        window_controller.present
        mpris.build
      end

      # Upstream's `_try_again`: open the file in a brand-new window, then
      # close the window that failed, once the new one is up.
      def retry_in_new_window(gfile)
        failed_controller = window_controller
        activate(gfile)
        failed_controller.window.close
      end

      # Upstream's `do_handle_local_options`: `register` so `remote?` is
      # answerable before the primary instance has necessarily started, then
      # either hand off to the already-running instance (unless the person
      # explicitly asked for `--new-window`, in which case `-1` lets the
      # default remote-activation machinery continue) or, for the first
      # instance, `-1` to continue into `do_startup`/`activate`/`open`.
      def handle_local_options(options)
        app.register
        if app.remote?
          if options.contains?("new-window")
            -1
          else
            Log.warn(
              "Showtime is already running. " \
              "To open a new window, run the app with --new-window.",
            )
            0
          end
        else
          -1
        end
      end
  end
end
