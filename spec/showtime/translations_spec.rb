# frozen_string_literal: true

RSpec.describe Showtime::Translations do
  around do |example|
    original = %w[LANGUAGE LC_ALL LC_MESSAGES LANG].to_h { |name| [name, ENV[name]] }
    described_class.reset!
    example.run
  ensure
    original.each { |name, value| ENV[name] = value }
    described_class.reset!
  end

  describe ".translate" do
    it "falls back to the msgid when no locale matches" do
      ENV["LANGUAGE"] = "xx_XX"

      expect(described_class.translate("Watch Videos")).to eq("Watch Videos")
    end

    it "falls back to the msgid for an unknown string in a known locale" do
      ENV["LANGUAGE"] = "de"

      expect(described_class.translate("Something nobody wrote a msgid for")).to(
        eq("Something nobody wrote a msgid for"),
      )
    end

    it "reads the matching msgstr out of the locale's catalogue" do
      ENV["LANGUAGE"] = "de"

      expect(described_class.translate("Watch Videos")).to eq("Videos ansehen")
    end

    it "prefers LANGUAGE over LANG" do
      ENV["LANGUAGE"] = "de"
      ENV["LANG"] = "fr_FR.UTF-8"

      expect(described_class.translate("Watch Videos")).to eq("Videos ansehen")
    end

    it "falls back to LANG when LANGUAGE names no shipped locale" do
      ENV.delete("LANGUAGE")
      ENV["LANG"] = "de_DE.UTF-8"

      expect(described_class.translate("Watch Videos")).to eq("Videos ansehen")
    end
  end

  describe ".ngettext" do
    it "uses the catalogue's plural form for a count other than 1" do
      ENV["LANGUAGE"] = "de"

      expect(
        described_class.ngettext("Undetermined, {} Channel", "Undetermined, {} Channels", 2),
      ).to eq("Unbestimmt, {} Kanäle")
    end

    it "uses the catalogue's singular form for a count of 1" do
      ENV["LANGUAGE"] = "de"

      expect(
        described_class.ngettext("Undetermined, {} Channel", "Undetermined, {} Channels", 1),
      ).to eq("Unbestimmt, {} Kanal")
    end

    it "falls back to the English plural rule with no matching locale" do
      ENV["LANGUAGE"] = "xx_XX"

      expect(
        described_class.ngettext("Undetermined, {} Channel", "Undetermined, {} Channels", 3),
      ).to eq("Undetermined, {} Channels")
      expect(
        described_class.ngettext("Undetermined, {} Channel", "Undetermined, {} Channels", 1),
      ).to eq("Undetermined, {} Channel")
    end
  end

  describe ".available_locales" do
    it "lists every locale under po/LINGUAS, including de and fr" do
      expect(described_class.available_locales).to include("de", "fr")
    end
  end

  describe "Showtime._ and Showtime.ngettext" do
    it "delegate to Translations" do
      ENV["LANGUAGE"] = "de"

      expect(Showtime._("Watch Videos")).to eq("Videos ansehen")
      expect(
        Showtime.ngettext("Undetermined, {} Channel", "Undetermined, {} Channels", 2),
      ).to eq("Unbestimmt, {} Kanäle")
    end
  end
end
