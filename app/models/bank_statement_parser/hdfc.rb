# frozen_string_literal: true

module BankStatementParser
  class Hdfc < Base
    def parse
      transactions = []

      if pdf_file?
        # Check password protection FIRST before any other checks
        text = if password_protected?
          if password.present?
            decrypt_pdf_and_extract_text
          else
            raise PasswordRequiredError, "Password required for this PDF"
          end
        elsif scanned_pdf?
          extract_text_with_ocr
        else
          extract_text_from_pdf
        end
        
        # Extract metadata from STATEMENT SUMMARY section (usually on last page)
        extract_summary_metadata(text)
        
        transactions = parse_transactions_from_text(text)
      elsif excel_file?
        transactions = parse_excel
      else
        raise UnsupportedFormatError, "Unsupported file format: #{file.content_type}"
      end

      transactions
    rescue PasswordRequiredError
      raise
    rescue => e
      raise ParseError, "Failed to parse HDFC statement: #{e.message}"
    end

    private

    def excel_file?
      return false unless file.respond_to?(:content_type)
      %w[application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet text/csv].include?(file.content_type)
    end

    def parse_excel
      require "roo"

      spreadsheet = case file.content_type
                    when "application/vnd.ms-excel"
                      Roo::Excel.new(file_path)
                    when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                      Roo::Excelx.new(file_path)
                    when "text/csv"
                      Roo::CSV.new(file_path)
                    end

      parse_transactions_from_spreadsheet(spreadsheet)
    end

    def extract_summary_metadata(text)
      # HDFC Statement Summary format (usually on last page):
      # STATEMENT SUMMARY :-
      # Opening Balance   Dr Count   Cr Count   Debits   Credits   Closing Bal
      # 1,750.21          181        58         2,490,524.96  2,489,531.00  756.25
      #
      # Note: Headers and values are on SEPARATE lines
      
      return unless text =~ /STATEMENT SUMMARY/i
      
      # Find the line that contains the summary values
      # It will have multiple comma-formatted amounts (Opening, Debits, Credits, Closing)
      lines = text.split(/\n/)
      summary_idx = lines.find_index { |l| l =~ /STATEMENT SUMMARY/i }
      
      return unless summary_idx
      
      # Look at lines after the summary header
      lines[(summary_idx + 1)..(summary_idx + 5)].each do |line|
        # The values line has: Opening(amount) DrCount(int) CrCount(int) Debits(amount) Credits(amount) Closing(amount)
        # Pattern: at least 4 decimal amounts
        amounts = line.scan(/([\d,]+\.\d{2})/).flatten.map { |s| parse_amount(s) }
        
        if amounts.length >= 4
          # Format: Opening, Debits, Credits, Closing (DrCount and CrCount are integers, not matched)
          @metadata[:opening_balance] = amounts[0]  # First amount is Opening Balance
          @metadata[:closing_balance] = amounts.last  # Last amount is Closing Balance
          
          Rails.logger.info "HDFC Summary: Opening=#{@metadata[:opening_balance]}, Closing=#{@metadata[:closing_balance]}"
          break
        end
      end
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")
      last_balance = nil
      closing_balance_found = false

      lines.each do |line|
        # Skip lines that don't look like transactions
        next unless line.match?(/\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/)
        next unless line.match?(/[\d,]+\.\d{2}/) # Must have decimal amounts
        
        # Skip header lines - be more specific to avoid matching transaction descriptions
        # Headers have patterns like "Date       Narration       Chq./Ref.No.    Value Dt       Withdrawal     Deposit    Closing Balance"
        next if line.match?(/^\s*Date\s+.*Narration/i) || 
                line.match?(/^\s*Chq\.?\/?Ref/i) ||
                line.match?(/Withdrawal\s+Deposit\s+.*Balance/i)

        parsed = parse_transaction_line_columnar(line)
        if parsed && parsed[:amount]
          transactions << parsed
          
          # Track balance for metadata (only if not already set from Summary)
          if parsed[:_balance]
            # HDFC is chronological - first txn parsed is oldest, so we track for opening
            # Last txn parsed will be newest (for closing if summary didn't provide it)
            last_balance = parsed[:_balance]
          end
        end
      end

      # =====================================================
      # BALANCE-CHAIN VERIFICATION - Correct Debit/Credit Polarity
      # =====================================================
      # HDFC is CHRONOLOGICAL (oldest first)
      # For each txn: prev_balance + correct_amount = curr_balance
      
      transactions.each_with_index do |txn, idx|
        next unless txn[:_balance]
        
        if idx == 0
          # First transaction - can't verify without opening balance
          # Will be verified after we calculate opening balance
        else
          prev_txn = transactions[idx - 1]
          next unless prev_txn[:_balance]
          
          prev_balance = prev_txn[:_balance]
          curr_balance = txn[:_balance]
          raw_amount = txn[:amount].abs
          
          # Check: Does prev + amount = curr? (Credit)
          if (prev_balance + raw_amount - curr_balance).abs < 1.0
            txn[:amount] = raw_amount  # Positive (credit)
          # Check: Does prev - amount = curr? (Debit)
          elsif (prev_balance - raw_amount - curr_balance).abs < 1.0
            txn[:amount] = -raw_amount  # Negative (debit)
          end
          # If neither matches, keep original (edge case)
        end
      end

      # Derive Opening Balance from first transaction (after polarity correction)
      # Only if not already set from Statement Summary
      if @metadata[:opening_balance].nil? && transactions.any? && transactions.first[:_balance]
        first_txn = transactions.first
        # Opening = FirstBalance - FirstAmount
        @metadata[:opening_balance] = (first_txn[:_balance] - first_txn[:amount]).round(2)
      end
      
      # Derive Closing Balance from last transaction if not set from Summary
      if @metadata[:closing_balance].nil? && transactions.any? && transactions.last[:_balance]
        @metadata[:closing_balance] = transactions.last[:_balance]
      end

      # Cleanup internal fields
      transactions.each { |t| t.delete(:_balance) }
      
      transactions
    end

    def parse_transaction_line_columnar(line)
      # HDFC statement format (columns):
      # Date | Description | Ref No | Value Date | Debit | Credit | Balance
      # Example: "25/03/25   IMPS-...   0000508414362929   25/03/25   6,500.00              1,188.21"
      # Debit and Credit columns - one is empty, one has value
      
      # Extract date first
      date = nil
      date_patterns = [
        /(\d{1,2}\/\d{1,2}\/\d{2,4})/,     # 25/03/25 or 25/03/2025
        /(\d{1,2}-[A-Za-z]{3}-\d{2,4})/,   # 01-Jan-2024
        /(\d{1,2}-\d{1,2}-\d{2,4})/,       # 01-01-2024
      ]
      
      date_patterns.each do |pattern|
        if match = line.match(pattern)
          date = parse_date(match[1])
          break if date
        end
      end
      
      return nil unless date

      # Extract ALL amounts from the line (looking for comma-formatted Indian numbers)
      # Include optional negative sign for ODraft balances
      amounts = line.scan(/(-?[\d,]+\.\d{2})/).flatten.map { |s| 
        BigDecimal(s.gsub(",", ""))
      }
      
      return nil if amounts.empty?
      
      # HDFC Column Logic:
      # The LAST amount is always Balance
      # Before that: either Debit OR Credit (one will be missing/zero in the text)
      # Pattern: ... Debit | Credit | Balance
      
      balance = amounts.last
      amount = nil
      
      if amounts.length >= 3
        # We have: [possibly more...], Debit, Credit, Balance
        # One of Debit/Credit should be the transaction, other might be 0 or missing
        debit_val = amounts[-3]
        credit_val = amounts[-2]
        
        if debit_val > 0 && credit_val == 0
          amount = -debit_val  # Withdrawal
        elsif credit_val > 0 && debit_val == 0
          amount = credit_val  # Deposit
        elsif credit_val > 0
          amount = credit_val  # Default to credit if both present
        else
          amount = -debit_val
        end
      elsif amounts.length == 2
        # Only one amount + balance
        # Need to infer direction from description or balance change
        raw_amount = amounts[-2]
        # Default to credit (positive) - will be corrected by balance verification later
        amount = raw_amount
        
        # Check for debit keywords in description
        if line.match?(/ACH D-|IMPS-.*-DR|UPI-.*-DR|NEFT DR|EMI CHQ|Bill Payment|Withdrawal/i)
          amount = -raw_amount
        end
      elsif amounts.length == 1
        # Only balance visible - might be a continuation line, skip
        return nil
      end
      
      return nil unless amount

      # Extract description - text between date and amounts
      description = extract_description(line, date_patterns)

      {
        date: date,
        amount: amount,
        description: description.presence || "HDFC Transaction",
        notes: "Imported from HDFC statement",
        _balance: balance  # Internal, will be removed after processing
      }
    end

    def parse_transaction_line(line)
      # HDFC statement formats:
      # "01-Jan-2024    UPI/SWIGGY/DR/...    450.00    Dr       12,345.67"
      # "05/01/24       NEFT credit Salary   50000.00  Cr       62,345.67"
      
      # Extract date (various formats)
      date = nil
      date_patterns = [
        /(\d{1,2}-[A-Za-z]{3}-\d{2,4})/,  # 01-Jan-2024
        /(\d{1,2}\/\d{1,2}\/\d{2,4})/,     # 01/01/2024
        /(\d{1,2}-\d{1,2}-\d{2,4})/,       # 01-01-2024
      ]
      
      date_patterns.each do |pattern|
        if match = line.match(pattern)
          date = parse_date(match[1])
          break if date
        end
      end
      
      return nil unless date

      # Extract amount and Dr/Cr indicator
      # Look for amount followed by Dr/Cr
      amount = nil
      is_debit = nil
      
      if match = line.match(/([\d,]+\.?\d*)\s*(Dr|Cr)/i)
        amount_str, dr_cr = match[1], match[2]
        amount = BigDecimal(amount_str.gsub(",", ""))
        is_debit = dr_cr.downcase == "dr"
      elsif match = line.match(/([\d,]+\.\d{2})/)
        # Just a number without Dr/Cr
        amount = BigDecimal(match[1].gsub(",", ""))
        # Try to infer from description
        is_debit = line.downcase.include?("debit") || line.include?("UPI/") || line.include?("IMPS/")
      end
      
      return nil unless amount

      # Make debits negative (money going out)
      amount = -amount if is_debit

      # Extract description - everything between date and amount
      description = extract_description(line, date_patterns)

      {
        date: date,
        amount: amount,
        description: description.presence || "HDFC Transaction",
        notes: "Imported from HDFC statement"
      }
    end

    def extract_description(line, date_patterns)
      desc = line.dup
      
      # Remove date
      date_patterns.each do |pattern|
        desc = desc.sub(pattern, "")
      end
      
      # Remove amounts and Dr/Cr
      desc = desc.gsub(/[\d,]+\.?\d*\s*(Dr|Cr)?/i, "")
      
      # Clean up
      clean_description(desc)
    end

    def parse_transactions_from_spreadsheet(spreadsheet)
      transactions = []
      header_found = false
      date_col = nil
      desc_col = nil
      debit_col = nil
      credit_col = nil
      
      spreadsheet.each_with_index do |row, idx|
        # Find header row
        unless header_found
          row_str = row.map(&:to_s).join(" ").downcase
          if row_str.include?("date") || row_str.include?("transaction")
            header_found = true
            row.each_with_index do |cell, col_idx|
              cell_str = cell.to_s.downcase
              date_col = col_idx if cell_str.include?("date")
              desc_col = col_idx if cell_str.include?("narration") || cell_str.include?("description") || cell_str.include?("particulars")
              debit_col = col_idx if cell_str.include?("debit") || cell_str.include?("withdrawal")
              credit_col = col_idx if cell_str.include?("credit") || cell_str.include?("deposit")
            end
          end
          next
        end

        # Parse data rows
        next if row.compact.empty?
        
        date = parse_date(row[date_col || 0])
        next unless date

        debit_amt = parse_amount(row[debit_col]) if debit_col
        credit_amt = parse_amount(row[credit_col]) if credit_col
        
        amount = if debit_amt && debit_amt != 0
          -debit_amt.abs
        elsif credit_amt && credit_amt != 0
          credit_amt.abs
        else
          next
        end

        description = clean_description(row[desc_col || 1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "HDFC Transaction",
          notes: "Imported from HDFC statement"
        }
      end

      transactions
    end
  end
end
