# frozen_string_literal: true

module BankStatementParser
  class IciciAmazonPay < Base
    # ICICI Amazon Pay Credit Card statement parser
    # Also works for other ICICI Credit Cards
    
    def parse
      if pdf_file?
        text = extract_icici_cc_text
        parse_transactions_from_text(text)
      else
        raise UnsupportedFormatError, "ICICI Credit Card statements are typically PDF format"
      end
    rescue PasswordRequiredError
      raise
    rescue => e
      raise ParseError, "Failed to parse ICICI Credit Card statement: #{e.message}"
    end

    private
    
    def extract_icici_cc_text
      require "pdf-reader"
      
      # ICICI CC PDFs often have encryption issues
      # Try multiple approaches
      
      begin
        # First try direct read
        reader = PDF::Reader.new(file_path)
        return reader.pages.map(&:text).join("\n")
      rescue PDF::Reader::EncryptedPDFError
        # Try qpdf decryption as fallback
        if password.present?
          return decrypt_with_qpdf
        else
          raise PasswordRequiredError, "Password required for ICICI Credit Card statement"
        end
      end
    end
    
    def decrypt_with_qpdf
      require "tempfile"
      temp = Tempfile.new(["icici_cc", ".pdf"])
      
      # Use qpdf which handles problematic ICICI CC encryption
      system("qpdf", "--password=#{password}", "--decrypt", file_path, temp.path, 
             out: File::NULL, err: File::NULL)
      
      unless File.exist?(temp.path) && File.size(temp.path) > 0
        raise ParseError, "Failed to decrypt ICICI Credit Card PDF"
      end
      
      reader = PDF::Reader.new(temp.path)
      text = reader.pages.map(&:text).join("\n")
      temp.unlink
      text
    end

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")
      
      # ==========================================
      # METADATA EXTRACTION - Credit Card Specific
      # ==========================================
      if match = text.match(/Total Amount due.*?([\d,]+\.\d{2})/im)
        @metadata[:total_due] = parse_amount(match[1])
        @metadata[:closing_balance] = @metadata[:total_due]  # For CC, total due = closing balance
      end
      if match = text.match(/Credit Limit.*?([\d,]+\.\d{2})/im)
        @metadata[:credit_limit] = parse_amount(match[1])
      end
      if match = text.match(/Minimum.*?Amount.*?Due.*?([\d,]+\.\d{2})/im)
        @metadata[:minimum_due] = parse_amount(match[1])
      end
      if match = text.match(/Previous.*?Balance.*?([\d,]+\.\d{2})/im)
        @metadata[:opening_balance] = parse_amount(match[1])
      end
      if match = text.match(/Payment.*?Due.*?Date.*?(\w+\s+\d{1,2},?\s+\d{4})/im)
        @metadata[:payment_due_date] = parse_date(match[1])
      end
      
      lines.each do |line|
        line = line.strip
        next if line.empty?
        next if line.length < 15
        
        # Skip header/footer lines
        next if line.match?(/^(Date|Transaction|Description|Points|Amount|Page\s+\d)/i)
        next if line.match?(/statement.*date|payment.*due.*date|credit.*limit/i)
        
        # ICICI CC Format: DD/MM/YYYY | Trans ID | Description | Points | Amount (CR)
        # Date pattern at the start of line (may have leading spaces/numbers)
        next unless date_match = line.match(/^\s*\d*\s*(\d{2}[\/-]\d{2}[\/-]\d{4})/)
        
        date = parse_date(date_match[1])
        next unless date
        
        # Extract amount - look for number followed by optional CR
        # Pattern: "45,317.00 CR" or "1,403.00" or "23.6 USD 2,189.78"
        # Get the last amount in the line (usually the INR amount)
        amounts = line.scan(/([\d,]+\.\d{2})(\s*CR)?/i)
        next if amounts.empty?
        
        # Last amount is typically the transaction amount
        amount_str, cr_indicator = amounts.last
        amount = parse_amount(amount_str)
        next unless amount && amount > 0
        
        # Determine credit vs debit
        # CR suffix = Credit (payment, refund, reversal)
        # No suffix = Debit (purchase)
        is_credit = cr_indicator&.strip&.upcase == "CR" ||
                    line.downcase.match?(/payment.*received|refund|reversal|cashback/)
        
        # For credit card: purchases are negative (money spent)
        # Credits/payments are positive
        if is_credit
          amount = amount.abs
        else
          amount = -amount.abs
        end
        
        # Extract description
        description = line.sub(date_match[0], "").strip
        # Remove transaction ID (12-digit number)
        description = description.gsub(/\d{10,12}/, "")
        # Remove amounts
        description = description.gsub(/[\d,]+\.\d{2}(\s*CR)?/i, "")
        # Remove reward points (single/double digit followed by spaces)
        description = description.gsub(/^\s*\d{1,2}\s+/, " ")
        # Remove foreign currency amounts
        description = description.gsub(/[\d.]+\s*(USD|EUR|GBP)/i, "")
        description = clean_description(description)
        
        # Skip interest/fee only entries with no meaningful description
        next if description.blank? && amount.abs < 1
        
        transactions << {
          date: date,
          amount: amount,
          description: description.presence || "ICICI CC Transaction",
          notes: "Imported from ICICI Credit Card statement"
        }
      end

      transactions.uniq { |t| [t[:date], t[:amount].to_s, t[:description]] }
    end
  end
end
