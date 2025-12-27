# frozen_string_literal: true

module BankStatementParser
  class Jupiter < Base
    def parse
      if excel_file?
        parse_excel
      elsif pdf_file?
        parse_pdf
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

    def parse_pdf
      # Memory efficient: Split by page and process lines directly
      lines = []
      
      begin
         if file.respond_to?(:download)
           pdf_content = StringIO.new(file.download) 
           reader = PDF::Reader.new(pdf_content)
         else
           reader = PDF::Reader.new(file_path)
         end
         
         # Metadata Extraction State
         opening_found = false
         closing_found = false

         reader.pages.each do |page| 
           page_text = page.text
           lines.concat(page_text.split("\n")) 
           
           # Extract Metadata (Opening/Closing Balance)
           unless opening_found
             if match = page_text.match(/Opening Balance\s+([\d,]+\.\d{2})/i)
               @metadata[:opening_balance] = parse_amount(match[1])
               opening_found = true
             end
           end
           
           # Always look for closing balance (might be updated on later pages)
           if match = page_text.match(/Effective Available Balance.*?([\d,]+\.\d{2})/i)
             @metadata[:closing_balance] = parse_amount(match[1])
             closing_found = true
           elsif match = page_text.match(/Closing Balance.*?([\d,]+\.\d{2})/i)
              @metadata[:closing_balance] = parse_amount(match[1])
              closing_found = true
           end
         end
      rescue => e
         # Fallback or error handling
         Rails.logger.error("Error reading Jupiter PDF: #{e.message}")
         # Attempt to proceed with whatever lines we got or raise
         raise e
      end

      parse_transactions_from_text(lines)
    end

    def parse_transactions_from_text(lines)
      if lines.is_a?(String)
        lines = lines.split("\n")
      end

      transactions = []
      current_txn = nil
      last_balance = nil
      first_balance = nil  # Track for closing balance (Jupiter is chronological)

      lines.each do |line|
        line = line.strip 
        next if line.empty?

        # Jupiter/Federal Bank PDF formats:
        # "01-Jan-2025  Description  1000.00 Dr  50000.00"
        # "01/01/2025   Description  1000.00     50000.00"
        
        match = line.match(/^(\d{1,2}-[A-Za-z]{3}-\d{2,4})/) ||
                line.match(/^(\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4})/)
        
        if match
          if current_txn && current_txn[:amount]
            transactions << current_txn
          end

          value_date = parse_date(match[1])
          
          # Extract all numbers (include negative for ODraft support)
          amounts_found = line.scan(/(-?[\d,]+\.?\d{0,2})/).flatten.map { |s| parse_amount(s) }.compact
          # Filter out weird small nums if needed, but keeping generally is safer
          amounts = amounts_found.select { |ns| ns.abs > 0 }
          
          amount = nil
          balance = nil
          
          if amounts.length >= 2
             balance = amounts.last
             raw_amount = amounts[-2]
             
             # Track first balance for closing (Jupiter is chronological - first=oldest)
             first_balance ||= balance
             
             # MATH HEURISTIC for Dr/Cr
             if last_balance
               # Debit: Last - Curr = Amount (Decay)
               diff = last_balance - balance
               
               if (diff.abs - raw_amount.abs).abs < 1.0
                 # The difference matches the amount extracted
                 # If Last > Curr, it's a Debit (Diff > 0)
                 # If Last < Curr, it's a Credit (Diff < 0)
                 if diff > 0
                   amount = -diff.abs # Debit
                 else
                   amount = diff.abs # Credit
                 end
               else
                 # Math didn't match perfectly
                 # Fallback to visual indicators
                 is_cr = line.match?(/\b(CR|Cr)\b/) || line.match?(/CREDIT|DEPOSIT/)
                 amount = is_cr ? raw_amount.abs : -raw_amount.abs
               end
             else
               # First txn
               # Look for explicit Cr/Dr
               is_cr = line.match?(/\b(CR|Cr)\b/) || line.match?(/CREDIT|DEPOSIT/)
               amount = is_cr ? raw_amount.abs : -raw_amount.abs
             end
             
             last_balance = balance
          elsif amounts.length == 1
             # Just amount?
             raw_amount = amounts.first
             is_cr = line.match?(/\b(CR|Cr)\b/) || line.match?(/CREDIT|DEPOSIT/)
             amount = is_cr ? raw_amount.abs : -raw_amount.abs
          end

          # Description extraction
          description = line.sub(match[0], "").strip
          description = description.gsub(/[\d,]+\.\d{2}/, "").gsub(/\b(Dr|Cr)\b/i, "").strip
          description = clean_description(description)

          current_txn = {
            date: value_date,
            amount: amount,
            description: description.presence || "Jupiter Transaction",
            notes: "Imported from Jupiter statement",
            _balance: balance  # Internal for balance-chain verification
          }
        elsif current_txn && !line.match?(/^\d/)
           current_txn[:description] = [current_txn[:description], clean_description(line)].compact.join(" ")
        end
      end
      
      if current_txn && current_txn[:amount]
        transactions << current_txn
      end

      # =====================================================
      # BALANCE-CHAIN VERIFICATION - Correct Polarity
      # =====================================================
      # Jupiter is CHRONOLOGICAL (oldest first)
      # For each txn: prev_balance + correct_amount = curr_balance
      
      transactions.each_with_index do |txn, idx|
        next unless txn[:_balance]
        next if idx == 0  # First txn can't be verified
        
        prev_txn = transactions[idx - 1]
        next unless prev_txn[:_balance]
        
        prev_balance = prev_txn[:_balance].to_f
        curr_balance = txn[:_balance].to_f
        raw_amount = txn[:amount].abs
        
        # Check: Does prev + amount = curr? (Credit)
        if (prev_balance + raw_amount - curr_balance).abs < 1.0
          txn[:amount] = raw_amount  # Positive (credit)
        # Check: Does prev - amount = curr? (Debit)
        elsif (prev_balance - raw_amount - curr_balance).abs < 1.0
          txn[:amount] = -raw_amount  # Negative (debit)
        end
        # If neither matches, keep original
      end

      # =====================================================
      # METADATA DERIVATION (Fallback if not found in PDF text)
      # =====================================================
      # Jupiter is chronological: first txn = oldest, last txn = newest
      
      # Opening Balance: FirstBalance - FirstAmount
      if @metadata[:opening_balance].nil? && transactions.any? && transactions.first[:_balance]
        first_txn = transactions.first
        @metadata[:opening_balance] = (first_txn[:_balance] - first_txn[:amount]).round(2)
      end
      
      # Closing Balance: Last transaction's balance
      if @metadata[:closing_balance].nil? && transactions.any? && transactions.last[:_balance]
        @metadata[:closing_balance] = transactions.last[:_balance]
      end

      # Cleanup internal fields
      transactions.each { |t| t.delete(:_balance) }

      transactions
    end
  end
end
