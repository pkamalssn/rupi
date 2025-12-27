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

      lines.each do |line|
        next unless line.match?(/\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}/)
        next unless line.match?(/\d+\.?\d*/)

        parsed = parse_transaction_line(line)
        transactions << parsed if parsed && parsed[:amount]
      end

      transactions
    end

    def parse_transaction_line(line)
      # RBL format: "25/12/2024  UPI-SWIGGY-PAYMENT  5,000.00  Dr  Balance"
      date = nil
      
      if match = line.match(/(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/)
        date = parse_date(match[1])
      end
      return nil unless date

      # Extract amount
      amount = nil
      is_debit = line.downcase.include?("dr") || line.downcase.include?("debit")
      
      if match = line.match(/([\d,]+\.\d{2})/)
        amount = BigDecimal(match[1].gsub(",", ""))
        amount = -amount if is_debit
      end
      return nil unless amount

      # Extract description
      description = line.dup
      description = description.sub(/\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/, "")
      description = description.gsub(/[\d,]+\.\d{2}/, "")
      description = description.gsub(/\s+(Dr|Cr|Debit|Credit)\s*/i, "")
      description = clean_description(description)

      {
        date: date,
        amount: amount,
        description: description.presence || "RBL Transaction",
        notes: "Imported from RBL statement"
      }
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
          notes: "Imported from RBL statement"
        }
      end

      transactions
    end
  end
end
