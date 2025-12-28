# frozen_string_literal: true

module BankStatementParser
  class Wise < Base
    # Wise (TransferWise) statement parser
    # Supports EUR, USD, GBP, INR statements
    
    def parse
      if pdf_file?
        text = if scanned_pdf?
          extract_text_with_ocr
        elsif password_protected? && password.present?
          decrypt_pdf_and_extract_text
        else
          extract_text_from_pdf
        end
        parse_transactions_from_text(text)
      elsif csv_file?
        parse_csv
      else
        raise UnsupportedFormatError, "Unsupported file format for Wise"
      end
    rescue PasswordRequiredError
      raise
    rescue => e
      raise ParseError, "Failed to parse Wise statement: #{e.message}"
    end

    # Returns the currency detected in the statement
    attr_reader :detected_currency

    private

    def csv_file?
      return true if file.respond_to?(:filename) && file.filename.to_s.match?(/\.csv$/i)
      return false unless file.respond_to?(:content_type)
      file.content_type&.include?("csv")
    end

    def parse_csv
      require "csv"
      transactions = []
      
      CSV.foreach(file_path, headers: true) do |row|
        date = parse_date(row["Date"] || row["date"] || row["Created"])
        next unless date

        amount = parse_amount(row["Amount"] || row["amount"])
        next unless amount && amount != 0

        description = row["Description"] || row["description"] || row["Merchant"] || ""
        description = clean_description(description)

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Wise Transaction",
          notes: "Imported from Wise statement",
          currency: row["Currency"] || "EUR"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []
      
      # Detect currency from statement header
      @detected_currency = if text.include?("EUR statement") || text.include?("EUR balance")
        "EUR"
      elsif text.include?("USD statement") || text.include?("USD balance")
        "USD"
      elsif text.include?("GBP statement") || text.include?("GBP balance")
        "GBP"
      elsif text.include?("INR statement") || text.include?("INR balance")
        "INR"
      else
        "EUR" # Default for Wise Europe
      end
      
      # ==========================================
      # METADATA EXTRACTION
      # ==========================================
      # Wise format: "Opening balance XX.XX" and "Closing balance XX.XX"
      if match = text.match(/Opening balance.*?([\d,]+\.\d{2})/im)
        @metadata[:opening_balance] = parse_amount(match[1])
      end
      if match = text.match(/Closing balance.*?([\d,]+\.\d{2})/im)
        @metadata[:closing_balance] = parse_amount(match[1])
      end
      # Also try alternate format
      if @metadata[:opening_balance].nil? && (match = text.match(/Balance on [\w\s]+ \d{4}.*?([\d,]+\.\d{2})/im))
        @metadata[:opening_balance] = parse_amount(match[1])
      end

      # Wise PDF format parsing
      # The format has transaction blocks like:
      # "Card transaction of EUR issued by Wolt Helsinki"
      # "                                        -15.66       107.53"
      # "17 June 2025 Card ending in 0357 DIVYA BHARATHI KAMAL"
      
      lines = text.split("\n")
      
      i = 0
      while i < lines.length
        line = lines[i].strip
        
        # Look for transaction description lines
        if line.match?(/^(Card transaction|Sent money|Received money|Added money|Converted|Transfer|Direct Debit)/i)
          description = line
          
          # Look for the amount on next lines
          amount = nil
          date = nil
          
          # Search next 5 lines for amount and date
          (1..5).each do |j|
            next if i + j >= lines.length
            next_line = lines[i + j].strip
            
            # Look for amount pattern: negative or positive numbers
            if !amount && (amt_match = next_line.match(/^\s*(-?[\d,]+\.\d{2})\s+(-?[\d,]+\.\d{2})?/))
              # First number is usually the transaction amount, second is balance
              amount_str = amt_match[1]
              amount = BigDecimal(amount_str.gsub(",", ""))
            end
            
            # Alternative: look for amount in the line with Incoming/Outgoing pattern
            if !amount && (amt_match = next_line.match(/-?([\d,]+\.\d{2})\s+([\d,]+\.\d{2})/))
              # Check if first amount is the change (could be incoming or outgoing)
              amount_str = amt_match[1]
              amount = BigDecimal(amount_str.gsub(",", ""))
              # Negative if "Sent" or "Card transaction"
              amount = -amount if description.downcase.match?(/sent|card transaction|direct debit|transfer.*to/)
            end
            
            # Look for date pattern
            if !date && (date_match = next_line.match(/(\d{1,2}\s+[A-Za-z]+\s+\d{4})/))
              date = parse_date(date_match[1])
            end
          end
          
          if date && amount && amount != 0
            # Clean description
            clean_desc = description.sub(/^(Card transaction of \w+ issued by|Sent money to|Received money from|Added money from|Converted \w+ to \w+)/i, "").strip
            clean_desc = description if clean_desc.blank?
            clean_desc = clean_description(clean_desc)
            
            transactions << {
              date: date,
              amount: amount,
              description: clean_desc.presence || "Wise Transaction",
              notes: "Imported from Wise #{@detected_currency} statement",
              currency: @detected_currency
            }
          end
        end
        
        i += 1
      end
      
      # If above method found few transactions, try line-by-line approach
      if transactions.count < 5
        transactions = parse_line_by_line(text)
      end

      transactions
    end

    def parse_line_by_line(text)
      transactions = []
      lines = text.split("\n")
      
      current_date = nil
      
      lines.each_with_index do |line, idx|
        # Extract date when we see it
        if date_match = line.match(/(\d{1,2}\s+[A-Za-z]+\s+\d{4})/)
          parsed = parse_date(date_match[1])
          current_date = parsed if parsed && parsed.year > 2000
        end
        
        # Look for transaction amounts
        # Pattern: -15.66 or +50.00 followed by balance
        if current_date && (amt_match = line.match(/^\s*(-?[\d,]+\.\d{2})\s+[\d,]+\.\d{2}\s*$/))
          amount = BigDecimal(amt_match[1].gsub(",", ""))
          next if amount == 0
          
          # Get description from previous lines
          desc = ""
          (-3..-1).each do |offset|
            prev_idx = idx + offset
            next if prev_idx < 0
            prev_line = lines[prev_idx].strip
            if prev_line.length > 10 && !prev_line.match?(/^\s*-?[\d,]+\.\d{2}/)
              desc = prev_line
              break
            end
          end
          
          transactions << {
            date: current_date,
            amount: amount,
            description: clean_description(desc).presence || "Wise Transaction",
            notes: "Imported from Wise #{@detected_currency || 'EUR'} statement",
            currency: @detected_currency || "EUR"
          }
        end
      end
      
      transactions
    end
  end
end
