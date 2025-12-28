# frozen_string_literal: true

module BankStatementParser
  class Scapia < Base
    # Scapia (Federal Bank) Credit Card statement parser
    # Handles .numbers (Apple Numbers) and CSV formats
    
    def parse
      if numbers_file?
        # .numbers files need to be converted to CSV first
        parse_numbers_file
      elsif csv_file?
        parse_csv
      elsif excel_file?
        parse_excel
      elsif pdf_file?
        text = scanned_pdf? ? extract_text_with_ocr : extract_text_from_pdf
        parse_transactions_from_text(text)
      else
        raise UnsupportedFormatError, "Unsupported format. Scapia supports Numbers, CSV, Excel, or PDF"
      end
    rescue => e
      raise ParseError, "Failed to parse Scapia statement: #{e.message}"
    end

    private

    def numbers_file?
      return true if file.respond_to?(:filename) && file.filename.to_s.match?(/\.numbers$/i)
      false
    end

    def csv_file?
      return true if file.respond_to?(:filename) && file.filename.to_s.match?(/\.csv$/i)
      return false unless file.respond_to?(:content_type)
      file.content_type&.include?("csv")
    end

    def excel_file?
      return true if file.respond_to?(:filename) && file.filename.to_s.match?(/\.xlsx?$/i)
      return false unless file.respond_to?(:content_type)
      file.content_type&.include?("excel") || file.content_type&.include?("spreadsheet")
    end

    def parse_numbers_file
      # Apple Numbers files are actually ZIP archives
      # For now, we'll ask user to export as CSV
      # In future, we could use a gem like 'numbers' or unzip and parse
      
      raise UnsupportedFormatError, 
        "Apple Numbers (.numbers) files need to be exported to CSV first. " \
        "Please open in Numbers and File > Export To > CSV, then upload the CSV file."
    end

    def parse_csv
      require "csv"
      transactions = []
      
      CSV.foreach(file_path, headers: true, liberal_parsing: true) do |row|
        # Scapia CSV columns may vary
        date = parse_date(row["Date"] || row["Transaction Date"] || row.values.first)
        next unless date

        amount = parse_amount(row["Amount"] || row["Transaction Amount"])
        next unless amount && amount != 0
        
        # Scapia treats purchases as positive, payments as negative
        # We want purchases (debits) as negative
        description = row["Description"] || row["Merchant"] || row["Details"] || ""
        is_payment = description.downcase.match?(/payment|credit|refund/)
        amount = -amount.abs unless is_payment

        transactions << {
          date: date,
          amount: amount,
          description: clean_description(description).presence || "Scapia Transaction",
          notes: "Imported from Scapia statement"
        }
      end

      transactions
    end

    def parse_excel
      require "roo"
      spreadsheet = Roo::Spreadsheet.open(file_path)
      
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
              column_map[:description] = col_idx if cell_str.match?(/description|merchant|details/i)
              column_map[:amount] = col_idx if cell_str.match?(/amount/i)
            end
          end
          next
        end

        next if row.compact.empty?

        date = parse_date(row[column_map[:date] || 0])
        next unless date

        amount = parse_amount(row[column_map[:amount]])
        next unless amount && amount != 0

        description = clean_description(row[column_map[:description] || 1])
        is_payment = description.downcase.match?(/payment|credit|refund/)
        amount = -amount.abs unless is_payment

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Scapia Transaction",
          notes: "Imported from Scapia statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")
      
      # ==========================================
      # METADATA EXTRACTION - Credit Card Specific
      # ==========================================
      if match = text.match(/Total Amount Due.*?([\d,]+\.\d{2})/im)
        @metadata[:total_due] = parse_amount(match[1])
        @metadata[:closing_balance] = @metadata[:total_due]
      end
      
      if match = text.match(/Minimum.*?Due.*?([\d,]+\.\d{2})/im)
        @metadata[:minimum_due] = parse_amount(match[1])
      end
      
      if match = text.match(/Payment.*?Due.*?Date.*?(\d{1,2}\s*\w+\s*\d{4})/im)
        @metadata[:payment_due_date] = parse_date(match[1])
      end
      
      if match = text.match(/Previous.*?Balance.*?([\d,]+\.\d{2})/im)
        @metadata[:opening_balance] = parse_amount(match[1])
      end

      lines.each do |line|
        next unless line.match?(/\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/)
        
        if match = line.match(/(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})/)
          date = parse_date(match[1])
          next unless date
          
          amounts = line.scan(/([\d,]+\.\d{2})/).flatten
          next if amounts.empty?
          
          amount = BigDecimal(amounts.first.gsub(",", ""))
          is_payment = line.downcase.match?(/payment|credit|refund/)
          amount = -amount unless is_payment

          description = line.sub(match[0], "").gsub(/([\d,]+\.\d{2})/, "").strip
          description = clean_description(description)

          transactions << {
            date: date,
            amount: amount,
            description: description.presence || "Scapia Transaction",
            notes: "Imported from Scapia statement"
          }
        end
      end

      transactions
    end
  end
end
