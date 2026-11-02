# frozen_string_literal: true

# Drives the application window: the placeholder page's three states, the
# primary menu, and the two dialogs the menu opens.

require "tmpdir"

ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir("showtime-config")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "showtime"
require_relative "gtk_driver"

app = Showtime::Application.new

GtkDriver.drive(app, shots: File.expand_path("../tmp/shots", __dir__)) do |d, _app|
  d.window { app.window }

  d.step("the window opens on the welcome page") do
    d.check("the window has a title") { app.window.title == "Video Player" }
    d.check("the welcome page is showing") do
      app.placeholder_page.stack.visible_child == app.placeholder_page.open_status_page
    end
    d.check("the app's icons all resolved") { Showtime::Icons.missing.empty? }
    d.check("the primary menu has four sections") { app.primary_menu.n_items == 4 }
    d.check("the open button is wired to win.open-video") do
      app.placeholder_page.open_button.action_name == "win.open-video"
    end
    d.shot("01-welcome")
  end

  d.step("the error state fills in from a failed stream") do
    app.placeholder_page.show_error(
      on_try_again:    -> {},
      on_copy_details: -> {},
    )
  end

  d.step("the error page shows its two rows") do
    d.check("the error page is showing") do
      app.placeholder_page.stack.visible_child == app.placeholder_page.error_status_page
    end
    d.check("it has an action group") do
      app.placeholder_page.error_status_page.child.is_a?(Adwaita::PreferencesGroup)
    end
    d.shot("02-error")
  end

  d.step("the missing-plugin state fills in") do
    app.placeholder_page.show_missing_plugin(
      description:   "H.264 (High Profile)",
      on_install:    -> {},
      on_try_anyway: -> {},
    )
  end

  d.step("the missing-plugin page names the codec") do
    d.check("the missing-plugin page is showing") { app.placeholder_page.showing_missing_plugin? }
    d.check("the description names the codec") do
      app.placeholder_page.missing_plugin_status_page.description.include?("H.264 (High Profile)")
    end
    d.shot("03-missing-plugin")
  end

  d.step("a system with no plugin installer gets the other message") do
    app.placeholder_page.show_missing_plugin(description: "H.264")
    d.check("the description says the codecs could not be found") do
      app.placeholder_page.missing_plugin_status_page.description.include?("could not be found")
    end
  end

  d.step("back to the welcome page") { app.placeholder_page.show_open }

  d.step("the shortcuts dialog opens") do
    app.app.activate_action("shortcuts", nil)
  end

  d.step("the shortcuts dialog is up") do
    d.check("a dialog is showing") { !app.window.visible_dialog.nil? }
    d.shot("04-shortcuts")
    app.window.visible_dialog&.close
  end

  d.step("the about dialog opens") do
    app.window.activate_action("about", nil)
  end

  d.step("the about dialog is up") do
    d.check("a dialog is showing") { !app.window.visible_dialog.nil? }
    d.check("it reports the libraries it is running on") do
      app.about_dialog.debug_info.include?("Libadwaita")
    end
    d.shot("05-about")
    app.window.visible_dialog&.close
  end

  # Whether the window actually ends up fullscreen is up to the window
  # manager, and there is none under Xvfb, so this checks that the action is
  # there and that activating it is harmless rather than asserting the state.
  d.step("the fullscreen action is bound") do
    d.check("the window has it") { app.window.has_action?("toggle-fullscreen") }
    d.check("F11 and f are bound to it") do
      app.app.get_accels_for_action("win.toggle-fullscreen") == %w[F11 f]
    end
    app.window.activate_action("toggle-fullscreen", nil)
  end

  d.step("the window survived it") do
    d.check("still showing the welcome page") do
      app.placeholder_page.stack.visible_child == app.placeholder_page.open_status_page
    end
    d.shot("06-after-fullscreen")
  end
end
