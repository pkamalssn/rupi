# frozen_string_literal: true

module BankStatementParser
  class KotakRoyale < Base
    # Kotak Credit Card statement parser (Royale, 811, etc.)
    
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
      elsif excel_file?
        parse_excel
      else
        raise UnsupportedFormatError, "Kotak Credit Card statements are typically PDF format"
      end
    rescue PasswordRequiredError
      raise
    rescue => e
      raise ParseError, "Failed to parse Kotak Credit Card statement: #{e.message}"
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

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")
      
      in_transactions = false
      
      # Extract metadata
      if match = text.match(/Total Amount Due.*?([\d,]+\.\d{2})/im)
        @metadata[:total_due] = parse_amount(match[1])
      end
      if match = text.match(/Minimum Amount Due.*?([\d,]+\.\d{2})/im)
        @metadata[:minimum_due] = parse_amount(match[1])
      end
      
      lines.each do |line|
        line = line.strip
        next if line.empty?
        
        # Detect start of transaction section
        if line.match?(/Transaction details from/i)
          in_transactions = true
          next
        end
        
        # Skip non-transaction lines
        next unless in_transactions
        
        # Skip section headers and summary lines
        next if line.match?(/^(Date|Statement|Page|Total|Minimum|Limit|Available|Customer|Primary|GSTIN|Rs\.\s*-)/i)
        next if line.match?(/^(EMI and Loans|Other Fees|Purchase \& Other)/i)
        next if line.match?(/SMS EMI|Payment of only|month shall/i)
        next if line.match?(/Credit Limit|Cash Limit|Outstanding|Payable/i)
        next if line.match?(/^[A-Z]{4}\s+XXXX|Card Number/i)
        
        # Line must start with date: DD/MM/YYYY
        next unless date_match = line.match(/^(\d{2}\/\d{2}\/\d{4})\s+/)
        
        date = parse_date(date_match[1])
        next unless date
        
        # Skip if date is unrealistic (future year > 2026)
        next if date.year > 2026
        
        # Extract amount at the end - pattern: number with optional Cr
        amounts = line.scan(/([\d,]+\.\d{2})(\s*Cr)?/i)
        next if amounts.empty?
        
        # Last amount is the transaction amount
        amount_str, cr_indicator = amounts.last
        amount = parse_amount(amount_str)
        next unless amount && amount > 0
        
        # Credits have "Cr" suffix (refunds, surcharge waivers)
        is_credit = cr_indicator&.strip&.downcase == "cr" ||
                    line.downcase.match?(/waiver|reversal|refund|cashback/)
        
        # For credit card: purchases are negative
        if is_credit
          amount = amount.abs
        else
          amount = -amount.abs
        end
        
        # Extract description between date and amount
        description = line.sub(date_match[0], "").strip
        # Remove all amounts including Cr
        description = description.gsub(/[\d,]+\.\d{2}(\s*Cr)?/i, "")
        # Remove spending category (single word at end before amount like "Fuel", "Food")
        description = description.gsub(/\s+(Fuel|Food|Shopping|Automotive|Travel|Entertainment|Utilities|Other)\s*$/i, "")
        # Remove EMI conversion text
        description = description.gsub(/\*Convert to EMI\*?/i, "")
        description = clean_description(description)
        
        # Skip fee/charges that are just descriptions
        next if description.match?(/^\s*GST\s*$/i) && amount.abs < 1000
        
        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Kotak CC Transaction",
          notes: "Imported from Kotak Credit Card statement"
        }
      end

      transactions.uniq { |t| [t[:date], t[:amount].to_s, t[:description]] }
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
              column_map[:description] = col_idx if cell_str.match?(/description|details|merchant/i)
              column_map[:amount] = col_idx if cell_str.match?(/amount/i)
              column_map[:type] = col_idx if cell_str.match?(/type|cr.*dr/i)
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
        
        is_credit = false
        if column_map[:type]
          is_credit = row[column_map[:type]].to_s.downcase.include?("cr")
        end
        is_credit ||= description.downcase.match?(/credit|refund|cashback|waiver/)
        
        amount = -amount.abs unless is_credit

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Kotak CC Transaction",
          notes: "Imported from Kotak Credit Card statement"
        }
      end

      transactions
    end
  end
end
