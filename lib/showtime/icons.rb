# frozen_string_literal: true

require "gtk4"

module Showtime
  # Icons is the port of the app-shipped symbolic icons: the eight SVGs under
  # data/icons/scalable/actions/ that upstream bundles into its GResource (see
  # the first `<gresource>` block of showtime/showtime.gresource.xml.in) and
  # reaches through `Gtk.IconTheme.add_resource_path`.
  #
  # These are the icons that are *not* in the Adwaita icon theme, so every one
  # of them is a blank square until the app adds its own search path. The SVGs
  # themselves are shipped verbatim under data/icons/scalable/actions/; this
  # adds that directory to the icon theme for a display, which is the
  # filesystem equivalent of upstream's resource path.
  module Icons
    SEARCH_PATH = File.expand_path("../../data/icons/scalable/actions", __dir__)

    # The icon names, without the ".svg", in the order the gresource lists
    # them. Every one is used by a widget in this port or in upstream's UI.
    NAMES = %w[
      settings-symbolic
      puzzle-piece-symbolic
      skip-backwards-10-symbolic
      skip-forward-10-symbolic
      speedometer2-symbolic
      speedometer3-symbolic
      speedometer4-symbolic
      arrow-circular-top-right-symbolic
    ].freeze

    class << self
      # Adds the app's icon directory to `display`'s icon theme, once per
      # display. Returns the icon theme.
      def load(display = Gdk::Display.default)
        if display
          theme_for(display).tap do |theme|
            unless theme.search_path.include?(SEARCH_PATH)
              theme.add_search_path(SEARCH_PATH)
            end
          end
        end
      end

      # The names that are missing after loading — empty when every shipped
      # icon resolved.
      def missing(display = Gdk::Display.default)
        theme = load(display)
        if theme
          NAMES.reject { |name| theme.has_icon?(name) }
        else
          NAMES
        end
      end

      def files = NAMES.map { |name| File.join(SEARCH_PATH, "#{name}.svg") }

      private

        def theme_for(display) = Gtk::IconTheme.get_for_display(display)
    end
  end
end
