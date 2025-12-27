# frozen_string_literal: true

module BankStatementParser
  class Jupiter < Base
    def parse
      if excel_file?
        parse_excel
      elsif pdf_file?
        text = extract_text_from_pdf
        parse_transactions_from_text(text)
      else
        raise UnsupportedFormatError, "Unsupported format for Jupiter statement"
      end
    rescue => e
      raise ParseError, "Failed to parse Jupiter statement: #{e.message}"
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
          if row_str.include?("date") || row_str.include?("transaction")
            header_found = true
            row.each_with_index do |cell, col_idx|
              cell_str = cell.to_s.downcase
              column_map[:date] = col_idx if cell_str.match?(/date/i)
              column_map[:description] = col_idx if cell_str.match?(/description|narration|details/i)
              column_map[:amount] = col_idx if cell_str.match?(/amount/i)
              column_map[:type] = col_idx if cell_str.match?(/type|dr.*cr/i)
              column_map[:debit] = col_idx if cell_str.match?(/debit/i)
              column_map[:credit] = col_idx if cell_str.match?(/credit/i)
            end
          end
          next
        end

        next if row.compact.empty?

        date = parse_date(row[column_map[:date] || 0])
        next unless date

        amount = determine_amount(row, column_map)
        next unless amount && amount != 0

        description = clean_description(row[column_map[:description] || 1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Jupiter Transaction",
          notes: "Imported from Jupiter statement"
        }
      end

      transactions
    end

    def determine_amount(row, column_map)
      if column_map[:debit] && column_map[:credit]
        debit = parse_amount(row[column_map[:debit]])
        credit = parse_amount(row[column_map[:credit]])
        if debit && debit != 0
          -debit.abs
        elsif credit && credit != 0
          credit.abs
        end
      elsif column_map[:amount]
        amount = parse_amount(row[column_map[:amount]])
        if column_map[:type]
          type_str = row[column_map[:type]].to_s.downcase
          amount = -amount.abs if type_str.include?("dr") || type_str.include?("debit")
        end
        amount
      end
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")

      lines.each do |line|
        # Jupiter/Federal Bank PDF formats:
        # "01-Jan-2025  Description  1000.00 Dr  50000.00"
        # "01/01/2025   Description  1000.00     50000.00"
        
        # Check for date patterns
        next unless line.match?(/\d{1,2}[-\/][A-Za-z]{3}[-\/]\d{2,4}/) || 
                    line.match?(/\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/)
        
        # Extract date
        date_match = line.match(/(\d{1,2}-[A-Za-z]{3}-\d{2,4})/) ||
                     line.match(/(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})/)
        next unless date_match
        
        date = parse_date(date_match[1])
        next unless date
        
        # Extract amounts
        amounts = line.scan(/([\d,]+\.\d{2})/).flatten
        next if amounts.empty?
        
        # Determine if debit or credit
        amount = parse_amount(amounts.first)
        next unless amount && amount > 0
        
        is_debit = line.upcase.match?(/\bDR\b|DEBIT|UPI\/|NEFT\/|IMPS\/|WITHDRAWAL/)
        is_credit = line.upcase.match?(/\bCR\b|CREDIT|DEPOSIT|SALARY|INTEREST/)
        
        if is_debit && !is_credit
          amount = -amount.abs
        elsif is_credit
          amount = amount.abs
        else
          # Default to debit for unknown
          amount = -amount.abs
        end

        # Extract description
        description = line.sub(date_match[0], "").strip
        description = description.gsub(/([\d,]+\.\d{2})/, "").gsub(/\b(Dr|Cr)\b/i, "").strip
        description = clean_description(description)

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Jupiter Transaction",
          notes: "Imported from Jupiter/Federal Bank statement"
        }
      end

      transactions
    end
  end
end
