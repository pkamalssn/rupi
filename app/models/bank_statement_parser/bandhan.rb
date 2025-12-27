# frozen_string_literal: true

module BankStatementParser
  class Bandhan < Base
    def parse
      if excel_file?
        parse_excel
      elsif pdf_file?
        text = scanned_pdf? ? extract_text_with_ocr : extract_text_from_pdf
        parse_transactions_from_text(text)
      else
        raise UnsupportedFormatError, "Unsupported file format for Bandhan"
      end
    rescue => e
      raise ParseError, "Failed to parse Bandhan statement: #{e.message}"
    end

    private

    def excel_file?
      return false unless file.respond_to?(:content_type)
      file.content_type&.include?("excel") || 
        file.content_type&.include?("spreadsheet") ||
        file.respond_to?(:filename) && file.filename.to_s.match?(/\.xlsx?$/i)
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
        # Find header row
        unless header_found
          row_str = row.map(&:to_s).join(" ").downcase
          if row_str.include?("date") || row_str.include?("transaction")
            header_found = true
            row.each_with_index do |cell, col_idx|
              cell_str = cell.to_s.downcase
              column_map[:date] = col_idx if cell_str.match?(/date|txn.*date/i)
              column_map[:description] = col_idx if cell_str.match?(/narration|description|particulars|remarks/i)
              column_map[:debit] = col_idx if cell_str.match?(/debit|withdrawal|dr/i)
              column_map[:credit] = col_idx if cell_str.match?(/credit|deposit|cr/i)
              column_map[:amount] = col_idx if cell_str.match?(/^amount$/i)
            end
          end
          next
        end

        next if row.compact.empty?

        date = parse_date(row[column_map[:date] || 0])
        next unless date

        # Handle separate debit/credit columns or single amount column
        amount = if column_map[:debit] && column_map[:credit]
          debit = parse_amount(row[column_map[:debit]])
          credit = parse_amount(row[column_map[:credit]])
          if debit && debit != 0
            -debit.abs
          elsif credit && credit != 0
            credit.abs
          end
        elsif column_map[:amount]
          parse_amount(row[column_map[:amount]])
        end
        
        next unless amount && amount != 0

        description = clean_description(row[column_map[:description] || 1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Bandhan Transaction",
          notes: "Imported from Bandhan statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")

      lines.each do |line|
        next unless line.match?(/\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/)
        
        if match = line.match(/(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})/)
          date = parse_date(match[1])
          next unless date
          
          amounts = line.scan(/([\d,]+\.\d{2})/).flatten
          next if amounts.empty?
          
          amount = BigDecimal(amounts.first.gsub(",", ""))
          is_debit = line.downcase.match?(/dr|debit|withdrawal/)
          amount = -amount if is_debit

          description = line.sub(match[0], "").gsub(/([\d,]+\.\d{2})/, "").strip
          description = clean_description(description)

          transactions << {
            date: date,
            amount: amount,
            description: description.presence || "Bandhan Transaction",
            notes: "Imported from Bandhan statement"
          }
        end
      end

      transactions
    end
  end
end
