# frozen_string_literal: true

require "gtk4"
require "adwaita"

require_relative "about_dialog"
require_relative "icons"
require_relative "placeholder_page"
require_relative "primary_menu"
require_relative "settings"
require_relative "shortcuts_dialog"
require_relative "style"
require_relative "translations"
require_relative "utils"

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
  # The window is the placeholder page under a toast overlay, which is what
  # upstream shows whenever no video is on screen. The video page, and the
  # window class that switches between the two, are the next things to port;
  # until then this is the whole window, and the actions that only make sense
  # with a video playing are not created rather than being created as no-ops —
  # which is why "Show in Files" and "Take Screenshot" are absent from the
  # menu, since the menu hides them when their action is missing.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    APP_ID = "org.rubygtkproject.Showtime"

    # From upstream's window.blp template: a 16:9 aspect ratio at the minimum
    # height, and 360px wide, which is what the metainfo file requires.
    DEFAULT_WIDTH = 800
    DEFAULT_HEIGHT = 500
    MIN_WIDTH = 360
    MIN_HEIGHT = 202

    def build
      app.tap do
        app.signal_connect("startup") do
          Adwaita::StyleManager.default.color_scheme = :prefer_dark
          Style.load
          Icons.load
          create_app_actions
        end

        app.signal_connect("activate") do
          create_window_actions

          window.tap do |win|
            win.content = toast_overlay
          end

          toast_overlay.tap do |overlay|
            overlay.child = stack
          end

          stack.tap do |pages|
            pages.add_child(placeholder_page.build)
          end

          placeholder_page.show_open

          window.present
        end
      end
    end

    def settings = @settings ||= Settings.new

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new(APP_ID, :default_flags)

    def window
      @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
        win.title = Translations.translate("Video Player")
        win.set_default_size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
        win.width_request = MIN_WIDTH
        win.height_request = MIN_HEIGHT
        win.maximized = settings.get_boolean("is-maximized")
        win.signal_connect("notify::maximized") do
          settings.set_boolean("is-maximized", win.maximized?)
        end
      end
    end

    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
    def stack = @stack ||= Gtk::Stack.new

    def primary_menu = @primary_menu ||= PrimaryMenu.new.build

    def placeholder_page = @placeholder_page ||= PlaceholderPage.new(menu_model: primary_menu)

    def shortcuts_dialog = @shortcuts_dialog ||= ShortcutsDialog.new.build

    def about_dialog = @about_dialog ||= AboutDialog.new.build

    private

      def create_app_actions
        add_action(app, "quit", %w[<primary>q]) { app.quit }
        add_action(app, "new-window", %w[<primary>n]) { app.activate }
        add_action(app, "shortcuts") { shortcuts_dialog.present(window) }
      end

      def create_window_actions
        add_action(window, "close-window", %w[<primary>w q]) { window.close }
        add_action(window, "about") { about_dialog.present(window) }
        add_action(window, "toggle-fullscreen", %w[F11 f]) do
          window.fullscreened = !window.fullscreened?
        end
      end

      # Upstream's `_create_action`, which both the application and the window
      # have a copy of: a simple action, plus the accelerators bound to it on
      # the application.
      def add_action(map, name, accelerators = [], &callback)
        Gio::SimpleAction.new(name, nil).tap do |action|
          action.signal_connect("activate") { callback.call }
          map.add_action(action)
          unless accelerators.empty?
            app.set_accels_for_action("#{prefix_for(map)}.#{name}", accelerators)
          end
        end
      end

      def prefix_for(map)
        if map == app
          "app"
        else
          "win"
        end
      end
  end
end
