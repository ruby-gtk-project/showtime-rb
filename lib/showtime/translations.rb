# frozen_string_literal: true

module Showtime
  # Translations is the port of upstream's `po/` directory — the 57 locale
  # catalogues listed in po/LINGUAS, whose source strings are the ones
  # po/POTFILES.in collects out of the Python modules and the Blueprint files.
  #
  # Upstream gets its catalogues through gettext: meson compiles each `.po` to
  # a `.mo`, installs it, and `_()` / `ngettext()` read the installed binary
  # catalogue. Compiling and installing a message catalogue to run the app from
  # a checkout is a worse trade than reading the `.po` files directly, so the
  # same catalogues are shipped verbatim under `po/` and parsed here.
  #
  # The entry points match the two gettext calls upstream makes:
  #
  #   Showtime::Translations.translate("Watch Videos")
  #   Showtime::Translations.ngettext(
  #     "Undetermined, {} Channel",
  #     "Undetermined, {} Channels",
  #     channels,
  #   )
  #
  # An untranslated string, an unknown locale and a missing catalogue all fall
  # back to the msgid, which is the English text — the same thing gettext does.
  module Translations
    CATALOGUE_DIR = File.expand_path("../../po", __dir__)

    # The subset of C that a Plural-Forms header may use: `n`, integers, the
    # arithmetic and comparison operators, the logical operators and the
    # conditional operator. Anything else is not evaluated at all.
    PLURAL_EXPRESSION = /\A[\s\dn%()?:!=<>&|*+-]+\z/

    # Parsed catalogues, keyed by locale name, so a second lookup for the same
    # locale does not re-read the file.
    @catalogues = {}

    class << self
      # The locale the environment asks for, as a po file base name, or nil
      # when the environment asks for none of the shipped locales.
      def locale
        candidates.find { |name| File.exist?(catalogue_path(name)) }
      end

      def translate(msgid)
        entry = lookup(msgid)
        if entry
          entry.fetch(:translations).first
        else
          msgid
        end
      end
      alias _ translate

      # The plural form of `msgid` for a count of `count`. Upstream's callers
      # format the result themselves, so the count is only used to pick the
      # form.
      def ngettext(msgid, msgid_plural, count)
        entry = lookup(msgid)
        if entry && entry.fetch(:translations).length > 1
          entry.fetch(:translations)[plural_index(count)] || msgid_plural
        else
          english_plural(msgid, msgid_plural, count)
        end
      end

      # Every locale shipped under po/, in the order po/LINGUAS lists them.
      def available_locales
        path = File.join(CATALOGUE_DIR, "LINGUAS")
        if File.exist?(path)
          File.readlines(path, chomp: true).reject { |line| line.strip.empty? }
        else
          []
        end
      end

      # The catalogue in use, as a msgid => entry hash. Empty when no locale
      # matched — the app then runs on the msgids, which are English.
      def catalogue
        name = locale
        if name
          @catalogues[name] ||= parse(File.read(catalogue_path(name)))
        else
          {}
        end
      end

      # Discards the cached catalogues and locale, so a changed environment
      # (or a test setting LANGUAGE) is picked up on the next lookup.
      def reset!
        @catalogues = {}
        @plural_rule = nil
        nil
      end

      private

        def lookup(msgid)
          entry = catalogue[msgid]
          if entry && !entry.fetch(:translations).first.to_s.empty?
            entry
          end
        end

        # LANGUAGE first and colon-separated, then the single-value variables,
        # exactly the precedence gettext uses. Each value contributes both its
        # full name ("pt_BR") and its bare language ("pt"), since po/ has some
        # of each.
        def candidates
          environment_locales.flat_map { |value| expand(value) }.uniq
        end

        def environment_locales
          ENV.fetch("LANGUAGE", "").split(":")
            .concat([ENV.fetch("LC_ALL", ""), ENV.fetch("LC_MESSAGES", ""), ENV.fetch("LANG", "")])
            .map { |value| value.to_s.strip }
            .reject(&:empty?)
        end

        # "sr_RS@latin.UTF-8" => ["sr_RS@latin", "sr@latin", "sr_RS", "sr"]
        def expand(value)
          language, modifier = value.split(".").first.to_s.split("@")
          bare = language.split("_").first.to_s
          names(language, bare, modifier).reject do |name|
            name.empty? || name.casecmp("c").zero? || name.casecmp("posix").zero?
          end
        end

        def names(language, bare, modifier)
          if modifier
            ["#{language}@#{modifier}", "#{bare}@#{modifier}", language, bare]
          else
            [language, bare]
          end
        end

        def catalogue_path(name) = File.join(CATALOGUE_DIR, "#{name}.po")

        # Which msgstr[i] a count selects, from the catalogue's own
        # Plural-Forms header. Falls back to the Germanic "one or other" rule
        # the header defaults to.
        def plural_index(count)
          rule = plural_rule
          if rule
            normalize_index(rule.call(count))
          else
            default_plural_index(count)
          end
        end

        def default_plural_index(count)
          if count == 1
            0
          else
            1
          end
        end

        def plural_rule
          @plural_rule ||= build_plural_rule(plural_forms_header)
        end

        def plural_forms_header
          header = catalogue[""]
          if header
            header.fetch(:translations).first.to_s[/Plural-Forms:\s*([^\n]*)/, 1].to_s
          else
            ""
          end
        end

        # The header is `nplurals=N; plural=EXPRESSION;`. The expression is C,
        # and the subset the catalogues use — n, %, comparisons, && / ||, and
        # the conditional operator — is also valid Ruby, so it is evaluated as
        # Ruby once it has been checked against PLURAL_EXPRESSION. An
        # expression with anything else in it is refused and the default rule
        # used instead.
        def build_plural_rule(header)
          expression = header[/plural\s*=\s*([^;]+)/, 1].to_s.strip
          if expression.empty? || !expression.match?(PLURAL_EXPRESSION)
            nil
          else
            compile_plural_rule(expression)
          end
        end

        def compile_plural_rule(expression)
          eval(
            "->(n) { #{expression} }",
            binding,
            __FILE__,
            __LINE__,
          )
        rescue SyntaxError, StandardError
          nil
        end

        # A C plural expression yields an int, but the common `(n != 1)` form
        # yields a bool in Ruby; both mean the same index.
        def normalize_index(value)
          case value
          when true then 1
          when false, nil then 0
          else value.to_i
          end
        end

        def english_plural(msgid, msgid_plural, count)
          if count == 1
            msgid
          else
            msgid_plural
          end
        end

        # A `.po` file as a msgid => {translations: [...]} hash.
        #
        # Entries are separated by blank lines; a string value may be
        # continued over any number of following quoted lines; `#~` marks an
        # obsolete entry and `#, fuzzy` an unreviewed one, and gettext ignores
        # both, so this does too.
        def parse(text)
          {}.tap do |entries|
            each_block(text) do |lines|
              add_entry(entries, lines)
            end
          end
        end

        def each_block(text)
          text.split(/\n[ \t]*\n/).each do |block|
            lines = block.lines.map(&:chomp).reject { |line| line.strip.empty? }
            unless lines.empty?
              yield lines
            end
          end
        end

        def add_entry(entries, lines)
          unless skip_block?(lines)
            fields = fields_for(lines)
            msgid = fields["msgid"]
            if msgid
              entries[msgid] = { translations: plural_translations(fields) }
            end
          end
        end

        def skip_block?(lines)
          lines.any? do |line|
            line.start_with?("#~") || line.match?(/\A#,.*\bfuzzy\b/)
          end
        end

        # msgstr for a singular entry, msgstr[0..n] in index order for a
        # plural one.
        def plural_translations(fields)
          indexed = fields.keys.grep(/\Amsgstr\[(\d+)\]\z/).sort_by { |key| key[/\d+/].to_i }
          if indexed.empty?
            [fields.fetch("msgstr", "")]
          else
            indexed.map { |key| fields.fetch(key) }
          end
        end

        # Collapses an entry's lines into a key => value hash, joining each
        # key's continuation lines onto it.
        def fields_for(lines)
          {}.tap do |fields|
            key = nil
            lines.each do |line|
              key = merge_line(fields, key, line)
            end
          end
        end

        def merge_line(fields, key, line)
          case line
          when /\A#/
            key
          when /\A(msgctxt|msgid|msgid_plural|msgstr(?:\[\d+\])?)\s+(".*")\s*\z/
            fields[Regexp.last_match(1)] = unescape(Regexp.last_match(2))
            Regexp.last_match(1)
          when /\A\s*(".*")\s*\z/
            if key
              fields[key] = fields.fetch(key) + unescape(Regexp.last_match(1))
            end
            key
          else
            key
          end
        end

        # Strips the surrounding quotes off each quoted run on the line and
        # resolves the escapes gettext allows inside them.
        def unescape(quoted)
          quoted.scan(/"((?:\\.|[^"\\])*)"/).flatten.join.gsub(/\\(.)/) do
            case Regexp.last_match(1)
            when "n" then "\n"
            when "t" then "\t"
            when "r" then "\r"
            when "0" then "\0"
            else Regexp.last_match(1)
            end
          end
        end
    end
  end

  # The two gettext calls upstream's modules make, at the same length they are
  # written there: `_("…")` becomes `Showtime._("…")`.
  class << self
    def _(msgid) = Translations.translate(msgid)

    def ngettext(msgid, msgid_plural, count) = Translations.ngettext(msgid, msgid_plural, count)
  end
end
