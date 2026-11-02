# frozen_string_literal: true

require "adwaita"
require_relative "translations"

module Showtime
  # Options is the port of upstream's showtime/widgets/options.py and its
  # template, showtime/gtk/options.blp: the settings button on the video page's
  # bottom overlay and the nested popover menu behind it — language and
  # subtitle submenus, a repeat item, inline rotate buttons, and a playback
  # speed toggle group.
  #
  # Two behaviours live in the Python rather than the template, and both are
  # ported here: `build_menus`, which fills the two submenus from the stream
  # list of the playing video, and `on_secondary_click_pressed`, which
  # reparents the popover onto the window so a right-click anywhere over the
  # video opens it at the pointer.
  #
  # Upstream declares `rate` as a GObject property and `rotate-left` /
  # `rotate-right` as signals so the window's Blueprint can bind and handle
  # them; here the rate is an accessor and the two rotations are callbacks.
  #
  # The button's accessibility label ("Playback Options") becomes a tooltip:
  # the Ruby bindings do not implement `Gtk::Accessible#update_property`, which
  # raises NotImplementedError on its array-of-enum argument.
  class Options < Adwaita::Bin
    # The toggles of the playback speed group, as `name => label`. The name is
    # the rate, which is what the group's active-name binding carries.
    RATES = {
      "0.5"  => "0.5×",
      "1.0"  => "1.0×",
      "1.25" => "1.25×",
      "1.5"  => "1.5×",
      "2.0"  => "2.0×",
    }.freeze

    # `GLib.MAXUINT16`, the index upstream uses for "no subtitles".
    NO_SUBTITLES = 65_535

    def initialize(on_rotate_left: nil, on_rotate_right: nil, on_rate: nil)
      super()
      @on_rotate_left = on_rotate_left
      @on_rotate_right = on_rotate_right
      @on_rate = on_rate
      # Upstream's `menus_building` counter: the window asks for a rebuild on
      # every media-info change, and a video that reports many of them in a row
      # should still only rebuild the menu once.
      @menus_building = 0
    end

    def build
      tap do |bin|
        bin.child = menu_button

        menu_button.tap do |button|
          button.popover = popover
          button.add_controller(shortcut_controller)

          popover.tap do |pop|
            pop.menu_model = menu
            pop.add_child(rotate_left_button, "rotate-left")
            pop.add_child(rotate_right_button, "rotate-right")
            pop.add_child(speed_box, "speed")
          end

          rotate_left_button.signal_connect("clicked") { @on_rotate_left&.call }
          rotate_right_button.signal_connect("clicked") { @on_rotate_right&.call }

          speed_box.tap do |box|
            box.append(speed_label)
            box.append(speed_group)

            speed_group.signal_connect("notify::active-name") do
              self.rate = speed_group.active_name
            end
          end
        end
      end
    end

    def rate = speed_group.active_name

    # Upstream's rate setter: the window applies the new rate, and the popover
    # closes so the video is visible again.
    def rate=(rate)
      unless speed_group.active_name == rate.to_s
        speed_group.active_name = rate.to_s
      end
      popover.popdown
      @on_rate&.call(rate.to_s)
    end

    # Registers that another media-info change has asked for a rebuild. The
    # window calls this, then schedules `build_menus` 500ms later.
    def schedule_menus = @menus_building += 1

    # Fills the language and subtitle submenus from the playing video's
    # streams.
    #
    # Each stream is a hash of the three things upstream reads off a
    # `GstPlayStreamInfo`: `:language`, `:title` and, for audio, `:channels`.
    def build_menus(audio_streams: [], subtitle_streams: [])
      @menus_building -= 1
      # Don't try to rebuild the menu multiple times when the media info has
      # many changes.
      if @menus_building <= 1
        rebuild_menus(audio_streams, subtitle_streams)
      end
    end

    # Parents the popover on `window` and pops it up at (x, y), so a
    # right-click over the video opens the options there; it goes back on the
    # menu button when it closes.
    def on_secondary_click_pressed(window, gesture, x, y)
      gesture.state = :claimed

      menu_button.popover = nil
      popover.tap do |pop|
        pop.set_parent(window)
        pop.has_arrow = false
        pop.halign = :start
        pop.pointing_to = Gdk::Rectangle.new(
          x,
          y,
          0,
          0,
        )
        pop.popup
      end

      restore_popover_when_closed
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.halign = :end
        button.valign = :center
        button.icon_name = "settings-symbolic"
        button.direction = :up
        button.tooltip_text = Translations.translate("Playback Options")
        button.add_css_class("circular")
        button.add_css_class("highlighted")
        button.add_css_class("overlaid")
      end
    end

    def popover
      @popover ||= Gtk::PopoverMenu.new.tap do |pop|
        pop.flags = :nested
      end
    end

    # The menu model: the two submenus, the repeat item, the inline rotate
    # section and the speed section, in upstream's order.
    def menu
      @menu ||= Gio::Menu.new.tap do |model|
        model.append_section(nil, submenus_section)
        model.append_section(nil, repeat_section)
        model.append_item(rotate_section_item)
        model.append_item(speed_section_item)
      end
    end

    def language_menu = @language_menu ||= Gio::Menu.new
    def subtitles_menu = @subtitles_menu ||= Gio::Menu.new

    def rotate_left_button
      @rotate_left_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "object-rotate-left-symbolic"
        button.tooltip_text = Translations.translate("Rotate Left")
        button.add_css_class("flat")
      end
    end

    def rotate_right_button
      @rotate_right_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "object-rotate-right-symbolic"
        button.tooltip_text = Translations.translate("Rotate Right")
        button.add_css_class("flat")
      end
    end

    def speed_box
      @speed_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
        box.margin_top = 9
        box.margin_bottom = 9
        box.margin_start = 9
        box.margin_end = 9
      end
    end

    def speed_label
      @speed_label ||= Gtk::Label.new(Translations.translate("Playback Speed")).tap do |label|
        label.halign = :start
        label.margin_start = 6
        label.add_css_class("heading")
      end
    end

    def speed_group
      @speed_group ||= Adwaita::ToggleGroup.new.tap do |group|
        group.homogeneous = true
        group.add_css_class("round")
        group.add_css_class("flat")
        RATES.each { |name, label| group.add(toggle(name, label)) }
      end
    end

    # `<shift>F10` opens the popover; the controller is managed, so the
    # shortcut works wherever the focus is inside the window.
    #
    # The trigger is built from the keyval and the modifier rather than parsed
    # from "<shift>F10": `Gtk::ShortcutTrigger.parse_string` is not bound in
    # Ruby, and `Gtk::KeyvalTrigger` is what the parser would have returned.
    def shortcut_controller
      @shortcut_controller ||= Gtk::ShortcutController.new.tap do |controller|
        controller.scope = :managed
        controller.add_shortcut(options_shortcut)
      end
    end

    # Positional, not keyword, arguments — even though the error a mismatched
    # `new` raises advertises the signature as "trigger: …, action: …".
    def options_shortcut
      @options_shortcut ||= Gtk::Shortcut.new(
        Gtk::KeyvalTrigger.new(Gdk::Keyval::KEY_F10, :shift_mask),
        Gtk::NamedAction.new("activate"),
      )
    end

    private

      def toggle(name, label)
        Adwaita::Toggle.new.tap do |toggle|
          toggle.name = name
          toggle.label = label
        end
      end

      def submenus_section
        Gio::Menu.new.tap do |model|
          model.append_submenu(Translations.translate("_Language"), language_menu)
          model.append_submenu(Translations.translate("_Subtitles"), subtitles_menu)
        end
      end

      def repeat_section
        Gio::Menu.new.tap do |model|
          model.append(Translations.translate("_Repeat"), "win.toggle-loop")
        end
      end

      # `display-hint: "inline-buttons"` turns the section into a row of
      # buttons under its label rather than a list of menu items.
      #
      # A section with attributes on it has to be built as a menu item with a
      # "section" link — `Gio::Menu#append_section` takes no attributes, and
      # `Gio::MenuItem.new_section` is not bound in Ruby.
      def rotate_section_item
        section_item(Translations.translate("Rotate"), rotate_section).tap do |item|
          item.set_attribute_value("display-hint", GLib::Variant.new("inline-buttons"))
        end
      end

      def section_item(label, model)
        Gio::MenuItem.new(label, nil).tap do |item|
          item.set_link("section", model)
        end
      end

      def rotate_section
        Gio::Menu.new.tap do |model|
          model.append_item(custom_item("rotate-left"))
          model.append_item(custom_item("rotate-right"))
        end
      end

      def speed_section_item
        section_item(nil, speed_section)
      end

      def speed_section
        Gio::Menu.new.tap do |model|
          model.append_item(custom_item("speed"))
        end
      end

      # `item { custom: "name"; }`: a slot the popover fills with the widget
      # added under that name.
      def custom_item(name)
        Gio::MenuItem.new(nil, nil).tap do |item|
          item.set_attribute_value("custom", GLib::Variant.new(name))
        end
      end

      def restore_popover_when_closed
        handler = nil
        handler = popover.signal_connect("closed") do
          popover.unparent
          popover.has_arrow = true
          popover.halign = :fill
          popover.pointing_to = nil
          menu_button.popover = popover
          popover.signal_handler_disconnect(handler)
        end
      end

      def rebuild_menus(audio_streams, subtitle_streams)
        language_menu.remove_all
        subtitles_menu.remove_all
        fill_language_menu(audio_streams)
        fill_subtitles_menu(subtitle_streams)
      end

      def fill_language_menu(audio_streams)
        audio_streams.each_with_index do |stream, index|
          language_menu.append(audio_label(stream), "win.select-language(uint16 #{index})")
        end

        if audio_streams.empty?
          # HACK: an action that does not exist is how upstream makes the item
          # insensitive.
          language_menu.append(Translations.translate("No Audio"), "nonexistent.action")
        end
      end

      def fill_subtitles_menu(subtitle_streams)
        subtitles_menu.append(
          Translations.translate("None"),
          "win.select-subtitles(uint16 #{NO_SUBTITLES})",
        )

        subtitle_streams.each_with_index do |stream, index|
          subtitles_menu.append(subtitle_label(stream), "win.select-subtitles(uint16 #{index})")
        end

        subtitles_menu.append(Translations.translate("Add Subtitle File…"), "win.choose-subtitles")
      end

      # The stream's language, or — for an audio stream that reports none —
      # its channel count, with the stream title appended when it says
      # something the language does not.
      def audio_label(stream)
        language = audio_language(stream)
        with_title(language, stream[:title])
      end

      def subtitle_label(stream)
        language = stream[:language].to_s
        if language.empty?
          with_title(Translations.translate("Undetermined Language"), stream[:title])
        else
          with_title(language, stream[:title])
        end
      end

      def audio_language(stream)
        language = stream[:language].to_s
        if !language.empty?
          language
        else
          undetermined(stream[:channels].to_i)
        end
      end

      def undetermined(channels)
        if channels.positive?
          # Translators: The variable is the number of channels in an audio
          # track
          format_channels(channels)
        else
          Translations.translate("Undetermined")
        end
      end

      def format_channels(channels)
        Translations.ngettext(
          "Undetermined, {} Channel",
          "Undetermined, {} Channels",
          channels,
        ).sub("{}", channels.to_s)
      end

      def with_title(language, title)
        if title.to_s.empty? || title.to_s == language
          language
        else
          "#{language} - #{title}"
        end
      end
  end
end
