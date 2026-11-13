# Reading an uploaded spreadsheet for a SpreadsheetImport.
module SpreadsheetUpload
  private
    # Spreadsheets saved from Excel are often Windows-1252 and start with a byte-order mark.
    def read_csv(file)
      return "" unless file.respond_to?(:read)
      return "x" * (SpreadsheetImport::MAX_SIZE + 1) if file.size > SpreadsheetImport::MAX_SIZE

      text = file.read.delete_prefix("\xEF\xBB\xBF".b)
      text.force_encoding(Encoding::UTF_8).valid_encoding? ? text : text.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8)
    end

    def import_from(klass, file)
      klass.new(account: Current.account, creator: Current.user, csv: read_csv(file),
        filename: (file.original_filename if file.respond_to?(:original_filename)))
    end
end
