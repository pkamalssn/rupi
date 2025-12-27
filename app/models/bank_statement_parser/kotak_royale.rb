# frozen_string_literal: true

module BankStatementParser
  class KotakRoyale < Base
    # Kotak Royale Credit Card statement parser
    
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
      raise ParseError, "Failed to parse Kotak Royale statement: #{e.message}"
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
      
      current_date = nil
      
      lines.each do |line|
        next if line.strip.empty?
        next if line.match?(/^(statement|page|total|minimum|limit|available)/i)
        
        # Look for date patterns
        if match = line.match(/(\d{1,2}[\/\-][A-Za-z]{3}[\/\-]\d{2,4})|(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/)
          parsed_date = parse_date(match[0])
          current_date = parsed_date if parsed_date
        end
        
        next unless current_date

        # Extract amount
        if amount_match = line.match(/([\d,]+\.\d{2})\s*(Cr|Dr)?/i)
          amount = BigDecimal(amount_match[1].gsub(",", ""))
          
          is_credit = amount_match[2]&.downcase == "cr" ||
                      line.downcase.match?(/credit|refund|cashback|reversal/)
          
          amount = -amount unless is_credit

          description = extract_description(line, amount_match[0])

          transactions << {
            date: current_date,
            amount: amount,
            description: description.presence || "Kotak Royale Transaction",
            notes: "Imported from Kotak Royale Credit Card statement"
          }
        end
      end

      transactions.uniq { |t| [t[:date], t[:amount].to_s, t[:description]] }
    end

    def extract_description(line, amount_match)
      desc = line.dup
      desc = desc.gsub(/\d{1,2}[\/\-][A-Za-z]{3}[\/\-]\d{2,4}/, "")
      desc = desc.gsub(/\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/, "")
      desc = desc.sub(amount_match, "")
      desc = desc.gsub(/\s*(Cr|Dr)\s*/i, "")
      clean_description(desc)
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
        
        # Check type column or description for credit indicator
        is_credit = false
        if column_map[:type]
          is_credit = row[column_map[:type]].to_s.downcase.include?("cr")
        end
        is_credit ||= description.downcase.match?(/credit|refund|cashback/)
        
        amount = -amount.abs unless is_credit

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Kotak Royale Transaction",
          notes: "Imported from Kotak Royale Credit Card statement"
        }
      end

      transactions
    end
  end
end
