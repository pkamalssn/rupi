# frozen_string_literal: true

module BankStatementParser
  class Hdfc < Base
    def parse
      transactions = []

      if pdf_file?
        # Check password protection FIRST before any other checks
        text = if password_protected?
          if password.present?
            decrypt_pdf_and_extract_text
          else
            raise PasswordRequiredError, "Password required for this PDF"
          end
        elsif scanned_pdf?
          extract_text_with_ocr
        else
          extract_text_from_pdf
        end
        transactions = parse_transactions_from_text(text)
      elsif excel_file?
        transactions = parse_excel
      else
        raise UnsupportedFormatError, "Unsupported file format: #{file.content_type}"
      end

      transactions
    rescue PasswordRequiredError
      raise
    rescue => e
      raise ParseError, "Failed to parse HDFC statement: #{e.message}"
    end

    private

    def excel_file?
      return false unless file.respond_to?(:content_type)
      %w[application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet text/csv].include?(file.content_type)
    end

    def parse_excel
      require "roo"

      spreadsheet = case file.content_type
                    when "application/vnd.ms-excel"
                      Roo::Excel.new(file_path)
                    when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                      Roo::Excelx.new(file_path)
                    when "text/csv"
                      Roo::CSV.new(file_path)
                    end

      parse_transactions_from_spreadsheet(spreadsheet)
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")

      lines.each do |line|
        # Skip lines that don't look like transactions
        next unless line.match?(/\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}|\d{1,2}[-\/][A-Za-z]{3}[-\/]\d{2,4}/)
        next unless line.match?(/\d+\.?\d*/) # Must have numbers

        parsed = parse_transaction_line(line)
        transactions << parsed if parsed && parsed[:amount]
      end

      transactions
    end

    def parse_transaction_line(line)
      # HDFC statement formats:
      # "01-Jan-2024    UPI/SWIGGY/DR/...    450.00    Dr       12,345.67"
      # "05/01/24       NEFT credit Salary   50000.00  Cr       62,345.67"
      
      # Extract date (various formats)
      date = nil
      date_patterns = [
        /(\d{1,2}-[A-Za-z]{3}-\d{2,4})/,  # 01-Jan-2024
        /(\d{1,2}\/\d{1,2}\/\d{2,4})/,     # 01/01/2024
        /(\d{1,2}-\d{1,2}-\d{2,4})/,       # 01-01-2024
      ]
      
      date_patterns.each do |pattern|
        if match = line.match(pattern)
          date = parse_date(match[1])
          break if date
        end
      end
      
      return nil unless date

      # Extract amount and Dr/Cr indicator
      # Look for amount followed by Dr/Cr
      amount = nil
      is_debit = nil
      
      if match = line.match(/([\d,]+\.?\d*)\s*(Dr|Cr)/i)
        amount_str, dr_cr = match[1], match[2]
        amount = BigDecimal(amount_str.gsub(",", ""))
        is_debit = dr_cr.downcase == "dr"
      elsif match = line.match(/([\d,]+\.\d{2})/)
        # Just a number without Dr/Cr
        amount = BigDecimal(match[1].gsub(",", ""))
        # Try to infer from description
        is_debit = line.downcase.include?("debit") || line.include?("UPI/") || line.include?("IMPS/")
      end
      
      return nil unless amount

      # Make debits negative (money going out)
      amount = -amount if is_debit

      # Extract description - everything between date and amount
      description = extract_description(line, date_patterns)

      {
        date: date,
        amount: amount,
        description: description.presence || "HDFC Transaction",
        notes: "Imported from HDFC statement"
      }
    end

    def extract_description(line, date_patterns)
      desc = line.dup
      
      # Remove date
      date_patterns.each do |pattern|
        desc = desc.sub(pattern, "")
      end
      
      # Remove amounts and Dr/Cr
      desc = desc.gsub(/[\d,]+\.?\d*\s*(Dr|Cr)?/i, "")
      
      # Clean up
      clean_description(desc)
    end

    def parse_transactions_from_spreadsheet(spreadsheet)
      transactions = []
      header_found = false
      date_col = nil
      desc_col = nil
      debit_col = nil
      credit_col = nil
      
      spreadsheet.each_with_index do |row, idx|
        # Find header row
        unless header_found
          row_str = row.map(&:to_s).join(" ").downcase
          if row_str.include?("date") || row_str.include?("transaction")
            header_found = true
            row.each_with_index do |cell, col_idx|
              cell_str = cell.to_s.downcase
              date_col = col_idx if cell_str.include?("date")
              desc_col = col_idx if cell_str.include?("narration") || cell_str.include?("description") || cell_str.include?("particulars")
              debit_col = col_idx if cell_str.include?("debit") || cell_str.include?("withdrawal")
              credit_col = col_idx if cell_str.include?("credit") || cell_str.include?("deposit")
            end
          end
          next
        end

        # Parse data rows
        next if row.compact.empty?
        
        date = parse_date(row[date_col || 0])
        next unless date

        debit_amt = parse_amount(row[debit_col]) if debit_col
        credit_amt = parse_amount(row[credit_col]) if credit_col
        
        amount = if debit_amt && debit_amt != 0
          -debit_amt.abs
        elsif credit_amt && credit_amt != 0
          credit_amt.abs
        else
          next
        end

        description = clean_description(row[desc_col || 1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "HDFC Transaction",
          notes: "Imported from HDFC statement"
        }
      end

      transactions
    end
  end
end
