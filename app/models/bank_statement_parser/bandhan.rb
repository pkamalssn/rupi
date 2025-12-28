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
              column_map[:balance] = col_idx if cell_str.match?(/balance/i)
            end
          end
          next
        end

        next if row.compact.empty?

        date = parse_date(row[column_map[:date] || 0])
        next unless date

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

        balance = parse_amount(row[column_map[:balance]]) if column_map[:balance]
        description = clean_description(row[column_map[:description] || 1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Bandhan Transaction",
          notes: "Imported from Bandhan statement",
          _balance: balance
        }
      end

      verify_and_fix_polarity(transactions)
      transactions.each { |t| t.delete(:_balance) }
      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")
      last_balance = nil
      
      # Bandhan format: "December19, 2025 December19, 2025 Description INR500.00 Dr INR2,167.10"
      # Date format: MonthDay, Year (e.g., December19, 2025)
      
      # Extract metadata from summary line
      # Format: "Opening Balance  Total Credits  Total Debits  Closing Balance"
      #         "INR122,047.78    INR997,261.00  INR1,117,141.68  INR2,167.10"
      lines.each_with_index do |line, idx|
        if line.match?(/Opening Balance.*Total Credits.*Total Debits.*Closing Balance/i)
          # Values are on a line following the header
          value_line = nil
          (1..3).each do |offset|
            next_line = lines[idx + offset]
            if next_line && next_line.match?(/INR[\d,]+\.\d{2}.*INR[\d,]+\.\d{2}/)
              value_line = next_line
              break
            end
          end
          
          if value_line
            amounts = value_line.scan(/INR\s*([\d,]+\.\d{2})/).flatten
            if amounts.length >= 4
              @metadata[:opening_balance] = parse_amount(amounts[0])
              @metadata[:closing_balance] = parse_amount(amounts[3])
            end
          end
          break
        end
      end

      lines.each do |line|
        line = line.strip
        next if line.empty?
        
        # Skip header lines
        next if line.match?(/Transaction Date.*Value Date/i)
        next if line.match?(/Statement Details/i)
        next if line.match?(/Account Statement as on/i)
        
        # Bandhan date format: Month + Day + comma + space + Year
        # E.g., "December19, 2025" or "November27, 2025"
        date_pattern = /(January|February|March|April|May|June|July|August|September|October|November|December)\s*(\d{1,2}),?\s*(\d{4})/i
        
        next unless date_match = line.match(date_pattern)
        
        month_name = date_match[1]
        day = date_match[2]
        year = date_match[3]
        
        # Convert to parseable date string
        date_str = "#{day} #{month_name} #{year}"
        date = parse_date(date_str)
        next unless date
        
        # Extract amounts with INR prefix
        # Pattern: INR followed by amount like "INR500.00" or "INR10,500.00"
        amounts = line.scan(/INR\s*([\d,]+\.\d{2})/i).flatten.map { |a| parse_amount(a) }.compact
        
        next if amounts.empty?
        
        # Last amount is typically the balance
        balance = amounts.last
        
        # First amount is the transaction amount
        raw_amount = amounts.first
        
        # Check for Dr/Cr indicator
        is_debit = line.match?(/\bDr\b/i)
        is_credit = line.match?(/\bCr\b/i)
        
        if is_debit
          amount = -raw_amount.abs
        elsif is_credit
          amount = raw_amount.abs
        else
          # Use balance chain if available
          if last_balance && amounts.length >= 2
            balance_change = balance - last_balance
            if balance_change > 0
              amount = raw_amount.abs
            else
              amount = -raw_amount.abs
            end
          else
            amount = raw_amount
          end
        end
        
        next unless amount && amount != 0
        
        last_balance = balance
        
        # Extract description - remove dates and amounts
        description = line.dup
        # Remove all date matches
        description = description.gsub(date_pattern, "")
        # Remove INR amounts
        description = description.gsub(/INR\s*[\d,]+\.\d{2}/i, "")
        # Remove Dr/Cr
        description = description.gsub(/\b(Dr|Cr)\b/i, "")
        description = clean_description(description)
        
        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "Bandhan Transaction",
          notes: "Imported from Bandhan statement",
          _balance: balance
        }
      end
      
      # Balance-chain verification (chronological - looking at the data, newer dates first = reverse chron)
      # Actually Bandhan appears to be reverse chronological based on the PDF
      verify_reverse_chronological(transactions)
      
      # Metadata derivation
      if transactions.any?
        # First transaction = newest (closing), Last = oldest
        if @metadata[:closing_balance].nil? && transactions.first[:_balance]
          @metadata[:closing_balance] = transactions.first[:_balance]
        end
        
        if @metadata[:opening_balance].nil? && transactions.last[:_balance]
          last_txn = transactions.last
          @metadata[:opening_balance] = (last_txn[:_balance] - last_txn[:amount]).round(2)
        end
      end
      
      transactions.each { |t| t.delete(:_balance) }
      transactions
    end
    
    def verify_and_fix_polarity(transactions)
      transactions.each_with_index do |txn, idx|
        next if idx == 0
        prev_txn = transactions[idx - 1]
        next unless txn[:_balance] && prev_txn[:_balance]
        
        prev_balance = prev_txn[:_balance].to_f
        curr_balance = txn[:_balance].to_f
        raw_amount = txn[:amount].abs
        
        if (prev_balance + raw_amount - curr_balance).abs < 1.0
          txn[:amount] = raw_amount
        elsif (prev_balance - raw_amount - curr_balance).abs < 1.0
          txn[:amount] = -raw_amount
        end
      end
    end
    
    def verify_reverse_chronological(transactions)
      # For reverse chronological, compare with NEXT transaction (older in time)
      transactions.each_with_index do |txn, idx|
        next if idx >= transactions.length - 1
        older_txn = transactions[idx + 1]
        next unless txn[:_balance] && older_txn[:_balance]
        
        newer_balance = txn[:_balance].to_f
        older_balance = older_txn[:_balance].to_f
        raw_amount = txn[:amount].abs
        
        # If newer_balance > older_balance, this was a credit
        balance_change = newer_balance - older_balance
        if balance_change > 0 && (balance_change - raw_amount).abs < 1.0
          txn[:amount] = raw_amount
        elsif balance_change < 0 && (balance_change.abs - raw_amount).abs < 1.0
          txn[:amount] = -raw_amount
        end
      end
    end
  end
end
