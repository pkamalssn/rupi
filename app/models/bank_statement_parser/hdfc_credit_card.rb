# frozen_string_literal: true

module BankStatementParser
  class HdfcCreditCard < Base
    # HDFC Credit Card statement parser (Regalia Gold, etc.)
    
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
      else
        raise UnsupportedFormatError, "HDFC Credit Card statements are typically PDF format"
      end
    rescue PasswordRequiredError
      raise
    rescue => e
      raise ParseError, "Failed to parse HDFC Credit Card statement: #{e.message}"
    end

    private

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")
      
      lines.each do |line|
        # Skip irrelevant lines
        next if line.strip.empty?
        next if line.strip.length < 20
        
        # Look for transaction lines with dates: DD/MM/YYYY or DD/MM/YYYY| HH:MM
        if date_match = line.match(/(\d{2}\/\d{2}\/\d{4})/)
          date = parse_date(date_match[1])
          next unless date
          
          # Look for amounts - HDFC CC uses C for rupee symbol
          # Format: "C 36,878.00" or "C36,878.00" or "₹ 1,234.56"
          if amt_match = line.match(/[C₹]\s*([\d,]+\.\d{2})/i)
            amount = BigDecimal(amt_match[1].gsub(",", ""))
            next if amount == 0
            
            # Determine if this is a credit or debit:
            # - Payments/Refunds/Cashback = Credit (positive for CC liability)
            # - Purchases/EMI = Debit (negative for CC liability)
            description = extract_cc_description(line, date_match[0])
            
            # Payment identifiers:
            # - "ST" followed by numbers = Statement payment reference (NEFT/IMPS)
            # - "NEFT" or "IMPS" in line = Payment received
            # - "credit" or "refund" keywords
            # Note: "EMI" is NOT a payment - it's a purchase on EMI!
            is_payment = line.match?(/ST\d{5,}/) ||  # ST253440083000010462891
                         line.downcase.match?(/neft.*cr|imps.*cr|payment.*received|refund|cashback|reversal/)
            
            # For credit card: 
            # - Purchases ADD to liability (negative from user perspective = money spent)
            # - Payments REDUCE liability (positive = money paid back)
            if is_payment
              amount = amount.abs  # Payment reduces what you owe
            else
              amount = -amount.abs  # Purchase increases what you owe
            end

            transactions << {
              date: date,
              amount: amount,
              description: description.presence || "HDFC CC Transaction",
              notes: "Imported from HDFC Credit Card statement"
            }
          end
        end
      end

      # Deduplicate based on date + amount + description
      transactions.uniq { |t| [t[:date], t[:amount].to_s, t[:description]] }
    end

    def extract_cc_description(line, date_str)
      desc = line.dup
      
      # Remove date and time
      desc = desc.gsub(/\d{2}\/\d{2}\/\d{4}\|?\s*\d{0,2}:?\d{0,2}/, "")
      
      # Remove amount patterns
      desc = desc.gsub(/[C₹]\s*[\d,]+\.\d{2}/, "")
      
      # Remove common noise
      desc = desc.gsub(/\+\s*\d+/, "")  # Points like "+ 8" or "+ 1148"
      desc = desc.gsub(/EMI/, "")
      desc = desc.gsub(/\s+l$/, "")  # Trailing 'l'
      desc = desc.gsub(/EUR\s*[\d.]+/, "")  # Foreign currency
      
      clean_description(desc)
    end
  end
end
