# frozen_string_literal: true

require "gtk4"
require "uri"

module Showtime
  # Utils is the port of upstream's showtime/utils.py: the four helpers the
  # window and the options menu share — a timestamp formatter, the video title,
  # an action lookup with type checking, a font description scaled for
  # subtitles — plus the paintable screenshot taken from Workbench.
  module Utils
    # Below this many characters, a stripped timestamp is seconds only and
    # wants a "0:" minute part putting back.
    SECONDS_ONLY = 2

    # The two placeholder titles GStreamer reports for a stream that has no
    # title tag; upstream treats both as "no title" and falls back to the file
    # name.
    PLACEHOLDER_TITLES = %w[Video Audio].freeze

    class << self
      # Converts `ns` to a human readable time stamp, in the format 1:23 or
      # 1:23:45 depending on length.
      #
      # With `hours: true`, always returns the full 01:23:45 form — which is
      # what the screenshot file name uses, so the names of two screenshots
      # sort the way their positions do.
      def nanoseconds_to_timestamp(ns, hours: false)
        formatted = full_timestamp(ns)
        if hours
          formatted
        else
          short_timestamp(formatted)
        end
      end

      # The title of the video.
      #
      # Upstream takes a `GstPlayMediaInfo` and reads the stream title and URI
      # off it; with no GstPlay binding in Ruby the same two values are passed
      # in, so the rule — the stream's own title unless it is missing or one of
      # the placeholders, otherwise the file name without its extension — is
      # the part that is ported.
      def get_title(uri, media_title = nil)
        if titled?(media_title)
          media_title
        else
          stem(uri)
        end
      end

      # The file name of `uri` without its extension, percent-decoding
      # included, as upstream's `Path(unquote(urlparse(uri).path)).stem`.
      def stem(uri)
        path = path_for(uri)
        if path.empty?
          nil
        else
          File.basename(path, File.extname(path))
        end
      end

      # Looks up an action in `action_map` with type checking: anything that is
      # not an action map, and any action that is not a `Gio::SimpleAction`,
      # comes back as nil rather than as something the caller would then poke
      # `enabled=` at.
      def lookup_action(action_map, name)
        if action_map.is_a?(Gio::ActionMap)
          simple_action(action_map.lookup_action(name))
        end
      end

      # A font description scaled to the user's preferences, ideal for
      # rendering subtitles.
      #
      # The GTK font name carries a point size that is not scaled by the text
      # scaling factor, so the size is multiplied by the ratio of the Xft DPI
      # to the unscaled 72 and put back on the name.
      def subtitle_font_desc(settings = Gtk::Settings.default)
        if settings
          scaled_font_name(settings.gtk_font_name.to_s, settings.gtk_xft_dpi)
        end
      end

      # Takes a screenshot of the current image of a `Gdk::Paintable`.
      #
      # Copied from Workbench, by way of upstream:
      # https://github.com/workbenchdev/Workbench/blob/1ebbe1e/src/Previewer/previewer.vala#L36
      def screenshot(paintable, native)
        image = paintable.current_image
        width = image.intrinsic_width
        height = image.intrinsic_height
        render(
          native,
          node_for(image, width, height),
          width,
          height,
        )
      end

      private

        def full_timestamp(ns)
          seconds = (ns.to_i / 1_000_000_000)
          format(
            "%<hours>02d:%<minutes>02d:%<seconds>02d",
            hours:   (seconds / 3600) % 24,
            minutes: (seconds / 60) % 60,
            seconds: seconds % 60,
          )
        end

        # Upstream's `formatted.lstrip("0:") or "0"`: drops every leading zero
        # and colon, so 00:01:23 becomes 1:23 and 00:00:05 becomes 5, then
        # puts a padded minute part back on anything that came out as seconds
        # only.
        def short_timestamp(formatted)
          stripped = formatted.sub(/\A[0:]+/, "")
          if stripped.empty?
            "0:00"
          elsif stripped.length > SECONDS_ONLY
            stripped
          else
            "0:#{stripped.rjust(2, "0")}"
          end
        end

        def titled?(media_title)
          !media_title.to_s.empty? && !PLACEHOLDER_TITLES.include?(media_title)
        end

        # `unquote(urlparse(uri).path)`: percent-decoding only — a "+" in a
        # file name is a "+", not a space, which is why this is not
        # `URI.decode_www_form_component`.
        def path_for(uri)
          URI::DEFAULT_PARSER.unescape(URI.parse(uri.to_s).path.to_s)
        rescue URI::InvalidURIError
          ""
        end

        def simple_action(action)
          if action.is_a?(Gio::SimpleAction)
            action
          end
        end

        def scaled_font_name(font_name, xft_dpi)
          size = font_name[/ (\d+(?:\.\d+)?)\z/, 1]
          if size
            "#{font_name[0...-size.length]}#{(size.to_f * ((xft_dpi.to_f / 1024) / 72)).round}"
          else
            font_name
          end
        end

        def node_for(image, width, height)
          Gtk::Snapshot.new.tap do |snapshot|
            image.snapshot(snapshot, width, height)
          end.to_node
        end

        def render(native, node, width, height)
          renderer = native.renderer
          if node && renderer
            renderer.render_texture(
              node,
              Graphene::Rect.new(
                0,
                0,
                width,
                height,
              ),
            )
          end
        end
    end
  end
end
