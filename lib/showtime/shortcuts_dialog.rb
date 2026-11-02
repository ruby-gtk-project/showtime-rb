# frozen_string_literal: true

require "adwaita"
require_relative "translations"

module Showtime
  # ShortcutsDialog is the port of upstream's showtime/gtk/shortcuts-dialog.blp:
  # an Adw.ShortcutsDialog with four sections — General, Volume, View and
  # Playback — in that order, with the same items in the same order.
  #
  # Most items name an action instead of an accelerator, so the accelerator
  # shown is whatever the application has bound to it; two name an accelerator
  # directly, because no action carries them (Shift+F10 opens the video options
  # popover through a ShortcutController, and Escape leaves fullscreen through
  # a CallbackAction).
  class ShortcutsDialog < Adwaita::ShortcutsDialog
    SECTIONS = {
      "General"  => [
        ["Show Shortcuts", { action: "app.shortcuts" }],
        ["Open Video", { action: "win.open-video" }],
        ["Video Options", { accelerator: "<shift>F10" }],
        ["Take Screenshot", { action: "win.screenshot" }],
        ["New Window", { action: "app.new-window" }],
        ["Close Window", { action: "win.close-window" }],
        ["Quit", { action: "app.quit" }],
      ],
      "Volume"   => [
        ["Increase Volume", { action: "win.increase-volume" }],
        ["Decrease Volume", { action: "win.decrease-volume" }],
        ["Mute/Unmute", { action: "win.toggle-mute" }],
      ],
      "View"     => [
        ["Toggle Fullscreen", { action: "win.toggle-fullscreen" }],
        ["Exit Fullscreen", { accelerator: "Escape" }],
      ],
      "Playback" => [
        ["Play/Pause", { action: "win.toggle-playback" }],
        ["Go Back 10 Seconds", { action: "win.backwards" }],
        ["Go Forward 10 Seconds", { action: "win.forwards" }],
      ],
    }.freeze

    def build
      tap do |dialog|
        SECTIONS.each do |title, items|
          dialog.add(section(title, items))
        end
      end
    end

    private

      def section(title, items)
        Adwaita::ShortcutsSection.new.tap do |section|
          section.title = Translations.translate(title)
          items.each { |item_title, binding| section.add(item(item_title, binding)) }
        end
      end

      # Positional, not keyword, arguments: a no-argument `new` fails even
      # though the signature it advertises reads like keywords. An item bound
      # to an action passes no accelerator and names the action instead, which
      # is what makes the dialog show the accelerator the app actually bound.
      def item(title, binding)
        Adwaita::ShortcutsItem.new(Translations.translate(title), binding[:accelerator].to_s).tap do |item|
          if binding[:action]
            item.action_name = binding[:action]
          end
        end
      end
  end
end
