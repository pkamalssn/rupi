# frozen_string_literal: true

require_relative "base"

module BankStatementParser
  class Sbi < Base
    def parse
      transactions = []

      if file.content_type == "application/pdf"
        transactions = parse_pdf
      elsif %w[application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet text/csv].include?(file.content_type)
        transactions = parse_excel
      else
        raise UnsupportedFormatError, "Unsupported file format: #{file.content_type}"
      end

      transactions
    rescue => e
      raise ParseError, "Failed to parse SBI statement: #{e.message}"
    end

    private

    def parse_pdf
      require "pdf-reader"

      pdf_content = file.respond_to?(:download) ? StringIO.new(file.download) : File.open(file.path, "rb")
      reader = PDF::Reader.new(pdf_content)

      text = ""
      reader.pages.each { |page| text += page.text }

      parse_transactions_from_text(text)
    end

    def parse_excel
      require "roo"

      spreadsheet = case file.content_type
                    when "application/vnd.ms-excel" then Roo::Excel.new(file.path)
                    when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" then Roo::Excelx.new(file.path)
                    when "text/csv" then Roo::CSV.new(file.path)
                    end

      transactions = []

      spreadsheet.each_with_index do |row, idx|
        next if idx == 0

        date = parse_date(row[0])
        next unless date

        # SBI Excel may have separate debit/credit columns
        amount = parse_amount(row[3]) || parse_amount(row[4])
        amount = -amount.abs if row[3].present? # Debit column

        next unless amount

        description = clean_description(row[1] || row[2])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "SBI Transaction",
          notes: "Imported from SBI statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []

      lines = text.split("\n")
      lines.each do |line|
        # SBI format: "01/01/2024    TRANSACTION DESCRIPTION    500.00 Dr    10000.00"
        # Also handle: "01-01-2024" format
        next unless line =~ /\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/

        parts = line.split(/\s{2,}/)
        next unless parts.length >= 3

        date = parse_date(parts[0])
        next unless date

        amount = parse_amount(parts[2])
        next unless amount

        description = clean_description(parts[1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "SBI Transaction",
          notes: "Imported from SBI statement"
        }
      end

      transactions
    end
  end
end
