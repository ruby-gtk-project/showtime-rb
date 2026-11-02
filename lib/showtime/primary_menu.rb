# frozen_string_literal: true

require "gtk4"
require_relative "translations"

module Showtime
  # PrimaryMenu is the port of the `menu primary_menu` block at the top of
  # upstream's showtime/gtk/window.blp — the model behind both of the window's
  # primary menu buttons (the one on the placeholder page's header bar, and the
  # overlaid one on the video page).
  #
  # Four sections, in upstream's order, with upstream's mnemonics. "Show in
  # Files" and "Take Screenshot" carry `hidden-when: "action-disabled"`,
  # because the window only enables them once a video is playing — so the two
  # items are absent from the menu rather than greyed out in it.
  class PrimaryMenu
    SECTIONS = [
      [
        ["_New Window", "app.new-window"],
        ["_Open…", "win.open-video"],
      ],
      [
        ["Show in _Files", "win.show-in-files", :hide_when_disabled],
      ],
      [
        ["Take _Screenshot", "win.screenshot", :hide_when_disabled],
      ],
      [
        ["_Keyboard Shortcuts", "app.shortcuts"],
        ["_About Video Player", "win.about"],
      ],
    ].freeze

    HIDDEN_WHEN = "hidden-when"
    ACTION_DISABLED = "action-disabled"

    def build
      menu.tap do |model|
        SECTIONS.each do |items|
          model.append_section(nil, section(items))
        end
      end
    end

    def menu = @menu ||= Gio::Menu.new

    private

      def section(items)
        Gio::Menu.new.tap do |model|
          items.each { |label, action, hide| model.append_item(item(label, action, hide)) }
        end
      end

      def item(label, action, hide)
        Gio::MenuItem.new(Translations.translate(label), action).tap do |menu_item|
          if hide
            menu_item.set_attribute_value(HIDDEN_WHEN, GLib::Variant.new(ACTION_DISABLED))
          end
        end
      end
  end
end
