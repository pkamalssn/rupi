# frozen_string_literal: true

require_relative "base"

module BankStatementParser
  class Sbi < Base
    def parse
      transactions = []

      if file.content_type == "application/pdf"
        transactions = parse_pdf
      elsif %w[application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet text/csv].include?(file.content_type)
        transactions = parse_excel
      else
        raise UnsupportedFormatError, "Unsupported file format: #{file.content_type}"
      end

      transactions
    rescue => e
      raise ParseError, "Failed to parse SBI statement: #{e.message}"
    end

    private

    def parse_pdf
      require "pdf-reader"

      pdf_content = file.respond_to?(:download) ? StringIO.new(file.download) : File.open(file.path, "rb")
      reader = PDF::Reader.new(pdf_content)

      text = ""
      reader.pages.each { |page| text += page.text }

      parse_transactions_from_text(text)
    end

    def parse_excel
      require "roo"

      spreadsheet = case file.content_type
                    when "application/vnd.ms-excel" then Roo::Excel.new(file.path)
                    when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" then Roo::Excelx.new(file.path)
                    when "text/csv" then Roo::CSV.new(file.path)
                    end

      transactions = []

      spreadsheet.each_with_index do |row, idx|
        next if idx == 0

        date = parse_date(row[0])
        next unless date

        # SBI Excel may have separate debit/credit columns
        amount = parse_amount(row[3]) || parse_amount(row[4])
        amount = -amount.abs if row[3].present? # Debit column

        next unless amount

        description = clean_description(row[1] || row[2])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "SBI Transaction",
          notes: "Imported from SBI statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")
      
      # ==========================================
      # METADATA EXTRACTION
      # ==========================================
      if match = text.match(/Opening.*?Balance.*?([\d,]+\.\d{2})/im)
        @metadata[:opening_balance] = parse_amount(match[1])
      end
      if match = text.match(/Closing.*?Balance.*?([\d,]+\.\d{2})/im)
        @metadata[:closing_balance] = parse_amount(match[1])
      end
      
      lines.each do |line|
        # SBI format: "01/01/2024    TRANSACTION DESCRIPTION    500.00 Dr    10000.00"
        next unless line =~ /\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/

        parts = line.split(/\s{2,}/)
        next unless parts.length >= 3

        date = parse_date(parts[0])
        next unless date

        # Find amounts in the line - typically [amount, balance]
        amounts = line.scan(/([\d,]+\.\d{2})/).flatten.map { |a| parse_amount(a) }
        next if amounts.empty?

        amount = amounts.first
        balance = amounts.length >= 2 ? amounts.last : nil
        next unless amount && amount > 0
        
        # SBI uses Dr/Cr indicators
        is_credit = line.match?(/\bCR\b|CREDIT|SALARY|NEFT.*CR|RTGS.*CR/i)
        is_debit = line.match?(/\bDR\b|DEBIT|ATM|WITHDRAWAL|UPI|NEFT.*DR|RTGS.*DR/i)
        
        if is_credit && !is_debit
          amount = amount.abs
        elsif is_debit || !is_credit
          amount = -amount.abs
        end

        description = clean_description(parts[1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "SBI Transaction",
          notes: "Imported from SBI statement",
          _balance: balance
        }
      end
      
      # ==========================================
      # BALANCE-CHAIN POLARITY VERIFICATION
      # ==========================================
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
      
      # ==========================================
      # METADATA DERIVATION
      # ==========================================
      if @metadata[:opening_balance].nil? && transactions.any? && transactions.first[:_balance]
        first_txn = transactions.first
        @metadata[:opening_balance] = (first_txn[:_balance] - first_txn[:amount]).round(2)
      end
      if transactions.any? && transactions.last[:_balance]
        @metadata[:closing_balance] ||= transactions.last[:_balance]
      end
      
      # ==========================================
      # CLEANUP
      # ==========================================
      transactions.each { |t| t.delete(:_balance) }

      transactions
    end
  end
end
