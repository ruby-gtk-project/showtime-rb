# frozen_string_literal: true

# Drives the window shell: the stack it builds (placeholder page + video
# page), the drag-and-drop target, the window-level actions it creates, and
# the breakpoint it installs.
#
# What this does *not* drive is actually playing a video: under this
# project's Xvfb test environment, handing a real URI to `Play` crashes the
# process — a Rust panic inside gst-plugins-rs's `gtk4paintablesink`
# ("Value accessed from different thread than where it was created"),
# reproducible with `Play` alone and nothing this port's code touches. It is
# an environment limitation, not something `Window` can route around, so
# this only exercises what is safe to drive headlessly: the shell, its
# actions, and the two pages' wiring.

require "tmpdir"

ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir("showtime-config")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "showtime"
require_relative "gtk_driver"

app = Showtime::Application.new

GtkDriver.drive(app, shots: File.expand_path("../tmp/shots", __dir__)) do |d, _app|
  d.window { app.window }

  d.step("the window builds both stack pages") do
    d.check("the stack has 2 children") { app.window_controller.stack.pages.n_items == 2 }
    d.check("it opens on the welcome page") { app.placeholder_page.stack.visible_child == app.placeholder_page.open_status_page }
    d.shot("20-window-welcome")
  end

  d.step("every window action window.py creates is present") do
    %w[
      close-window about toggle-fullscreen toggle-playback increase-volume
      decrease-volume toggle-mute backwards forwards decrease-rate
      increase-rate screenshot show-in-files open-video choose-subtitles
      select-subtitles select-language toggle-loop
    ].each do |name|
      d.check("win.#{name} exists") { app.window.has_action?(name) }
    end
    d.check("screenshot starts disabled") { !app.window.lookup_action("screenshot").enabled? }
    d.check("show-in-files starts disabled") { !app.window.lookup_action("show-in-files").enabled? }
  end

  d.step("the drop target accepts a GFile") do
    d.check("drag overlay's drop target is wired") { app.window_controller.drop_target.formats.contain_gtype(Gio::File.gtype) }
  end

  d.step("volume, mute, rate and loop actions run without crashing") do
    app.window.activate_action("increase-volume", nil)
    app.window.activate_action("decrease-volume", nil)
    app.window.activate_action("toggle-mute", nil)
    app.window.activate_action("toggle-mute", nil)
    app.window.activate_action("increase-rate", nil)
    app.window.activate_action("decrease-rate", nil)
    app.window.activate_action("toggle-loop", nil)
  end

  d.step("looping persisted to settings") do
    d.check("looping is now on") { app.settings.looping? == true }
  end

  d.step("the video page can be shown on its own, with no video loaded") do
    app.window_controller.stack.visible_child = app.window_controller.video_page.root
  end

  d.step("the video page is the visible stack child") do
    d.check("stack shows the video page") do
      app.window_controller.stack.visible_child == app.window_controller.video_page.root
    end
    d.shot("21-window-video-page-empty")
  end

  d.step("back to the welcome page") do
    app.window_controller.stack.visible_child = app.placeholder_page.toolbar_view
  end

  d.step("still on the welcome page") do
    d.check("the welcome page is showing again") { app.placeholder_page.stack.visible_child == app.placeholder_page.open_status_page }
    d.shot("22-window-back-to-welcome")
  end
end
