# frozen_string_literal: true

require_relative "base"

module BankStatementParser
  class Axis < Base
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
      raise ParseError, "Failed to parse Axis statement: #{e.message}"
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

        amount = parse_amount(row[2])
        next unless amount

        description = clean_description(row[1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Axis Transaction",
          notes: "Imported from Axis statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []

      lines = text.split("\n")
      lines.each do |line|
        # Axis format varies - try common patterns
        next unless line =~ /\d{1,2}-\d{1,2}-\d{4}/ || line =~ /\d{2}\/\d{2}\/\d{4}/

        parts = line.split(/\s{2,}/)
        next unless parts.length >= 2

        date = parse_date(parts[0])
        next unless date

        # Find amount in the line
        amount_match = line.match(/([\d,]+\.\d{2})/)
        next unless amount_match

        amount = parse_amount(amount_match[1])
        next unless amount

        description = clean_description(parts[1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Axis Transaction",
          notes: "Imported from Axis statement"
        }
      end

      transactions
    end
  end
end
