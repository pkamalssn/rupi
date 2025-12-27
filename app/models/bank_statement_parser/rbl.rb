# frozen_string_literal: true

module BankStatementParser
  class Rbl < Base
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
        raise UnsupportedFormatError, "Unsupported file format for RBL"
      end
    rescue PasswordRequiredError
      raise
    rescue => e
      raise ParseError, "Failed to parse RBL statement: #{e.message}"
    end

    private

    def excel_file?
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
      
      # Extract metadata from PDF text
      if match = text.match(/Opening.*?Balance.*?([\d,]+\.\d{2})/im)
        @metadata[:opening_balance] = parse_amount(match[1])
      end
      if match = text.match(/Closing.*?Balance.*?([\d,]+\.\d{2})/im)
        @metadata[:closing_balance] = parse_amount(match[1])
      end

      lines.each do |line|
        line = line.strip
        next if line.empty?
        
        # Skip headers
        next if line.match?(/^Transaction\s*(Date|List)/i)
        next if line.match?(/^(Date|Cheque|Value|Withdrawal|Deposit|Balance)/i)
        next if line.match?(/Page\s+\d+\s+of/i)
        
        # Check for date pattern: DD/MM/YYYY or DD-MM-YYYY
        next unless match = line.match(/^(\d{2}[\/-]\d{2}[\/-]\d{4})\s+/)
        
        date = parse_date(match[1])
        next unless date
        
        # Extract all amounts from the line (include negative for ODraft)
        amounts = line.scan(/(-?[\d,]+\.\d{2})/).flatten.map { |s| parse_amount(s) }.compact
        
        next if amounts.empty? || amounts.length < 2
        
        # RBL PDF format: The last amount is always the balance
        balance = amounts.last
        raw_amount = amounts[0]
        
        # Store amount as positive for now - will fix with balance chain
        amount = raw_amount
        
        # Extract description (remove dates and amounts)
        description = line.sub(match[0], "").strip
        description = description.gsub(/[\d,]+\.\d{2}/, "").strip
        description = description.gsub(/\d{2}[\/-]\d{2}[\/-]\d{4}/, "").strip
        description = clean_description(description)
        
        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "RBL Transaction",
          notes: "Imported from RBL statement",
          _balance: balance
        }
      end
      
      # ==========================================
      # BALANCE-CHAIN POLARITY CORRECTION
      # ==========================================
      # RBL is REVERSE chronological: transactions[0] is NEWEST
      # 
      # For each transaction, we use the NEXT transaction's balance (which is older in time)
      # to determine if current transaction is a debit or credit.
      #
      # If transactions[idx] is a CREDIT:
      #   transactions[idx+1].balance (older) + transactions[idx].amount = transactions[idx].balance (newer)
      #
      # If transactions[idx] is a DEBIT:
      #   transactions[idx+1].balance (older) - transactions[idx].amount = transactions[idx].balance (newer)
      
      transactions.each_with_index do |txn, idx|
        next if idx >= transactions.length - 1  # Last transaction, no older reference
        
        older_txn = transactions[idx + 1]  # This is the OLDER transaction
        next unless txn[:_balance] && older_txn[:_balance]
        
        newer_balance = txn[:_balance].to_f
        older_balance = older_txn[:_balance].to_f
        raw_amount = txn[:amount].abs
        
        # Calculate the actual balance change
        balance_change = newer_balance - older_balance
        
        # If balance increased, this was a credit (deposit)
        # If balance decreased, this was a debit (withdrawal)
        if balance_change > 0
          # Credit: Amount should be positive
          txn[:amount] = raw_amount
        else
          # Debit: Amount should be negative
          txn[:amount] = -raw_amount
        end
      end
      
      # Handle the LAST transaction (oldest) - compare with opening balance if available
      if transactions.any? && @metadata[:opening_balance]
        last_txn = transactions.last
        if last_txn[:_balance]
          older_balance = @metadata[:opening_balance].to_f
          newer_balance = last_txn[:_balance].to_f
          balance_change = newer_balance - older_balance
          raw_amount = last_txn[:amount].abs
          
          if balance_change > 0
            last_txn[:amount] = raw_amount
          else
            last_txn[:amount] = -raw_amount
          end
        end
      end
      
      # ==========================================
      # METADATA FALLBACK
      # ==========================================
      if transactions.any?
        # Closing balance = newest transaction's balance (first in list)
        if @metadata[:closing_balance].nil? && transactions.first[:_balance]
          @metadata[:closing_balance] = transactions.first[:_balance]
        end
      end
      
      # ==========================================
      # CLEANUP
      # ==========================================
      transactions.each { |t| t.delete(:_balance) }
      
      transactions
    end

    def parse_transactions_from_spreadsheet(spreadsheet)
      transactions = []
      
      spreadsheet.each_with_index do |row, idx|
        next if idx == 0 # Skip header
        next if row.compact.empty?

        date = parse_date(row[0])
        next unless date

        # RBL Excel: Date, Description, Debit, Credit, Balance
        debit = parse_amount(row[2])
        credit = parse_amount(row[3])
        balance = parse_amount(row[4])
        
        amount = if debit && debit != 0
          -debit.abs
        elsif credit && credit != 0
          credit.abs
        else
          next
        end

        description = clean_description(row[1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "RBL Transaction",
          notes: "Imported from RBL statement",
          _balance: balance
        }
      end
      
      # Cleanup
      transactions.each { |t| t.delete(:_balance) }

      transactions
    end
  end
end
