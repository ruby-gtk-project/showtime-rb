# frozen_string_literal: true

require_relative "rb/version"

# The part of Showtime that loads without a display.
#
# This file exists because `require "gtk4"` initialises GTK at require time
# and raises Gtk::InitError when there is no display server, so anything that
# reaches a widget class cannot be loaded by a plain `ruby -e` or by a test
# process on a headless machine. The split is along that line and no other:
#
#   require "showtime/rb"   the translation catalogue and the settings
#                           backend — no gtk4, no adwaita, loadable anywhere;
#   require "showtime"      all of the above plus every widget and the
#                           application, which needs a display.
#
# It is also the file the gem's version constant lives under, which is why
# spec/spec_helper.rb requires it: the specs for the display-free half need
# nothing more, and the ones that drive widgets ask for "showtime" themselves.
require_relative "translations"
require_relative "settings"
require_relative "log"
