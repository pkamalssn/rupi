# frozen_string_literal: true

require_relative "base"

module BankStatementParser
  class Kotak < Base
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
      raise ParseError, "Failed to parse Kotak statement: #{e.message}"
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

        # Kotak may have withdrawal/deposit columns
        withdrawal = parse_amount(row[2])
        deposit = parse_amount(row[3])

        amount = if withdrawal && withdrawal != 0
                   -withdrawal.abs
                 elsif deposit && deposit != 0
                   deposit.abs
                 else
                   next
                 end

        description = clean_description(row[1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Kotak Transaction",
          notes: "Imported from Kotak statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []

      lines = text.split("\n")
      
      # Extract metadata - Kotak format: "Opening Balance : 2,261.51(Cr)"
      lines.each do |line|
        if match = line.match(/Opening Balance.*?([\d,]+\.\d{2})/i)
          @metadata[:opening_balance] = parse_amount(match[1])
        end
        if match = line.match(/Closing Balance.*?([\d,]+\.\d{2})/i)
          @metadata[:closing_balance] = parse_amount(match[1])
        end
      end
      
      lines.each do |line|
        # Kotak format patterns:
        # Old: "01 Jan 2024    TRANSACTION    500.00"
        # New: "22-07-2025   UPI/KAMAL...   15,000.00(Dr)"
        
        # Check for date patterns
        has_date = line =~ /\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/ ||          # 22-07-2025 or 22/07/2025
                   line =~ /\d{1,2}\s+[A-Za-z]{3}\s+\d{2,4}/ ||           # 01 Jan 2024
                   line =~ /\d{1,2}-[A-Za-z]{3}-\d{2,4}/                   # 01-Jan-2024
        
        next unless has_date
        next unless line =~ /[\d,]+\.?\d*/ # Must have amount numbers

        # Extract the date from the beginning of the line
        date_match = line.match(/^(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})/) ||
                     line.match(/^(\d{1,2}\s+[A-Za-z]{3}\s+\d{2,4})/) ||
                     line.match(/^(\d{1,2}-[A-Za-z]{3}-\d{2,4})/)
        
        next unless date_match
        date = parse_date(date_match[1])
        next unless date

        # Extract amount - look for numbers with optional Dr/Cr indicator
        # Kotak format: "15,000.00(Dr)" or "15,000.00(Cr)"
        amount = nil
        is_debit = nil
        
        if amt_match = line.match(/([\d,]+\.?\d*)\s*\(?(Dr|Cr)\)?/i)
          amount = parse_amount(amt_match[1])
          is_debit = amt_match[2].downcase == "dr"
        elsif amt_match = line.match(/([\d,]+\.\d{2})/)
          amount = parse_amount(amt_match[1])
          # Infer from description
          is_debit = line =~ /UPI\/|NEFT\/|IMPS\/|ATM|DEBIT|Chg:|CHG:/i
        end
        
        next unless amount && amount > 0

        # Make debits negative
        amount = -amount if is_debit

        # Extract description - text between date and amount
        description = line.sub(date_match[0], "").strip
        description = description.sub(/([\d,]+\.?\d*)\s*\(?(Dr|Cr)\)?.*$/i, "").strip
        description = clean_description(description)

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Kotak Transaction",
          notes: "Imported from Kotak statement"
        }
      end

      transactions
    end
  end
end
