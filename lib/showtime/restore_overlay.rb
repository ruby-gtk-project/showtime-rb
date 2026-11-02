# frozen_string_literal: true

require "adwaita"
require_relative "translations"

module Showtime
  # RestoreOverlay is the port of the `restore_breakpoint_bin` overlay in
  # upstream's showtime/gtk/window.blp: the pair of buttons the window reveals
  # when a video is opened that was left part-watched — Resume, which carries
  # on from the stored position, and Start Again, which seeks back to zero.
  #
  # It starts fully transparent and untargetable, because the window fades it
  # in with an Adw.TimedAnimation on `opacity` rather than by showing it.
  #
  # The two Adw.Breakpoints are what make the pair work at every window size:
  # on a short and narrow window the labels go away and the buttons are
  # icon-only; given height, the buttons become 126×120 tiles with the icon
  # above the label.
  #
  # Upstream labels each button by its own label widget
  # (`accessibility { labelled-by: resume_label; }`). The Ruby bindings do not
  # implement `Gtk::Accessible#update_relation`, which raises
  # NotImplementedError on its array-of-enum argument, and a button whose child
  # is a box containing that label already takes its accessible name from the
  # label, which is what the relation was spelling out.
  class RestoreOverlay < Adwaita::BreakpointBin
    SMALL = "max-height: 320px and max-width: 720px"
    TALL = "min-height: 320px"

    def initialize(on_resume: nil, on_restart: nil)
      super()
      @on_resume = on_resume
      @on_restart = on_restart
      # The bin's own properties from the template: invisible and untargetable
      # until the window animates it in, and sized from its content rather
      # than claiming the overlay's whole area.
      self.opacity = 0
      self.can_target = false
      self.margin_bottom = 60
      self.width_request = 1
      self.height_request = 1
    end

    def build
      tap do |bin|
        bin.child = restore_box
        bin.add_breakpoint(small_breakpoint)
        bin.add_breakpoint(tall_breakpoint)

        restore_box.tap do |box|
          box.append(resume_button)
          box.append(restart_button)

          resume_button.tap do |button|
            button.child = resume_box
            button.signal_connect("clicked") { @on_resume&.call }

            resume_box.tap do |content|
              content.append(resume_icon)
              content.append(resume_label)
            end
          end

          restart_button.tap do |button|
            button.child = restart_box
            button.signal_connect("clicked") { @on_restart&.call }

            restart_box.tap do |content|
              content.append(restart_icon)
              content.append(restart_label)
            end
          end
        end
      end
    end

    def restore_box
      @restore_box ||= Gtk::Box.new(:horizontal, 9).tap do |box|
        box.halign = :center
        box.valign = :center
        box.margin_start = 3
        box.margin_end = 3
      end
    end

    def resume_button
      @resume_button ||= Gtk::Button.new.tap do |button|
        button.add_css_class("overlaid")
        button.add_css_class("highlighted")
      end
    end

    def restart_button
      @restart_button ||= Gtk::Button.new.tap do |button|
        button.add_css_class("overlaid")
        button.add_css_class("highlighted")
      end
    end

    def resume_box = @resume_box ||= button_box
    def restart_box = @restart_box ||= button_box

    def resume_icon
      @resume_icon ||= Gtk::Image.new.tap do |image|
        image.icon_name = "media-playback-start-symbolic"
        image.add_css_class("overlaid")
      end
    end

    def restart_icon
      @restart_icon ||= Gtk::Image.new.tap do |image|
        image.icon_name = "arrow-circular-top-right-symbolic"
        image.add_css_class("overlaid")
      end
    end

    def resume_label = @resume_label ||= overlaid_label("Resume")
    def restart_label = @restart_label ||= overlaid_label("Start Again")

    # Short and narrow: labels off, so the buttons are the icons alone.
    def small_breakpoint
      @small_breakpoint ||= breakpoint(SMALL).tap do |point|
        point.add_setter(restart_label, "visible", GLib::Value.new(GLib::Type::BOOLEAN, false))
        point.add_setter(resume_label, "visible", GLib::Value.new(GLib::Type::BOOLEAN, false))
      end
    end

    # Tall enough for tiles: icon above label, 126×120, with more space
    # between the two buttons.
    def tall_breakpoint
      @tall_breakpoint ||= breakpoint(TALL).tap do |point|
        point.add_setter(restore_box, "spacing", GLib::Value.new(GLib::Type::INT, 24))
        [[restart_button, restart_box, restart_icon], [resume_button, resume_box, resume_icon]]
          .each { |button, box, icon| add_tile_setters(
            point,
            button,
            box,
            icon,
          ) }
      end
    end

    private

      # Every value goes through GLib::Value: adw_breakpoint_add_setter takes a
      # GValue and aborts the process on a type it cannot transform, so the
      # enum setters in particular have to carry their enum's GType.
      def add_tile_setters(point, button, box, icon)
        point.add_setter(button, "width-request", int(126))
        point.add_setter(button, "height-request", int(120))
        point.add_setter(box, "orientation", enum(Gtk::Orientation, Gtk::Orientation::VERTICAL))
        %w[margin-top margin-bottom margin-start margin-end].each do |property|
          point.add_setter(box, property, int(0))
        end
        point.add_setter(icon, "icon-size", enum(Gtk::IconSize, Gtk::IconSize::LARGE))
        point.add_setter(icon, "margin-top", int(12))
      end

      def int(value) = GLib::Value.new(GLib::Type::INT, value)

      def enum(type, value) = GLib::Value.new(type.gtype, value)

      def breakpoint(condition)
        Adwaita::Breakpoint.new(Adwaita::BreakpointCondition.parse(condition))
      end

      def button_box
        Gtk::Box.new(:horizontal, 18).tap do |box|
          box.valign = :center
          box.margin_top = 9
          box.margin_bottom = 9
          box.margin_start = 18
          box.margin_end = 18
        end
      end

      def overlaid_label(text)
        Gtk::Label.new(Translations.translate(text)).tap do |label|
          label.justify = :center
          label.wrap = true
          label.add_css_class("overlaid")
        end
      end
  end
end
