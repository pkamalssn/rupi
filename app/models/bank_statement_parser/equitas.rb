# frozen_string_literal: true

module BankStatementParser
  class Equitas < Base
    def parse
      if excel_file?
        parse_excel
      elsif pdf_file?
        text = if password_protected? && password.present?
          decrypt_pdf_and_extract_text
        elsif scanned_pdf?
          extract_text_with_ocr
        else
          extract_text_from_pdf
        end
        parse_transactions_from_text(text)
      else
        raise UnsupportedFormatError, "Unsupported file format for Equitas"
      end
    rescue PasswordRequiredError
      raise
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
      
      # Equitas format has columns: Date | Ref | Narration | Withdrawal | Deposit | ClosingBalance
      # We use balance chain to determine polarity since UPI transactions don't have clear Dr/Cr markers
      
      # Extract metadata - Available Balance
      if match = text.match(/Available Balance.*?([\d,]+\.\d{2})/i)
        @metadata[:closing_balance] = parse_amount(match[1])
      end

      lines.each_with_index do |line, idx|
        # Date pattern: dd-MMM-yyyy
        next unless date_match = line.match(/(\d{2}-[A-Za-z]{3}-\d{4})/)
        
        date = parse_date(date_match[1])
        next unless date
        
        # Extract all amounts from this line
        amounts = line.scan(/([\d,]+\.\d{2})/).flatten.map { |a| parse_amount(a) }
        next if amounts.empty?
        
        raw_amount = nil
        balance = nil
        description = line.sub(date_match[0], "").strip
        
        if amounts.length >= 2
          # Normal line: [transaction_amount, closing_balance]
          raw_amount = amounts.first
          balance = amounts.last
        elsif amounts.length == 1
          # Date line with only balance - look back for transaction amount
          balance = amounts.first
          
          # Search previous lines (up to 5) for transaction amount
          (-5..-1).each do |offset|
            prev_idx = idx + offset
            next if prev_idx < 0
            prev_line = lines[prev_idx]
            
            # Skip if previous line has a date (it's a different transaction)
            next if prev_line.match?(/\d{2}-[A-Za-z]{3}-\d{4}/)
            
            # Look for UPI/transaction reference with amount
            if prev_line.match?(/UPIFIN\d+|UPI REF/) && prev_line.match?(/[\d,]+\.\d{2}/)
              prev_amounts = prev_line.scan(/([\d,]+\.\d{2})/).flatten.map { |a| parse_amount(a) }
              if prev_amounts.any?
                raw_amount = prev_amounts.first
                description = prev_line.gsub(/UPIFIN\d+/, "").gsub(/[\d,]+\.\d{2}/, "").strip
                description += " " + line.sub(date_match[0], "").gsub(/[\d,]+\.\d{2}/, "").strip
                break
              end
            end
          end
        end
        
        next unless raw_amount && raw_amount > 0
        
        description = description.gsub(/UPIFIN\d+/, "").gsub(/[\d,]+\.\d{2}/, "").strip
        description = clean_description(description)

        transactions << {
          date: date,
          amount: raw_amount,
          description: description.presence || "Equitas Transaction",
          notes: "Imported from Equitas statement",
          _balance: balance
        }
      end
      
      # ==========================================
      # BALANCE-CHAIN POLARITY VERIFICATION
      # ==========================================
      # Equitas is chronological: first transaction is oldest
      
      transactions.each_with_index do |txn, idx|
        next if idx == 0
        prev_txn = transactions[idx - 1]
        next unless txn[:_balance] && prev_txn[:_balance]
        
        prev_balance = prev_txn[:_balance].to_f
        curr_balance = txn[:_balance].to_f
        raw_amount = txn[:amount].abs
        
        # Credit check: prev + amount = curr
        if (prev_balance + raw_amount - curr_balance).abs < 1.0
          txn[:amount] = raw_amount
        # Debit check: prev - amount = curr
        elsif (prev_balance - raw_amount - curr_balance).abs < 1.0
          txn[:amount] = -raw_amount
        end
      end
      
      # Fix first transaction using opening balance if derivable
      if transactions.length > 0 && transactions.first[:_balance]
        first_txn = transactions.first
        raw = first_txn[:amount].abs
        balance_after = first_txn[:_balance].to_f
        
        # Infer opening balance
        # If it's a credit: opening = balance - amount
        # If it's a debit: opening = balance + amount
        opening_if_credit = balance_after - raw
        opening_if_debit = balance_after + raw
        
        # Use the polarity that was already determined by balance chain (for transactions 2+)
        # For first transaction, use second transaction's balance chain to infer
        desc = first_txn[:description].to_s.upcase
        
        # Check if we can use second transaction to verify first
        if transactions.length >= 2
          second_txn = transactions[1]
          if second_txn[:_balance]
            first_balance = first_txn[:_balance].to_f
            second_balance = second_txn[:_balance].to_f
            second_amount = second_txn[:amount].to_f
            
            # Second transaction polarity is known from balance chain
            # If it's a credit: first_balance + second_amount = second_balance
            # If it's a debit: first_balance - abs(second_amount) = second_balance
            # This helps us verify the first transaction
            
            # For first transaction: try both directions and see which makes sense
            # If first_txn is credit: opening + raw = first_balance → opening = first_balance - raw
            # If first_txn is debit: opening - raw = first_balance → opening = first_balance + raw
            
            opening_if_credit = balance_after - raw
            opening_if_debit = balance_after + raw
            
            if opening_if_credit >= 0
              first_txn[:amount] = raw  # Credit
              @metadata[:opening_balance] = opening_if_credit
            elsif opening_if_debit >= 0
              first_txn[:amount] = -raw  # Debit
              @metadata[:opening_balance] = opening_if_debit
            end
          end
        else
          # Fallback to keyword matching
          if desc.match?(/CREDIT|RTGS CR|NEFT CR|IMPS CR|DEPOSIT/)
            first_txn[:amount] = raw
            @metadata[:opening_balance] = opening_if_credit
          elsif desc.match?(/ATM|WITHDRAWAL|P2P|P2M|DEBIT/)
            first_txn[:amount] = -raw
            @metadata[:opening_balance] = opening_if_debit
          end
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

