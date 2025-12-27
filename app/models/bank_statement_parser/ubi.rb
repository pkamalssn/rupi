# frozen_string_literal: true

module BankStatementParser
  class Ubi < Base
    # Union Bank of India statement parser

    def parse
      if excel_file?
        parse_excel
      elsif pdf_file?
        text = if password_protected? && password.present?
          decrypt_pdf_and_extract_text
        elsif scanned_pdf?
          extract_text_with_ocr
        else
          extract_text_from_pdf
        end
        parse_transactions_from_text(text)
      else
        raise UnsupportedFormatError, "Unsupported file format for UBI"
      end
    rescue => e
      raise ParseError, "Failed to parse UBI statement: #{e.message}"
    end

    private

    def excel_file?
      return true if file.respond_to?(:filename) && file.filename.to_s.match?(/\.xlsx?$/i)
      return false unless file.respond_to?(:content_type)
      file.content_type&.include?("excel") || file.content_type&.include?("spreadsheet")
    end

    def parse_excel
      require "roo"
      spreadsheet = Roo::Spreadsheet.open(file_path)
      parse_transactions_from_spreadsheet(spreadsheet)
    end

    def parse_transactions_from_spreadsheet(spreadsheet)
      transactions = []
      header_found = false
      column_map = {}

      spreadsheet.each_with_index do |row, idx|
        unless header_found
          row_str = row.map(&:to_s).join(" ").downcase
          if row_str.include?("date") || row_str.include?("transaction") || row_str.include?("particulars")
            header_found = true
            row.each_with_index do |cell, col_idx|
              cell_str = cell.to_s.downcase
              column_map[:date] = col_idx if cell_str.match?(/date|txn date|value date/i)
              column_map[:description] = col_idx if cell_str.match?(/description|narration|particulars/i)
              column_map[:debit] = col_idx if cell_str.match?(/debit|withdrawal|dr/i)
              column_map[:credit] = col_idx if cell_str.match?(/credit|deposit|cr/i)
              column_map[:balance] = col_idx if cell_str.match?(/balance/i)
            end
          end
          next
        end

        next if row.compact.empty?

        date = parse_date(row[column_map[:date] || 0])
        next unless date

        debit = parse_amount(row[column_map[:debit]]) if column_map[:debit]
        credit = parse_amount(row[column_map[:credit]]) if column_map[:credit]
        
        amount = if debit && debit != 0
          -debit.abs
        elsif credit && credit != 0
          credit.abs
        end
        
        next unless amount && amount != 0

        description = clean_description(row[column_map[:description] || 1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "UBI Transaction",
          notes: "Imported from Union Bank of India statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")

      lines.each do |line|
        # UBI formats: 
        # "01-01-2024  Description  1000.00 Dr  50000.00"
        # "01/01/2024  Description  1000.00  Cr  51000.00"
        # "01-Jan-2024  Description  1000.00  51000.00"
        
        # Check for date patterns
        next unless line.match?(/\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/) || 
                    line.match?(/\d{1,2}[-\/][A-Za-z]{3}[-\/]\d{2,4}/)
        
        # Ignore header lines
        next if line.match?(/Statement.*Date|Statement.*Period|Balance.*Brought|Page.*of/i)
        
        # Extract date
        date_match = line.match(/(\d{1,2}[-\/][A-Za-z]{3}[-\/]\d{2,4})/) ||
                     line.match(/(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})/)
        next unless date_match
        
        date = parse_date(date_match[1])
        next unless date
        
        # Extract amounts
        amounts = line.scan(/([\d,]+\.?\d*)/).flatten.select { |a| a.match?(/\d/) && a.length > 2 }
        next if amounts.empty?
        
        # Check for Dr/Cr indicators
        if dr_match = line.match(/([\d,]+\.?\d*)\s*(Dr|Debit)/i)
          amount = -parse_amount(dr_match[1]).abs
        elsif cr_match = line.match(/([\d,]+\.?\d*)\s*(Cr|Credit)/i)
          amount = parse_amount(cr_match[1]).abs
        else
          amount = parse_amount(amounts.first)
          # Infer from keywords
          is_debit = line.downcase.match?(/withdrawal|neft\/|imps\/|upi\/|atm|debit/)
          amount = -amount.abs if is_debit && amount
        end
        
        next unless amount && amount != 0

        # Extract description
        description = line.sub(date_match[0], "").strip
        description = description.gsub(/([\d,]+\.?\d*)\s*(Dr|Cr|Debit|Credit)?/i, "").strip
        description = clean_description(description)

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "UBI Transaction",
          notes: "Imported from Union Bank of India statement"
        }
      end

      transactions
    end
  end
end
