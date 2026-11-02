# frozen_string_literal: true

# Drives the four widgets the video page is built from — the drag overlay, the
# sound options popover, the options popover and the restore overlay.
#
# The window class that assembles them onto a playing video is not ported yet,
# so this hosts them in a window of its own and exercises the behaviour each
# one owns: the volume icon thresholds, the submenus built from a stream list,
# the rate setter, the drop-target binding and the restore buttons.

require "tmpdir"

ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir("showtime-config")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "showtime"
require_relative "gtk_driver"

# A window holding the four widgets side by side, so each one is realized and
# can be driven and photographed.
class WidgetHarness
  attr_reader :resumed, :restarted, :volumes, :mutes, :rotations, :rates

  def initialize
    @resumed = 0
    @restarted = 0
    @volumes = []
    @mutes = []
    @rotations = []
    @rates = []
  end

  def build
    app.tap do
      app.signal_connect("activate") do
        Showtime::Style.load
        Showtime::Icons.load

        window.tap { |win| win.content = box }

        box.tap do |content|
          content.append(drag_overlay.build)
          content.append(sound_options.build)
          content.append(options.build)
          content.append(restore_overlay.build)
        end

        drag_overlay.tap do |overlay|
          overlay.child = Gtk::Label.new("video goes here")
          overlay.overlayed = drop_status_page
          overlay.drop_target = drop_target
          overlay.add_controller(drop_target)
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new("org.rubygtkproject.ShowtimeWidgets", :default_flags)

  def window
    @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
      win.title = "Video widgets"
      win.set_default_size(700, 300)
    end
  end

  def box
    @box ||= Gtk::Box.new(:horizontal, 12).tap do |content|
      content.margin_top = 12
      content.margin_bottom = 12
      content.margin_start = 12
      content.margin_end = 12
      content.valign = :center
    end
  end

  def drag_overlay = @drag_overlay ||= Showtime::DragOverlay.new

  def drop_target = @drop_target ||= Gtk::DropTarget.new(Gio::File.gtype, :copy)

  def drop_status_page
    @drop_status_page ||= Adwaita::StatusPage.new.tap do |page|
      page.title = "Drop Video to Play"
      page.icon_name = "video-x-generic-symbolic"
      page.add_css_class("showtime-dragging-area-highlight")
    end
  end

  def sound_options
    @sound_options ||= Showtime::SoundOptions.new(
      on_mute:   ->(mute) { @mutes << mute },
      on_volume: ->(volume) { @volumes << volume },
    )
  end

  def options
    @options ||= Showtime::Options.new(
      on_rotate_left:  -> { @rotations << :left },
      on_rotate_right: -> { @rotations << :right },
      on_rate:         ->(rate) { @rates << rate },
    )
  end

  def restore_overlay
    @restore_overlay ||= Showtime::RestoreOverlay.new(
      on_resume:  -> { @resumed += 1 },
      on_restart: -> { @restarted += 1 },
    )
  end
end

# The label of the item at `index` of a Gio::Menu.
def label_at(menu, index)
  menu.get_item_attribute_value(index, "label", GLib::VariantType.new("s"))
end

harness = WidgetHarness.new

GtkDriver.drive(harness, shots: File.expand_path("../tmp/shots", __dir__)) do |d, _app|
  d.window { harness.window }

  d.step("everything is on screen") do
    d.check("the drag overlay holds the content") do
      harness.drag_overlay.child.is_a?(Gtk::Label)
    end
    d.check("the drag overlay is not revealing the drop page") do
      harness.drag_overlay.revealer.reveal_child? == false
    end
    d.check("the drop target is bound to it") do
      harness.drag_overlay.drop_target == harness.drop_target
    end
    d.check("the restore overlay starts invisible") { harness.restore_overlay.opacity.zero? }
    d.shot("10-widgets")
  end

  d.step("the volume icon follows the volume") do
    d.check("muted") { harness.sound_options.volume_icon == "audio-volume-muted-symbolic" }
    harness.sound_options.mute = false
    harness.sound_options.volume = 0.9
    d.check("high") { harness.sound_options.volume_icon == "audio-volume-high-symbolic" }
    harness.sound_options.volume = 0.5
    d.check("medium") { harness.sound_options.volume_icon == "audio-volume-medium-symbolic" }
    harness.sound_options.volume = 0.1
    d.check("low") { harness.sound_options.volume_icon == "audio-volume-low-symbolic" }
    d.check("the button shows the same icon") do
      harness.sound_options.menu_button.icon_name == "audio-volume-low-symbolic"
    end
    d.check("each move was reported once") { harness.volumes == [0.9, 0.5, 0.1] }
  end

  d.step("the mute toggle reports back") do
    harness.sound_options.mute_button.active = true
  end

  d.step("muting changed the icon and called back") do
    d.check("reported") { harness.mutes == [true] }
    d.check("icon") { harness.sound_options.menu_button.icon_name == "audio-volume-muted-symbolic" }
  end

  d.step("the options menu fills in from a stream list") do
    harness.options.schedule_menus
    harness.options.build_menus(
      audio_streams:    [
        { language: "English", title: "Commentary" },
        { language: nil, title: nil, channels: 2 },
        { language: "German", title: "German" },
      ],
      subtitle_streams: [{ language: "English", title: nil }],
    )
  end

  d.step("the submenus say what the streams are") do
    d.check("three audio tracks") { harness.options.language_menu.n_items == 3 }
    d.check("the first names its title too") do
      label_at(harness.options.language_menu, 0) == "English - Commentary"
    end
    d.check("the second falls back to its channel count") do
      label_at(harness.options.language_menu, 1) == "Undetermined, 2 Channels"
    end
    d.check("a title the same as the language is not repeated") do
      label_at(harness.options.language_menu, 2) == "German"
    end
    d.check("subtitles get None, the track, and the file chooser") do
      harness.options.subtitles_menu.n_items == 3
    end
    d.check("None comes first") { label_at(harness.options.subtitles_menu, 0) == "None" }
    d.check("the file chooser comes last") do
      label_at(harness.options.subtitles_menu, 2) == "Add Subtitle File…"
    end
  end

  d.step("a video with no audio says so") do
    harness.options.schedule_menus
    harness.options.build_menus(audio_streams: [], subtitle_streams: [])
    d.check("one item") { harness.options.language_menu.n_items == 1 }
    d.check("No Audio") { label_at(harness.options.language_menu, 0) == "No Audio" }
  end

  d.step("the rate setter moves the toggle group") do
    harness.options.rate = "1.5"
  end

  d.step("the rate took") do
    d.check("the group is on 1.5") { harness.options.speed_group.active_name == "1.5" }
    d.check("the rate was reported") { harness.rates.include?("1.5") }
  end

  d.step("the rotate buttons report back") do
    harness.options.rotate_left_button.signal_emit("clicked")
    harness.options.rotate_right_button.signal_emit("clicked")
  end

  d.step("both rotations arrived") do
    d.check("left then right") { harness.rotations == %i[left right] }
  end

  d.step("the restore buttons report back") do
    harness.restore_overlay.resume_button.signal_emit("clicked")
    harness.restore_overlay.restart_button.signal_emit("clicked")
    harness.restore_overlay.opacity = 1
  end

  d.step("resume and restart both fired") do
    d.check("resumed once") { harness.resumed == 1 }
    d.check("restarted once") { harness.restarted == 1 }
    d.shot("11-restore")
  end
end
