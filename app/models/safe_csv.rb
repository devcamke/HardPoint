# CSV that's safe to open in Excel or Google Sheets. A cell someone typed that starts with = + - @ (or a tab or
# carriage return) would be run as a formula, so it's written with a leading apostrophe, which spreadsheets show as
# plain text. Numbers, including negative amounts, are left alone. Importing strips the apostrophe again.
module SafeCsv
  FORMULA = /\A[=+\-@\t\r]/
  NUMBER = /\A[-+]?\d[\d,]*(\.\d+)?\z/
  ESCAPED = /\A'(?=[=+\-@\t\r])/

  def self.generate(**options, &)
    CSV.generate(write_converters: [ ESCAPE ], **options, &)
  end

  def self.escape(value)
    value.is_a?(String) && value.match?(FORMULA) && !value.match?(NUMBER) ? "'#{value}" : value
  end

  def self.unescape(value)
    value.is_a?(String) ? value.sub(ESCAPED, "") : value
  end

  # The csv gem takes converters as procs.
  ESCAPE = ->(value) { escape(value) }
  UNESCAPE = ->(value) { unescape(value) }
end
