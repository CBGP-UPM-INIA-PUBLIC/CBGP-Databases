# frozen_string_literal: true

# Covers the two pure helpers in lib/core.rb that everything else about
# currency handling is built on: parse_currency_input (locale-aware text ->
# canonical decimal, used on save and search) and format_currency (canonical
# decimal -> locale-aware text, used on display and export). If these ever
# regress, every currency field silently breaks for one or both regions.
RSpec.describe 'currency parsing and formatting' do
  describe '#parse_currency_input' do
    it 'parses US-style input (comma thousands, period decimal)' do
      expect(parse_currency_input('15,000.5', language: 'en')).to eq('15000.50')
    end

    it 'parses Spanish-style input (period thousands, comma decimal)' do
      expect(parse_currency_input('15.000,50', language: 'es')).to eq('15000.50')
    end

    it 'parses a plain whole number the same in either language' do
      expect(parse_currency_input('500', language: 'en')).to eq('500.00')
      expect(parse_currency_input('500', language: 'es')).to eq('500.00')
    end

    it 'preserves a negative sign' do
      expect(parse_currency_input('-1234.5', language: 'en')).to eq('-1234.50')
    end

    it 'defaults to current_language when none is given' do
      Thread.current[:language] = 'es'
      expect(parse_currency_input('1.234,56')).to eq('1234.56')
    end

    it 'returns nil for blank input' do
      expect(parse_currency_input('')).to be_nil
      expect(parse_currency_input('   ')).to be_nil
      expect(parse_currency_input(nil)).to be_nil
    end

    it 'returns nil (does not raise) for non-numeric input' do
      expect(parse_currency_input('fifteen thousand', language: 'en')).to be_nil
      expect(parse_currency_input('abc', language: 'en')).to be_nil
    end

    it 'rejects malformed grouping/decimals instead of silently misreading them' do
      # Reported bug (2026-07-06): stripping thousands separators blindly and
      # handing the rest to Float() accepted "2,00.0000" as 200.00 — a wrong
      # grouping (2 digits, not 3) *and* a nonsensical decimal length (4
      # digits), neither of which should ever parse as a real amount.
      expect(parse_currency_input('2,00.0000', language: 'en')).to be_nil
      expect(parse_currency_input('2.00,0000', language: 'es')).to be_nil
      expect(parse_currency_input('1,23.45', language: 'en')).to be_nil # bad grouping alone
      expect(parse_currency_input('1234.567', language: 'en')).to be_nil # bad decimal length alone
    end

    it 'accepts large numbers with multiple correct thousands groups' do
      expect(parse_currency_input('1,234,567.89', language: 'en')).to eq('1234567.89')
    end

    it 'accepts a single decimal digit' do
      expect(parse_currency_input('15.5', language: 'en')).to eq('15.50')
    end
  end

  describe '#format_currency' do
    it 'formats a canonical amount in US style' do
      expect(format_currency('15000.50', language: 'en')).to eq('15,000.50')
    end

    it 'formats a canonical amount in Spanish style' do
      expect(format_currency('15000.50', language: 'es')).to eq('15.000,50')
    end

    it 'pads a whole number to two decimal places' do
      expect(format_currency('500', language: 'en')).to eq('500.00')
    end

    it 'preserves a negative sign' do
      expect(format_currency('-1234.50', language: 'es')).to eq('-1.234,50')
    end

    it 'groups amounts over a million correctly' do
      expect(format_currency('1234567.89', language: 'en')).to eq('1,234,567.89')
    end

    it 'returns an empty string for blank input' do
      expect(format_currency('')).to eq('')
      expect(format_currency(nil)).to eq('')
    end

    it 'echoes non-canonical input unchanged instead of mangling it' do
      # This is what gets redisplayed after a ValidationError — the user's
      # own invalid input, not a canonical decimal — so it must come back
      # exactly as typed, not garbled by the grouping logic.
      expect(format_currency('fifteen thousand', language: 'en')).to eq('fifteen thousand')
    end
  end

  describe 'round-tripping between locales' do
    it 'produces the same canonical value regardless of which locale it was typed in' do
      from_us = parse_currency_input('15,000.5', language: 'en')
      from_es = parse_currency_input('15.000,50', language: 'es')
      expect(from_us).to eq(from_es)
    end

    it 'redisplays a saved amount correctly in both languages' do
      canonical = parse_currency_input('15,000.5', language: 'en')
      expect(format_currency(canonical, language: 'en')).to eq('15,000.50')
      expect(format_currency(canonical, language: 'es')).to eq('15.000,50')
    end
  end
end
