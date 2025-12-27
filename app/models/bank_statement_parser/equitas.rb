# frozen_string_literal: true

module BankStatementParser
  class Equitas < Base
    def parse
      if excel_file?
        parse_excel
      elsif pdf_file?
        text = scanned_pdf? ? extract_text_with_ocr : extract_text_from_pdf
        parse_transactions_from_text(text)
      else
        raise UnsupportedFormatError, "Unsupported file format for Equitas"
      end
    rescue => e
      raise ParseError, "Failed to parse Equitas statement: #{e.message}"
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
          if row_str.include?("date") || row_str.include?("transaction") || row_str.include?("txn")
            header_found = true
            row.each_with_index do |cell, col_idx|
              cell_str = cell.to_s.downcase
              column_map[:date] = col_idx if cell_str.match?(/date|txn/i)
              column_map[:description] = col_idx if cell_str.match?(/description|narration|particulars/i)
              column_map[:debit] = col_idx if cell_str.match?(/debit|withdrawal/i)
              column_map[:credit] = col_idx if cell_str.match?(/credit|deposit/i)
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
          description: description.presence || "Equitas Transaction",
          notes: "Imported from Equitas statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")

      lines.each do |line|
        # Equitas format: "10-Apr-2025  UPIFIN...  UPI REF NO...  50000.00  (empty)  171754.20"
        # Check for date patterns: dd-MMM-yyyy or dd-mm-yyyy or dd/mm/yyyy
        next unless line.match?(/\d{1,2}[-\/][A-Za-z]{3}[-\/]\d{4}/) || 
                    line.match?(/\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/)
        
        # Extract date
        date_match = line.match(/(\d{1,2}-[A-Za-z]{3}-\d{4})/) ||
                     line.match(/(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})/)
        next unless date_match
        
        date = parse_date(date_match[1])
        next unless date
        
        # Extract amounts - look for numbers that look like currency
        amounts = line.scan(/([\d,]+\.\d{2})/).flatten
        next if amounts.empty?
        
        # Determine if this is a credit or debit based on keywords
        line_upper = line.upcase
        is_credit = line_upper.match?(/CREDIT INTEREST|NEFT CR|RTGS CR|IMPS CR|\bCR[- ]|DEPOSIT|SALARY|CREDITED/)
        is_debit = line_upper.match?(/P2P-|P2M-|P2A-|ATM|WITHDRAWAL|DEBIT|DEBITED|NEFT DR|RTGS DR|IMPS DR|\bDR[- ]|CARD AMC/)
        
        # Get the first amount (transaction amount, not balance)
        amount = parse_amount(amounts.first)
        next unless amount && amount > 0
        
        # Apply sign based on detected direction
        if is_credit && !is_debit
          # It's a credit (money coming in)
          amount = amount.abs
        elsif is_debit || (!is_credit && amounts.length >= 2)
          # It's a debit (money going out) - default for most UPI transactions
          amount = -amount.abs
        else
          # Unclear - default to debit for safety
          amount = -amount.abs
        end
        
        next if amount == 0

        # Extract description - the narration part
        description = line.sub(date_match[0], "").strip
        # Remove reference numbers and amounts
        description = description.gsub(/UPIFIN\d+/, "").gsub(/[\d,]+\.\d{2}/, "").strip
        description = clean_description(description)

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Equitas Transaction",
          notes: "Imported from Equitas statement"
        }
      end

      transactions
    end
  end
end
