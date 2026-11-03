# frozen_string_literal: true

require "adwaita"
require_relative "options"
require_relative "primary_menu"
require_relative "restore_overlay"
require_relative "sound_options"
require_relative "translations"

module Showtime
  # VideoPage is the port of the `video_page` branch of upstream's
  # showtime/gtk/window.blp: the player itself and everything laid over it.
  #
  # A `Gtk.WindowHandle` holding a `Gtk.Overlay`. The overlay's child is the
  # `Gtk.GraphicsOffload` wrapping the `Gtk.Picture` that the GStreamer sink
  # paints into; on top of it sit four overlays — the toolbar clamp with the
  # transport controls and the seek bar, the resume/restart prompt, and the two
  # window-handle corners carrying the window controls, the fullscreen button,
  # the buffering spinner and the primary menu button.
  #
  # Everything the page shows is driven from outside: the window owns the
  # pipeline and pushes the title, position, duration, paused and fullscreened
  # states in. Everything the page does goes back out through the callbacks the
  # constructor takes, which are the Blueprint template's `=>` handlers and its
  # property bindings — `icon-name: bind $_get_play_icon(template.paused)` and
  # `icon-name: bind $_get_fullscreen_icon(template.fullscreened)` become the
  # `paused=` and `fullscreened=` setters, since the Ruby bindings have no
  # equivalent of a closure binding.
  #
  # The accessible labels upstream sets in its `accessibility` blocks are set
  # as tooltips, the choice the rest of this port already makes:
  # `Gtk::Accessible#update_property` raises NotImplementedError on its
  # array-of-enum argument in the Ruby bindings.
  class VideoPage
    # Upstream's `SCALE_MULT`: the seek scale runs 0–500 rather than 0–1 so
    # that dragging it is not rough.
    SCALE_MULT = 500

    # The widgets that fade together on pointer motion and fade out again when
    # the pointer has been still for two seconds. Upstream's `overlay_widgets`.
    def overlay_widgets
      @overlay_widgets ||= [
        toolbar_clamp,
        header_handle_start,
        header_handle_end,
      ]
    end

    # One motion controller per widget that should keep the overlays up while
    # the pointer is over it. Upstream's `overlay_motions`.
    def overlay_motions
      @overlay_motions ||= hover_widgets.map do |widget|
        Gtk::EventControllerMotion.new.tap { |motion| widget.add_controller(motion) }
      end
    end

    # The three menu buttons whose open popovers also keep the overlays up.
    def overlay_menu_buttons
      @overlay_menu_buttons ||= [
        video_primary_menu_button,
        options.menu_button,
        sound_options.menu_button,
      ]
    end

    def initialize(
      menu_model: PrimaryMenu.new.build,
      on_motion: nil,
      on_seek: nil,
      on_primary_click: nil,
      on_secondary_click: nil,
      on_cycle_end_timestamp: nil,
      on_resume: nil,
      on_restart: nil,
      on_rotate_left: nil,
      on_rotate_right: nil,
      on_rate: nil,
      on_mute: nil,
      on_volume: nil
    )
      @menu_model = menu_model
      @on_motion = on_motion
      @on_seek = on_seek
      @on_primary_click = on_primary_click
      @on_secondary_click = on_secondary_click
      @on_cycle_end_timestamp = on_cycle_end_timestamp
      @on_resume = on_resume
      @on_restart = on_restart
      @on_rotate_left = on_rotate_left
      @on_rotate_right = on_rotate_right
      @on_rate = on_rate
      @on_mute = on_mute
      @on_volume = on_volume
    end

    def build
      window_handle.tap do |page|
        page.child = overlay

        overlay.tap do |over|
          over.child = graphics_offload
          over.add_overlay(toolbar_clamp)
          over.add_overlay(restore_overlay.build)
          over.add_overlay(header_handle_start)
          over.add_overlay(header_handle_end)
          over.add_controller(primary_click)
          over.add_controller(secondary_click)
          over.add_controller(overlay_motion)

          graphics_offload.child = picture

          toolbar_clamp.child = toolbar_box

          toolbar_box.tap do |box|
            box.append(controls_box)
            box.append(bottom_overlay_box)

            controls_box.tap do |controls|
              controls.append(backwards_button)
              controls.append(play_button)
              controls.append(forwards_button)
            end

            bottom_overlay_box.tap do |bottom|
              bottom.append(title_box)
              bottom.append(seek_scale)
              bottom.append(timestamp_box)

              title_box.tap do |titles|
                titles.append(title_label)
                titles.append(sound_options.build)
                titles.append(options.build)
              end

              timestamp_box.tap do |stamps|
                stamps.append(position_label)
                stamps.append(end_timestamp_button)
              end
            end
          end

          header_handle_start.tap do |handle|
            handle.child = header_start

            header_start.tap do |box|
              box.append(window_controls_start)
              box.append(fullscreen_button)
            end
          end

          header_handle_end.tap do |handle|
            handle.child = header_end

            header_end.tap do |box|
              box.append(spinner)
              box.append(video_primary_menu_button)
              box.append(window_controls_end)
            end
          end

          end_timestamp_button.signal_connect("clicked") { @on_cycle_end_timestamp&.call }

          seek_scale.signal_connect("change-value") do |_scale, _scroll, value|
            @on_seek&.call(value)
            false
          end

          overlay_motion.signal_connect("motion") do |_controller, x, y|
            @on_motion&.call(x, y)
          end

          primary_click.signal_connect("released") do |gesture, presses, _x, _y|
            @on_primary_click&.call(gesture, presses)
          end

          secondary_click.signal_connect("pressed") do |gesture, _presses, x, y|
            @on_secondary_click&.call(gesture, x, y)
          end

          # `visible: bind window_controls_start.empty inverted` — a decoration
          # layout with nothing on that side leaves an empty widget taking up
          # space, so each set of controls hides itself.
          [window_controls_start, window_controls_end].each do |controls|
            controls.signal_connect("notify::empty") do
              controls.visible = !controls.empty?
            end
            controls.visible = !controls.empty?
          end

          # `vexpand: bind controls_box.can-target inverted` — while the
          # transport controls are hidden the bottom strip takes the space they
          # would have had, so the seek bar stays at the bottom edge.
          controls_box.signal_connect("notify::can-target") do
            title_box.vexpand = !controls_box.can_target?
          end

          overlay_motions
          force_left_to_right
        end
      end
    end

    # The stack page's root widget, which the window adds to its stack.
    def root = window_handle

    # `template.paused`: the play button's icon and its label.
    def paused=(paused)
      play_button.icon_name = play_icon(paused)
      play_button.tooltip_text = play_label(paused)
    end

    # `template.fullscreened`: the corner button's icon.
    def fullscreened=(fullscreened)
      fullscreen_button.icon_name = fullscreen_icon(fullscreened)
    end

    def title=(title)
      title_label.label = title.to_s
    end

    def position=(position)
      position_label.label = Utils.nanoseconds_to_timestamp(position)
    end

    def end_timestamp=(timestamp)
      end_timestamp_button.label = timestamp
    end

    # The seek scale's position, as a fraction of the duration scaled by
    # `SCALE_MULT`. A stream whose duration is not known yet divides by zero
    # in upstream, so the zero case leaves the slider where it is.
    def progress=(fraction)
      seek_scale.value = fraction * SCALE_MULT
    end

    def play_icon(paused)
      if paused
        "media-playback-start-symbolic"
      else
        "media-playback-pause-symbolic"
      end
    end

    def fullscreen_icon(fullscreened)
      if fullscreened
        "view-restore-symbolic"
      else
        "view-fullscreen-symbolic"
      end
    end

    def pointer_over_video? = overlay_motion.contains_pointer?

    def window_handle
      @window_handle ||= Gtk::WindowHandle.new.tap do |handle|
        handle.name = "video-page"
      end
    end

    def overlay = @overlay ||= Gtk::Overlay.new

    def graphics_offload
      @graphics_offload ||= Gtk::GraphicsOffload.new(picture).tap do |offload|
        offload.black_background = true
      end
    end

    def picture = @picture ||= Gtk::Picture.new

    # The gradient scrim behind the controls: the `shade` class is what makes
    # white text readable over a bright frame.
    def toolbar_clamp
      @toolbar_clamp ||= Adwaita::Clamp.new.tap do |clamp|
        clamp.maximum_size = 1920
        clamp.tightening_threshold = 1920
        clamp.add_css_class("shade")
      end
    end

    def toolbar_box
      @toolbar_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.margin_start = 12
        box.margin_end = 12
        box.margin_bottom = 12
      end
    end

    def controls_box
      @controls_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.hexpand = true
        box.vexpand = true
        box.halign = :center
        box.valign = :center
        box.margin_top = 48
      end
    end

    def backwards_button
      @backwards_button ||= overlaid_button("backwards-button").tap do |button|
        button.icon_name = "skip-backwards-10-symbolic"
        button.action_name = "win.backwards"
        button.tooltip_text = Translations.translate("Go Back 10 Seconds")
      end
    end

    def play_button
      @play_button ||= overlaid_button("play-button").tap do |button|
        button.icon_name = "media-playback-start-symbolic"
        button.action_name = "win.toggle-playback"
        button.tooltip_text = Translations.translate("Play")
        button.margin_start = 12
        button.margin_end = 12
      end
    end

    def forwards_button
      @forwards_button ||= overlaid_button("forwards-button").tap do |button|
        button.icon_name = "skip-forward-10-symbolic"
        button.action_name = "win.forwards"
        button.tooltip_text = Translations.translate("Go Forward 10 Seconds")
      end
    end

    def bottom_overlay_box = @bottom_overlay_box ||= Gtk::Box.new(:vertical, 0)

    # The strip with the title and the two popover buttons. Upstream gives it
    # the widget *name* `bottom-overlay-box`, which style.css keys its padding
    # off; the vertical box above it is the template's `bottom_overlay_box`
    # object, which carries no name at all.
    def title_box
      @title_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.name = "bottom-overlay-box"
        box.valign = :end
      end
    end

    def title_label
      @title_label ||= Gtk::Label.new.tap do |label|
        label.hexpand = true
        label.halign = :start
        label.margin_start = 12
        label.margin_end = 12
        label.ellipsize = :end
        label.add_css_class("title-4")
        label.add_css_class("overlaid")
      end
    end

    def sound_options
      @sound_options ||= SoundOptions.new(
        on_mute: @on_mute,
        on_volume: @on_volume,
      )
    end

    def options
      @options ||= Options.new(
        on_rotate_left: @on_rotate_left,
        on_rotate_right: @on_rotate_right,
        on_rate: @on_rate,
      )
    end

    def seek_scale
      @seek_scale ||= Gtk::Scale.new(:horizontal, seek_adjustment).tap do |scale|
        scale.hexpand = true
        scale.valign = :end
        scale.draw_value = false
        scale.add_css_class("highlighted")
        scale.add_css_class("overlaid")
      end
    end

    def seek_adjustment
      @seek_adjustment ||= Gtk::Adjustment.new(
        0,
        0,
        SCALE_MULT,
        1,
        10,
        0,
      )
    end

    def timestamp_box
      @timestamp_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.valign = :end
        box.margin_bottom = 3
      end
    end

    def position_label
      @position_label ||= Gtk::Label.new("0:00").tap do |label|
        label.hexpand = true
        label.halign = :start
        label.margin_start = 12
        label.margin_end = 3
        label.add_css_class("caption-heading")
        label.add_css_class("numeric")
        label.add_css_class("timestamp")
        label.add_css_class("overlaid")
      end
    end

    def end_timestamp_button
      @end_timestamp_button ||= Gtk::Button.new.tap do |button|
        button.name = "end-timestamp-button"
        button.label = "0:00"
        button.hexpand = true
        button.halign = :end
        button.margin_start = 3
        button.tooltip_text = Translations.translate("Toggle Duration/Remaining")
        button.add_css_class("caption-heading")
        button.add_css_class("numeric")
        button.add_css_class("timestamp")
        button.add_css_class("highlighted")
        button.add_css_class("overlaid")
      end
    end

    def restore_overlay
      @restore_overlay ||= RestoreOverlay.new(
        on_resume: @on_resume,
        on_restart: @on_restart,
      )
    end

    def header_handle_start
      @header_handle_start ||= Gtk::WindowHandle.new.tap do |handle|
        handle.valign = :start
        handle.halign = :start
      end
    end

    def header_handle_end
      @header_handle_end ||= Gtk::WindowHandle.new.tap do |handle|
        handle.valign = :start
        handle.halign = :end
      end
    end

    def header_start
      @header_start ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.margin_top = 6
        box.margin_bottom = 3
        box.margin_start = 6
        box.margin_end = 3
      end
    end

    def header_end
      @header_end ||= Gtk::Box.new(:horizontal, 6).tap do |box|
        box.margin_top = 6
        box.margin_bottom = 3
        box.margin_start = 3
        box.margin_end = 6
      end
    end

    # Positional argument: `Gtk::WindowControls.new` with no argument raises,
    # and the error names the signature as `initialize(side: …)` even though a
    # keyword argument is what fails.
    def window_controls_start
      @window_controls_start ||= Gtk::WindowControls.new(:start).tap do |controls|
        controls.halign = :start
        controls.valign = :start
        controls.add_css_class("overlaid")
      end
    end

    def window_controls_end
      @window_controls_end ||= Gtk::WindowControls.new(:end).tap do |controls|
        controls.halign = :end
        controls.valign = :start
        controls.add_css_class("overlaid")
      end
    end

    def fullscreen_button
      @fullscreen_button ||= Gtk::Button.new.tap do |button|
        button.hexpand = true
        button.margin_bottom = 24
        button.margin_end = 24
        button.icon_name = "view-fullscreen-symbolic"
        button.tooltip_text = Translations.translate("Toggle Fullscreen")
        button.action_name = "win.toggle-fullscreen"
        button.add_css_class("circular")
        button.add_css_class("highlighted")
        button.add_css_class("overlaid")
      end
    end

    # Faded in only once buffering has lasted a second, which is why it starts
    # transparent rather than hidden.
    def spinner
      @spinner ||= Adwaita::Spinner.new.tap do |spin|
        spin.width_request = 18
        spin.height_request = 18
        spin.margin_end = 9
        spin.opacity = 0
        spin.can_target = false
        spin.add_css_class("overlaid")
      end
    end

    def video_primary_menu_button
      @video_primary_menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.hexpand = true
        button.primary = true
        button.icon_name = "open-menu-symbolic"
        button.tooltip_text = Translations.translate("Main Menu")
        button.menu_model = @menu_model
        button.add_css_class("circular")
        button.add_css_class("highlighted")
        button.add_css_class("overlaid")
      end
    end

    def primary_click
      @primary_click ||= Gtk::GestureClick.new.tap do |gesture|
        gesture.button = 1
      end
    end

    def secondary_click
      @secondary_click ||= Gtk::GestureClick.new.tap do |gesture|
        gesture.button = 3
      end
    end

    def overlay_motion = @overlay_motion ||= Gtk::EventControllerMotion.new

    private

      def hover_widgets
        [
          controls_box,
          bottom_overlay_box,
          header_start,
          header_end,
          restore_overlay.restore_box,
        ]
      end

      # Upstream forces the transport controls and the progress bar
      # left-to-right whatever the interface direction is: a seek bar that
      # ran right-to-left would not match the video it scrubs.
      def force_left_to_right
        [
          controls_box,
          seek_scale,
          timestamp_box,
          position_label,
          end_timestamp_button,
        ].each { |widget| widget.direction = :ltr }
      end

      def play_label(paused)
        if paused
          Translations.translate("Play")
        else
          Translations.translate("Pause")
        end
      end

      def overlaid_button(name)
        Gtk::Button.new.tap do |button|
          button.name = name
          button.valign = :center
          button.add_css_class("circular")
          button.add_css_class("highlighted")
          button.add_css_class("overlaid")
        end
      end
  end
end
