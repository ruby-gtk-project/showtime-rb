# frozen_string_literal: true

# Drives the MPRIS2 surface: lib/showtime/mpris.rb, the port of
# showtime/mpris.py.
#
# MPRIS registers its four interfaces as D-Bus object handlers, but calling
# through a real client (DBusConnection#call_sync) from the same process
# deadlocks: the reply can only be dispatched once the main loop is free, and
# call_sync blocks that very loop waiting on it. A real MPRIS client (GNOME
# Shell, playerctl) lives in another process and has no such problem; here
# the dispatcher is exercised directly, the way blanket-rb's
# test/drive_app.rb already does for its own Mpris class — "call the
# handler the way the widget would" for a GDBus method table rather than a
# widget signal.

require "tmpdir"

ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir("showtime-config")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "showtime"
require_relative "gtk_driver"

FakeInvocation = Struct.new(:value, :error) do
  def return_value(v) = self.value = v
  def return_dbus_error(name, msg) = self.error = [name, msg]
end

MEDIA_PLAYER_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"

def call_mpris(mpris, iface, method, params = [])
  FakeInvocation.new.tap do |inv|
    mpris.send(:handle_method_call, iface, method, params, inv)
  end
end

def get(mpris, iface, prop)
  call_mpris(mpris, PROPERTIES_IFACE, "Get", [iface, prop]).value.value.first
end

app = Showtime::Application.new

GtkDriver.drive(app, shots: File.expand_path("../tmp/shots", __dir__)) do |d, _app|
  d.window { app.window }

  d.step("the app builds an MPRIS object on the session bus") do
    @mpris = app.mpris

    d.check("the object is registered") { !@mpris.instance_variable_get(:@build).nil? }
  end

  d.step("introspection answers with the real node XML") do
    inv = call_mpris(@mpris, "org.freedesktop.DBus.Introspectable", "Introspect")

    d.check("the player interface is in it") { inv.value.to_s.include?("org.mpris.MediaPlayer2.Player") }
  end

  d.step("MediaPlayer2 properties answer from the real app state") do
    d.check("Identity is the window title") { get(@mpris, MEDIA_PLAYER_IFACE, "Identity") == "Video Player" }
    d.check("DesktopEntry is the app id") { get(@mpris, MEDIA_PLAYER_IFACE, "DesktopEntry") == Showtime::Application::APP_ID }
    d.check("CanRaise is false") { get(@mpris, MEDIA_PLAYER_IFACE, "CanRaise") == false }
  end

  d.step("with no video loaded, the player reports Stopped and cannot play") do
    d.check("PlaybackStatus is Stopped") { get(@mpris, PLAYER_IFACE, "PlaybackStatus") == "Stopped" }
    d.check("CanPlay is false") { get(@mpris, PLAYER_IFACE, "CanPlay") == false }
    d.check("CanSeek is still true") { get(@mpris, PLAYER_IFACE, "CanSeek") == true }
  end

  d.step("GetAll answers for the Player interface") do
    inv = call_mpris(@mpris, PROPERTIES_IFACE, "GetAll", [PLAYER_IFACE])

    d.check("the metadata dict is in the reply") { inv.value.to_s.include?("mpris:trackid") }
  end

  d.step("MPRIS Raise presents the window") do
    app.window.visible = false
    call_mpris(@mpris, MEDIA_PLAYER_IFACE, "Raise")

    d.check("the window is visible again") { app.window.visible? }
  end

  d.step("LoopStatus follows the looping setting") do
    app.settings.looping = true

    d.check("LoopStatus reports Track") { get(@mpris, PLAYER_IFACE, "LoopStatus") == "Track" }

    app.settings.looping = false

    d.check("and back to None") { get(@mpris, PLAYER_IFACE, "LoopStatus") == "None" }
  end

  d.step("Setting Rate buckets an arbitrary value into one of the toggle group's rates") do
    call_mpris(@mpris, PROPERTIES_IFACE, "Set", [PLAYER_IFACE, "Rate", 1.3])

    d.check("1.3 landed on the 1.25x bucket") { app.rate == "1.25" }
  end

  d.step("PlayPause with nothing loaded does not crash") do
    call_mpris(@mpris, PLAYER_IFACE, "PlayPause")

    d.check("still stopped") { app.stopped? }
  end

  d.step("an unknown MPRIS method returns a DBus error, not a crash") do
    inv = call_mpris(@mpris, PLAYER_IFACE, "Teleport")

    d.check("an error came back") { inv.error&.first == "#{PLAYER_IFACE}.UnknownMethod" }
  end

  d.step("Next/Previous/OpenUri are deliberate no-ops, not crashes") do
    inv_next = call_mpris(@mpris, PLAYER_IFACE, "Next")
    inv_prev = call_mpris(@mpris, PLAYER_IFACE, "Previous")
    inv_uri = call_mpris(@mpris, PLAYER_IFACE, "OpenUri", ["file:///nope.mp4"])

    d.check("all three returned cleanly") { inv_next.error.nil? && inv_prev.error.nil? && inv_uri.error.nil? }
  end
end
