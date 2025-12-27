# frozen_string_literal: true

require_relative "base"

module BankStatementParser
  class Icici < Base
    def parse
      transactions = []

      if pdf_file?
        transactions = parse_pdf
      elsif excel_file?
        transactions = parse_excel
      else
        raise UnsupportedFormatError, "Unsupported file format for ICICI"
      end

      transactions
    rescue => e
      raise ParseError, "Failed to parse ICICI statement: #{e.message}"
    end

    private

    def excel_file?
      return true if file.respond_to?(:filename) && file.filename.to_s.match?(/\.xlsx?$/i)
      return false unless file.respond_to?(:content_type)
      file.content_type&.include?("excel") || file.content_type&.include?("spreadsheet")
    end

    def parse_pdf
      require "pdf-reader"
      require "hexapdf"

      # ICICI encrypts PDFs with empty password
      text = ""
      
      begin
        # Try direct read first
        pdf_content = file.respond_to?(:download) ? StringIO.new(file.download) : File.open(file_path, "rb")
        reader = PDF::Reader.new(pdf_content)
        reader.pages.each { |page| text += page.text + "\n" }
      rescue PDF::Reader::EncryptedPDFError, PDF::Reader::MalformedPDFError => e
        # Try with HexaPDF and empty password
        Rails.logger.info("ICICI PDF encrypted, trying empty password...")
        
        doc = HexaPDF::Document.open(file_path, decryption_opts: { password: password.presence || "" })
        doc.encrypt(name: nil)
        
        temp = Tempfile.new(['icici_decrypted', '.pdf'])
        doc.write(temp.path)
        
        reader = PDF::Reader.new(temp.path)
        reader.pages.each { |page| text += page.text + "\n" }
        temp.unlink
      end

      parse_transactions_from_text(text)
    end

    def parse_excel
      require "roo"

      spreadsheet = Roo::Spreadsheet.open(file_path)
      transactions = []

      spreadsheet.each_with_index do |row, idx|
        next if idx == 0

        date = parse_date(row[0])
        next unless date

        amount = parse_amount(row[2] || row[3])
        next unless amount

        description = clean_description(row[1])

        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "ICICI Transaction",
          notes: "Imported from ICICI statement"
        }
      end

      transactions
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")

      # ICICI Detailed Statement format:
      # Value Date | Transaction Date | Cheque Number | Transaction Remarks | Withdrawal | Deposit | Balance
      # Transactions can span multiple lines for remarks
      
      current_txn = nil
      
      lines.each do |line|
        line = line.strip
        next if line.empty?
        next if line.match?(/^(S No|Value Date|Transaction|Search|Account Number|Transactions List|Page \d)/i)
        
        # Check for date pattern at start of line (DD/MM/YYYY)
        if match = line.match(/^\s*(\d{2}\/\d{2}\/\d{4})\s+(\d{2}\/\d{2}\/\d{4})/)
          # Save previous transaction if exists
          if current_txn && current_txn[:amount]
            transactions << current_txn
          end
          
          value_date = parse_date(match[1])
          
          # Try to extract amounts - look for numbers at the end
          # Format: Withdrawal | Deposit | Balance
          amounts = line.scan(/([\d,]+\.\d{2})/).flatten
          
          withdrawal = nil
          deposit = nil
          balance = nil
          
          if amounts.length >= 3
            withdrawal = parse_amount(amounts[-3])
            deposit = parse_amount(amounts[-2])
            balance = parse_amount(amounts[-1])
          elsif amounts.length == 2
            # Could be withdrawal+balance or deposit+balance
            withdrawal = parse_amount(amounts[0])
            balance = parse_amount(amounts[1])
          end
          
          # Determine amount and direction
          amount = if withdrawal && withdrawal > 0
            -withdrawal
          elsif deposit && deposit > 0
            deposit
          end
          
          # Extract description from the line
          description = line.sub(match[0], "").strip
          description = description.gsub(/([\d,]+\.\d{2})/, "").strip
          
          current_txn = {
            date: value_date,
            amount: amount,
            description: clean_description(description),
            notes: "Imported from ICICI statement"
          }
        elsif current_txn && !line.match?(/^\d/)
          # This is a continuation of the transaction remarks
          current_txn[:description] = [current_txn[:description], clean_description(line)].compact.join(" ")
        end
      end
      
      # Don't forget the last transaction
      if current_txn && current_txn[:amount]
        transactions << current_txn
      end

      # Clean up descriptions
      transactions.each do |t|
        t[:description] = t[:description].to_s.squeeze(" ").strip.presence || "ICICI Transaction"
      end

      transactions
    end
  end
end
