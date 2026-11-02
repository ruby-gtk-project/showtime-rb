# frozen_string_literal: true

require "adwaita"
require_relative "primary_menu"
require_relative "translations"

module Showtime
  # PlaceholderPage is the port of the `placeholder_page` branch of upstream's
  # showtime/gtk/window.blp, plus the two handlers in
  # showtime/widgets/window.py that fill it in — `_on_error` and
  # `_on_missing_plugin`.
  #
  # It is the stack page the window shows whenever there is no video on
  # screen, and it has three states of its own, held in a stack: the welcome
  # page with the Open button, the "Unable to Play Video" page, and the
  # "Missing Plugin" page. The last two get their description and their action
  # rows from the window when a stream fails, which is why `show_error` and
  # `show_missing_plugin` take the callbacks that upstream's two handlers wire
  # up inline.
  class PlaceholderPage
    def initialize(menu_model: PrimaryMenu.new.build)
      @menu_model = menu_model
    end

    def build
      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = window_handle

        header_bar.pack_end(primary_menu_button)

        window_handle.child = stack

        stack.tap do |pages|
          pages.add_child(open_status_page)
          pages.add_child(error_status_page)
          pages.add_child(missing_plugin_status_page)

          open_status_page.child = open_button
        end
      end
    end

    # The welcome state: the one the window opens on.
    def show_open
      stack.visible_child = open_status_page
    end

    # Upstream's `_on_error`: the error page, with a row to try the video
    # again and a row to copy the technical details of the failure.
    def show_error(on_try_again: nil, on_copy_details: nil)
      error_status_page.child = action_group(
        [Translations.translate("Try Again"), on_try_again, "suggested-action"],
        [Translations.translate("Copy Technical Details"), on_copy_details, nil],
      )
      stack.visible_child = error_status_page
    end

    # Upstream's `_on_missing_plugin`. `description` is the codec description
    # GStreamer reports; `on_install` is nil when plugin installation is not
    # supported on this system, and `on_try_anyway` is nil unless the plugins
    # are only partially missing, which are the two conditions that decide
    # which rows the page gets.
    def show_missing_plugin(description:, on_install: nil, on_try_anyway: nil)
      missing_plugin_status_page.tap do |page|
        page.description = missing_plugin_description(description, on_install)
        page.child = action_group(*missing_plugin_rows(on_install, on_try_anyway))
      end
      stack.visible_child = missing_plugin_status_page
    end

    # The two messages upstream sets on the missing-plugin page after an
    # install attempt comes back.
    def plugin_not_found
      missing_plugin_status_page.description =
        Translations.translate("No plugin available for this media type")
    end

    def plugin_install_failed
      missing_plugin_status_page.description =
        Translations.translate("Unable to install the required plugin")
    end

    def showing_missing_plugin? = stack.visible_child == missing_plugin_status_page

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def window_handle = @window_handle ||= Gtk::WindowHandle.new

    def stack = @stack ||= Gtk::Stack.new

    def primary_menu_button
      @primary_menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.primary = true
        button.icon_name = "open-menu-symbolic"
        button.tooltip_text = Translations.translate("Main Menu")
        button.menu_model = @menu_model
      end
    end

    def open_status_page
      @open_status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = "video-x-generic-symbolic"
        page.title = Translations.translate("Watch Videos")
        page.description = Translations.translate("Drag and drop videos here")
      end
    end

    def open_button
      @open_button ||= Gtk::Button.new.tap do |button|
        button.label = Translations.translate("Open…")
        button.halign = :center
        button.action_name = "win.open-video"
        button.add_css_class("pill")
        button.add_css_class("suggested-action")
      end
    end

    def error_status_page
      @error_status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = "dialog-error-symbolic"
        page.title = Translations.translate("Unable to Play Video")
      end
    end

    def missing_plugin_status_page
      @missing_plugin_status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = "puzzle-piece-symbolic"
        page.title = Translations.translate("Missing Plugin")
      end
    end

    private

      def missing_plugin_description(description, on_install)
        if on_install
          Translations.translate("“{}” codecs are required to play this video")
            .sub("{}", description.to_s)
        else
          Translations.translate("The “{}” codecs required to play this video could not be found")
            .sub("{}", description.to_s)
        end
      end

      def missing_plugin_rows(on_install, on_try_anyway)
        [
          on_install && [Translations.translate("Install Plugin"), on_install, "suggested-action"],
          on_try_anyway && [Translations.translate("Try Anyway"), on_try_anyway, nil],
        ].compact
      end

      # The `Adw.PreferencesGroup` upstream builds for both failure pages: one
      # narrow column of separate button rows, centred under the status page's
      # text.
      def action_group(*rows)
        Adwaita::PreferencesGroup.new.tap do |group|
          group.halign = :center
          group.width_request = 250
          group.separate_rows = true
          rows.each { |title, callback, css| group.add(button_row(title, callback, css)) }
        end
      end

      def button_row(title, callback, css)
        Adwaita::ButtonRow.new.tap do |row|
          row.title = title
          if css
            row.add_css_class(css)
          end
          row.signal_connect("activated") { callback&.call }
        end
      end
  end
end
