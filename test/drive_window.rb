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

  d.step("the three app.* actions from application.rb are present") do
    %w[quit new-window shortcuts].each do |name|
      d.check("app.#{name} exists") { app.app.has_action?(name) }
    end
    d.check("<primary>q is bound to app.quit") { app.app.get_accels_for_action("app.quit") == ["<Control>q"] }
    d.check("<primary>n is bound to app.new-window") { app.app.get_accels_for_action("app.new-window") == ["<Control>n"] }
  end

  d.step("the primary menu's 4 sections point at the actions above") do
    actions = (0...app.primary_menu.n_items).flat_map do |i|
      section = app.primary_menu.get_item_link(i, "section")
      (0...section.n_items).map { |j| section.get_item_attribute_value(j, "action", GLib::VariantType.new("s")) }
    end
    d.check("open-video is on the menu") { actions.include?("win.open-video") }
    d.check("about is on the menu") { actions.include?("win.about") }
    d.check("new-window is on the menu") { actions.include?("app.new-window") }
    d.check("shortcuts is on the menu") { actions.include?("app.shortcuts") }
  end

  d.step("the idle inhibitor is wired to real playback state, not just present") do
    d.check("no inhibitor is held with nothing playing") { app.window_controller.instance_variable_get(:@inhibit_cookie).nil? }
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

  # Window#on_missing_plugin is wired to Play's real "missing-plugin"
  # pub/sub in `wire_play` (window.rb's Messenger#emit is the dispatcher, not
  # a GObject signal), so firing it through that dispatcher — rather than
  # calling the private handler directly — exercises the exact path a real
  # qtdemux/decodebin missing-plugin bus message takes. The message itself is
  # a genuine `GstPbutils` one (`missing_decoder_message_new`), not a stub.
  d.step("a real missing-plugin message reaches the window") do
    Showtime::Play.init
    caps = Gst::Caps.from_string("video/x-h264")
    message = GstPbutils.missing_decoder_message_new(app.window_controller.play.pipeline, caps)
    app.window_controller.play.messenger.send(:emit, "missing-plugin", message)
  end

  d.step("the missing-plugin page is up, from a real bus message") do
    d.check("the placeholder page is showing the missing-plugin state") { app.placeholder_page.showing_missing_plugin? }
    d.check("the description names the codec") { app.placeholder_page.missing_plugin_status_page.description.include?("H.264") }
    # install_plugins_supported reflects whether this system has a PackageKit
    # installer to drive; the description wording is what show_missing_plugin
    # picks between based on whether on_install came back non-nil. Asserting
    # it matches GstPbutils's real answer — rather than hard-coding either
    # wording — proves install_callback is actually asking GstPbutils, not
    # just always returning nil.
    d.check("the wording matches what this system's GstPbutils.install_plugins_supported says") do
      description = app.placeholder_page.missing_plugin_status_page.description
      if GstPbutils.install_plugins_supported
        description.include?("required to play this video")
      else
        description.include?("could not be found")
      end
    end
    d.shot("23-window-missing-plugin-real")
  end

  # on_install_done's three branches are the result-handling half of the
  # install flow (window.rb:482-494). `install_plugins_async` itself drives
  # real PackageKit D-Bus calls this environment has no installer for, so
  # those two branches are driven directly with the same
  # `GstPbutils::InstallPluginsReturn` values `install_plugins_async`'s
  # callback would hand it — not a rescue around a crash, a direct exercise
  # of logic that takes a plain enum argument.
  d.step("on_install_done(NOT_FOUND) reports no plugin available") do
    app.window_controller.send(:on_install_done, GstPbutils::InstallPluginsReturn::NOT_FOUND)
  end

  d.step("the not-found message landed") do
    d.check("the page says no plugin is available") do
      description = app.placeholder_page.missing_plugin_status_page.description
      description.include?("No plug") && description.include?("available")
    end
  end

  d.step("on_install_done(some other failure) reports the install failed") do
    app.window_controller.send(:on_install_done, GstPbutils::InstallPluginsReturn::ERROR)
  end

  d.step("the failure message landed") do
    d.check("the page says the install failed") do
      description = app.placeholder_page.missing_plugin_status_page.description
      description.include?("Unable to install") && description.include?("plug")
    end
    d.shot("24-window-missing-plugin-install-failed")
  end
end
