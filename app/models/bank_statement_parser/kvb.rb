# frozen_string_literal: true

module BankStatementParser
  class Kvb < Base
    # KVB = Karur Vysya Bank
    
    def parse
      if excel_file?
        parse_excel
      elsif pdf_file?
        text = scanned_pdf? ? extract_text_with_ocr : extract_text_from_pdf
        parse_transactions_from_text(text)
      else
        raise UnsupportedFormatError, "Unsupported file format for KVB"
      end
    rescue => e
      raise ParseError, "Failed to parse KVB statement: #{e.message}"
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
              column_map[:date] = col_idx if cell_str.match?(/date|txn/i)
              column_map[:description] = col_idx if cell_str.match?(/description|narration|particulars/i)
              column_map[:debit] = col_idx if cell_str.match?(/debit|withdrawal|dr/i)
              column_map[:credit] = col_idx if cell_str.match?(/credit|deposit|cr/i)
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
          description: description.presence || "KVB Transaction",
          notes: "Imported from KVB statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")
      
      # KVB NRE format:
      # Txn Date | Value Date | Particulars | Ref.No. | Debit | Credit | Balance
      # Date format: DD-MMM-YYYY (e.g., "11-DEC-2025")
      # Multi-line transactions possible
      
      # Extract metadata
      if match = text.match(/Current Balance.*?([\d,]+\.\d{2})/im)
        @metadata[:closing_balance] = parse_amount(match[1])
      end
      if match = text.match(/B\/F\.*\s*-\s*-\s*-\s*([\d,]+\.\d{2})/im)
        @metadata[:opening_balance] = parse_amount(match[1])
      end
      
      current_date = nil
      current_description = nil
      pending_line = nil
      
      lines.each_with_index do |line, idx|
        line = line.strip
        next if line.empty?
        
        # Skip header and summary lines
        next if line.match?(/^(Txn Date|ACCOUNT SUMMARY|ACCOUNT STATEMENT|Current Balance|Note:)/i)
        next if line.match?(/^\d+$/)  # Page numbers
        
        # Skip B/F (brought forward) line
        next if line.match?(/B\/F\.\.\./i)
        
        # Date pattern: DD-MMM-YYYY (e.g., "11-DEC-2025")
        date_pattern = /(\d{2}-[A-Z]{3}-\d{4})/i
        
        if match = line.match(date_pattern)
          # This line has a date
          date = parse_date(match[1])
          next unless date
          
          current_date = date
          
          # Extract amounts - look for Debit, Credit, Balance columns
          # Format: "- 500.00 0.00 2,04,274.94" or "- 0.00 469.12 469.12"
          amounts = line.scan(/([\d,]+\.\d{2})/).flatten.map { |a| parse_amount(a) }
          
          if amounts.length >= 3
            # We have Debit, Credit, Balance
            debit = amounts[0]
            credit = amounts[1]
            balance = amounts[2]
            
            if debit && debit > 0
              amount = -debit.abs
            elsif credit && credit > 0
              amount = credit.abs
            else
              next
            end
            
            # Extract description
            description = line.sub(date_pattern, "").strip
            # Remove time patterns like "10:07:46"
            description = description.gsub(/\d{2}:\d{2}:\d{2}/, "")
            # Remove amounts
            description = description.gsub(/[\d,]+\.\d{2}/, "")
            # Remove the second date (Value Date)
            description = description.gsub(date_pattern, "")
            # Remove dashes and cleanup
            description = description.gsub(/\s+-\s+/, " ").strip
            description = clean_description(description)
            
            transactions << {
              date: current_date,
              amount: amount,
              description: description.presence || "KVB Transaction",
              notes: "Imported from KVB statement",
              _balance: balance
            }
          else
            # Multi-line transaction - amounts might be on next line
            pending_line = { date: current_date, text: line }
          end
        elsif pending_line && line.match?(/[\d,]+\.\d{2}/)
          # This is a continuation line with amounts
          amounts = line.scan(/([\d,]+\.\d{2})/).flatten.map { |a| parse_amount(a) }
          
          # Combine with pending line
          combined_text = pending_line[:text] + " " + line
          
          if amounts.length >= 3
            debit = amounts[0]
            credit = amounts[1]
            balance = amounts[2]
            
            if debit && debit > 0
              amount = -debit.abs
            elsif credit && credit > 0
              amount = credit.abs
            else
              pending_line = nil
              next
            end
            
            description = combined_text.gsub(/\d{2}-[A-Z]{3}-\d{4}/i, "").strip
            description = description.gsub(/\d{2}:\d{2}:\d{2}/, "")
            description = description.gsub(/[\d,]+\.\d{2}/, "")
            description = description.gsub(/\s+-\s+/, " ").strip
            description = clean_description(description)
            
            transactions << {
              date: pending_line[:date],
              amount: amount,
              description: description.presence || "KVB Transaction",
              notes: "Imported from KVB statement",
              _balance: balance
            }
          end
          
          pending_line = nil
        end
      end
      
      # ==========================================
      # METADATA DERIVATION
      # ==========================================
      if transactions.any? && transactions.last[:_balance]
        @metadata[:closing_balance] = transactions.last[:_balance]
      end
      
      # ==========================================
      # CLEANUP
      # ==========================================
      transactions.each { |t| t.delete(:_balance) }

      transactions
    end
  end
end
