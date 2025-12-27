# frozen_string_literal: true

require_relative "base"

module BankStatementParser
  # Generic parser for other Indian banks with standard formats
  class Generic < Base
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
      raise ParseError, "Failed to parse statement: #{e.message}"
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

      # Try various column mappings
      spreadsheet.each_with_index do |row, idx|
        next if idx == 0

        # Try to find date in first few columns
        date = nil
        (0..3).each do |col_idx|
          date = parse_date(row[col_idx])
          break if date
        end
        next unless date

        # Try to find amount
        amount = nil
        (0..5).each do |col_idx|
          val = row[col_idx]
          next unless val.is_a?(String) && val.match(/[\d,]+\.\d{2}/)

          amount = parse_amount(val)
          break if amount
        end
        next unless amount

        # Everything else is description
        description_parts = row.select { |v| v.is_a?(String) && v.length > 5 && !v.match(/^\d/) }
        description = clean_description(description_parts.first || "Bank Transaction")

        transactions << {
          date: date,
          amount: amount,
          description: description,
          notes: "Imported from bank statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []

      lines = text.split("\n")

      # Try multiple date formats
      date_patterns = [
        /(\d{1,2}[-\/]\d{1,2}[-\/]\d{4})/,
        /(\d{1,2}\s+[A-Za-z]{3}\s+\d{4})/,
        /(\d{4}[-\/]\d{1,2}[-\/]\d{1,2})/
      ]

      lines.each do |line|
        # Skip lines without dates
        next unless date_patterns.any? { |pattern| line.match(pattern) }

        # Extract date
        date = nil
        date_patterns.each do |pattern|
          match = line.match(pattern)
          if match
            date = parse_date(match[1])
            break if date
          end
        end
        next unless date

        # Extract amount - look for numbers with 2 decimal places
        amount_matches = line.scan(/([\d,]+\.\d{2})/)
        next unless amount_matches.any?

        # Use the last amount (usually the transaction amount)
        amount = parse_amount(amount_matches.last)
        next unless amount && amount != 0

        # Extract description - remove date and amount, take what's left
        description = line
        date_patterns.each { |pattern| description = description.sub(pattern, "") }
        amount_matches.each { |match| description = description.sub(match, "") }
        description = clean_description(description).presence || "Bank Transaction"

        transactions << {
          date: date,
          amount: amount,
          description: description,
          notes: "Imported from bank statement"
        }
      end

      transactions
    end
  end
end
