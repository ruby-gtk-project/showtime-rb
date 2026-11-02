# frozen_string_literal: true

require "adwaita"
require_relative "translations"

module Showtime
  # SoundOptions is the port of upstream's showtime/widgets/sound_options.py
  # and its template, showtime/gtk/sound-options.blp: the volume button on the
  # video page's bottom overlay, and the popover it opens — a mute toggle and a
  # volume slider.
  #
  # Upstream declares `mute` and `volume` as GObject properties and
  # `schedule-volume-change` as a signal, so the window's Blueprint can bind
  # the first two and handle the third. Here `mute` and `volume` are accessors
  # and the two directions the bindings carried are callbacks: `on_mute` for
  # the bidirectional mute binding, `on_volume` for the signal, which upstream
  # emits on every adjustment change and the window turns into a volume change
  # on the pipeline.
  #
  # Upstream gives the two buttons accessibility labels ("Adjust Volume",
  # "Mute/Unmute") through the template's `accessibility` blocks. The Ruby
  # bindings do not implement `Gtk::Accessible#update_property` — it raises
  # NotImplementedError on the array-of-enum argument — so the same two strings
  # are set as tooltips, which a screen reader reads as the accessible
  # description and a pointer user can also see.
  class SoundOptions < Adwaita::Bin
    # The thresholds that pick the button's icon, from upstream's
    # `_get_volume_icon`.
    HIGH_VOLUME = 0.7
    MEDIUM_VOLUME = 0.3

    def initialize(on_mute: nil, on_volume: nil)
      super()
      @on_mute = on_mute
      @on_volume = on_volume
      @mute = true
    end

    def build
      tap do |bin|
        bin.child = menu_button

        menu_button.tap do |button|
          button.popover = popover

          popover.tap do |pop|
            pop.child = box

            box.tap do |content|
              content.append(mute_button)
              content.append(volume_scale)

              mute_button.tap do |toggle|
                # Only a change reports back, which is what upstream's
                # bidirectional binding amounts to: the window setting `mute`
                # moves the toggle without the move coming back as a fresh
                # user action.
                toggle.signal_connect("toggled") do
                  unless @mute == toggle.active?
                    self.mute = toggle.active?
                    @on_mute&.call(toggle.active?)
                  end
                end
              end

              adjustment.signal_connect("notify::value") do
                schedule_volume_change(adjustment.value)
              end
            end
          end
        end

        update_icon
      end
    end

    attr_reader :mute

    def mute=(mute)
      unless @mute == mute
        @mute = mute
        mute_button.active = mute
        update_icon
      end
    end

    def volume = adjustment.value

    # The one-way binding from the window's volume: moves the slider and
    # repicks the icon without reporting the change back as a user action.
    def volume=(volume)
      adjustment.value = volume
      update_icon
    end

    # Upstream's `_get_volume_icon(mute, volume)`.
    def volume_icon
      if mute
        "audio-volume-muted-symbolic"
      elsif volume > HIGH_VOLUME
        "audio-volume-high-symbolic"
      elsif volume > MEDIUM_VOLUME
        "audio-volume-medium-symbolic"
      else
        "audio-volume-low-symbolic"
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.valign = :center
        button.direction = :up
        button.tooltip_text = Translations.translate("Adjust Volume")
        button.add_css_class("circular")
        button.add_css_class("highlighted")
        button.add_css_class("overlaid")
      end
    end

    def popover
      @popover ||= Gtk::Popover.new.tap do |pop|
        pop.width_request = 250
      end
    end

    def box
      @box ||= Gtk::Box.new(:horizontal, 0).tap do |content|
        content.margin_top = 6
        content.margin_bottom = 6
        content.margin_start = 6
        content.margin_end = 6
      end
    end

    def mute_button
      @mute_button ||= Gtk::ToggleButton.new.tap do |toggle|
        toggle.icon_name = "audio-volume-muted-symbolic"
        toggle.active = true
        toggle.tooltip_text = Translations.translate("Mute/Unmute")
        toggle.add_css_class("circular")
        toggle.add_css_class("flat")
      end
    end

    def volume_scale
      @volume_scale ||= Gtk::Scale.new(:horizontal, adjustment).tap do |scale|
        scale.hexpand = true
        scale.draw_value = false
      end
    end

    def adjustment
      @adjustment ||= Gtk::Adjustment.new(
        1,
        0,
        1,
        0.2,
        0.2,
        0,
      )
    end

    private

      def schedule_volume_change(value)
        update_icon
        @on_volume&.call(value)
      end

      def update_icon
        menu_button.icon_name = volume_icon
      end
  end
end
