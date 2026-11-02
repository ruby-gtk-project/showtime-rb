# frozen_string_literal: true

require "adwaita"
require_relative "rb/version"
require_relative "translations"

module Showtime
  # AboutDialog is the port of `Window._present_about_dialog` in upstream's
  # showtime/widgets/window.py, together with the parts of
  # data/org.gnome.Showtime.metainfo.xml.in that the dialog reads.
  #
  # Upstream builds it with `Adw.AboutDialog.new_from_appdata`, which pulls the
  # name, summary, licence, URLs and release notes out of the metainfo XML that
  # the GResource bundle carries, and then sets the credits and copyright by
  # hand. There is no appdata resource to read here, so the same fields are
  # carried as constants below — the values are upstream's, from the metainfo
  # file and from the method itself.
  #
  # The one field with no counterpart is `debug_info`: upstream fills it from
  # its rotating log file, and this port has no logger, so it reports the
  # library versions the app is running on, which is the thing a bug report
  # actually needs out of that field.
  class AboutDialog < Adwaita::AboutDialog
    APPLICATION_NAME = "Video Player"
    APPLICATION_ICON = "org.gnome.Showtime"
    DEVELOPER_NAME = "The GNOME Project"
    COPYRIGHT = "© 2024-2025 kramo"
    LICENSE_TYPE = :gpl_3_0

    WEBSITE = "https://apps.gnome.org/Showtime/"
    ISSUE_URL = "https://gitlab.gnome.org/GNOME/showtime/-/issues"
    SUPPORT_URL = "https://welcome.gnome.org/app/Showtime/"
    TRANSLATE_URL = "https://l10n.gnome.org/module/showtime/"

    COMMENTS = "Watch without distraction"

    DEVELOPERS = [
      "kramo https://kramo.page",
    ].freeze

    DESIGNERS = [
      "Tobias Bernard https://tobiasbernard.com/",
      "Allan Day https://blogs.gnome.org/aday/",
      "kramo https://kramo.page",
    ].freeze

    # The <release> the metainfo file lists first.
    RELEASE_VERSION = "50.0"

    RELEASE_NOTES = <<~HTML
      <ul>
        <li>Videos with partially-missing plugins can now be attempted to be played anyway.</li>
        <li>Smaller quality-of-life improvements.</li>
      </ul>
    HTML

    def initialize(version: Rb::VERSION)
      super()
      @version = version
    end

    def build
      tap do |dialog|
        dialog.application_name = Translations.translate(APPLICATION_NAME)
        dialog.application_icon = APPLICATION_ICON
        dialog.developer_name = Translations.translate(DEVELOPER_NAME)
        dialog.version = @version
        dialog.comments = Translations.translate(COMMENTS)
        dialog.copyright = COPYRIGHT
        dialog.license_type = LICENSE_TYPE
        dialog.website = WEBSITE
        dialog.issue_url = ISSUE_URL
        dialog.support_url = SUPPORT_URL
        dialog.translator_credits = Translations.translate("translator-credits")
        dialog.developers = DEVELOPERS
        dialog.designers = DESIGNERS
        dialog.release_notes_version = RELEASE_VERSION
        dialog.release_notes = RELEASE_NOTES
        dialog.debug_info = version_info
        dialog.debug_info_filename = "showtime-versions.txt"
        dialog.add_link(Translations.translate("Translate"), TRANSLATE_URL)
      end
    end

    private

      def version_info
        [
          "#{APPLICATION_NAME} #{@version}",
          "Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})",
          "GTK #{Gtk::Version::STRING}",
          "Libadwaita #{adwaita_version}",
          "Locale #{Translations.locale || "C"}",
        ].join("\n")
      end

      def adwaita_version
        [Adwaita::MAJOR_VERSION, Adwaita::MINOR_VERSION, Adwaita::MICRO_VERSION].join(".")
      end
  end
end
