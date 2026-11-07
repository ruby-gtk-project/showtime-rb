# frozen_string_literal: true

require "gtk4"
require "adwaita"

require_relative "icons"
require_relative "mpris"
require_relative "settings"
require_relative "shortcuts_dialog"
require_relative "style"
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
  class Application
    APP_ID = "org.rubygtkproject.Showtime"

    def build
      app.tap do
        app.signal_connect("startup") do
          Adwaita::StyleManager.default.color_scheme = :prefer_dark
          Style.load
          Icons.load
          create_app_actions
        end

        app.signal_connect("activate") do
          window_controller.build
          window_controller.present
          mpris.build
        end
      end
    end

    def settings = @settings ||= Settings.new

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new(APP_ID, :default_flags)

    def window_controller = @window_controller ||= Window.new(app, settings: settings)

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
  end
end
