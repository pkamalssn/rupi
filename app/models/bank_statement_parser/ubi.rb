# frozen_string_literal: true

module BankStatementParser
  class Ubi < Base
    # Union Bank of India statement parser

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
        raise UnsupportedFormatError, "Unsupported file format for UBI"
      end
    rescue => e
      raise ParseError, "Failed to parse UBI statement: #{e.message}"
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
          if row_str.include?("date") || row_str.include?("transaction") || row_str.include?("particulars")
            header_found = true
            row.each_with_index do |cell, col_idx|
              cell_str = cell.to_s.downcase
              column_map[:date] = col_idx if cell_str.match?(/date|txn date|value date/i)
              column_map[:description] = col_idx if cell_str.match?(/description|narration|particulars/i)
              column_map[:debit] = col_idx if cell_str.match?(/debit|withdrawal|dr/i)
              column_map[:credit] = col_idx if cell_str.match?(/credit|deposit|cr/i)
              column_map[:balance] = col_idx if cell_str.match?(/balance/i)
            end
          end
          next
        end

        next if row.compact.empty?

        date = parse_date(row[column_map[:date] || 0])
        next unless date

        debit = parse_amount(row[column_map[:debit]]) if column_map[:debit]
        credit = parse_amount(row[column_map[:credit]]) if column_map[:credit]
        balance = parse_amount(row[column_map[:balance]]) if column_map[:balance]
        
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
          description: description.presence || "UBI Transaction",
          notes: "Imported from Union Bank of India statement",
          _balance: balance
        }
      end

      # Balance-chain verification
      verify_and_fix_polarity(transactions)
      
      # Cleanup
      transactions.each { |t| t.delete(:_balance) }
      
      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")
      last_balance = nil
      
      # Extract metadata
      if match = text.match(/Opening.*?Balance.*?([\d,]+\.\d{2})/im)
        @metadata[:opening_balance] = parse_amount(match[1])
      end
      if match = text.match(/Closing.*?Balance.*?([\d,]+\.\d{2})/im)
        @metadata[:closing_balance] = parse_amount(match[1])
      end

      lines.each do |line|
        line = line.strip
        next if line.empty?
        
        # UBI format from PDF:
        # "03-01-2025    S53520969              352102010053600:Int.Pd:01-10-2024 to 31-12-2024             56.0(Cr)     6748.04(Cr)"
        # Date | Trans ID | Description | Amount(Dr/Cr) | Balance(Cr)
        
        # Check for date at start: DD-MM-YYYY
        next unless match = line.match(/^(\d{2}-\d{2}-\d{4})\s+/)
        
        # Ignore header lines
        next if line.match?(/Statement.*Date|Statement.*Period|Balance.*Brought|Page.*of|Date.*Transaction/i)
        
        date = parse_date(match[1])
        next unless date
        
        # Rest of line after date
        rest = line.sub(match[0], "").strip
        
        # Extract amounts with (Cr) or (Dr) indicators
        # Pattern: 56.0(Cr) or 20000.0(Dr)
        amount_matches = rest.scan(/([\d,]+\.?\d*)\((Cr|Dr)\)/i)
        
        next if amount_matches.empty?
        
        # Last match is typically the balance, first is the transaction amount
        if amount_matches.length >= 2
          amount_str, amount_type = amount_matches[0]
          balance_str, _ = amount_matches.last
          balance = parse_amount(balance_str)
        elsif amount_matches.length == 1
          # Only one amount found - could be just balance or amount
          amount_str, amount_type = amount_matches[0]
          balance = nil
        end
        
        amount = parse_amount(amount_str)
        next unless amount && amount != 0
        
        # Apply polarity based on Dr/Cr
        if amount_type&.downcase == "dr"
          amount = -amount.abs
        else
          amount = amount.abs
        end
        
        # Extract description (remove amounts and transaction ID)
        description = rest.gsub(/[\d,]+\.?\d*\((Cr|Dr)\)/i, "").strip
        description = description.gsub(/^[A-Z]\d+\s+/, "")  # Remove transaction ID like S53520969
        description = clean_description(description)
        
        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "UBI Transaction",
          notes: "Imported from Union Bank of India statement",
          _balance: balance
        }
        
        last_balance = balance if balance
      end
      
      # ==========================================
      # BALANCE-CHAIN VERIFICATION (CHRONOLOGICAL)
      # ==========================================
      # UBI is chronological: transactions[0] is OLDEST
      
      verify_and_fix_polarity(transactions)
      
      # ==========================================
      # METADATA DERIVATION
      # ==========================================
      if transactions.any?
        # Opening: first transaction's balance - first amount
        if @metadata[:opening_balance].nil? && transactions.first[:_balance]
          first_txn = transactions.first
          @metadata[:opening_balance] = (first_txn[:_balance] - first_txn[:amount]).round(2)
        end
        
        # Closing: last transaction's balance
        if @metadata[:closing_balance].nil? && transactions.last[:_balance]
          @metadata[:closing_balance] = transactions.last[:_balance]
        end
      end
      
      # ==========================================
      # CLEANUP
      # ==========================================
      transactions.each { |t| t.delete(:_balance) }

      transactions
    end
    
    def verify_and_fix_polarity(transactions)
      # Chronological order: each transaction builds on the previous
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
    end
  end
end
