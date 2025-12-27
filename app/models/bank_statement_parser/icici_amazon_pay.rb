# frozen_string_literal: true

module BankStatementParser
  class IciciAmazonPay < Base
    # ICICI Amazon Pay Credit Card statement parser
    
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
        raise UnsupportedFormatError, "ICICI Amazon Pay statements are typically PDF format"
      end
    rescue PasswordRequiredError
      raise
    rescue => e
      raise ParseError, "Failed to parse ICICI Amazon Pay statement: #{e.message}"
    end

    private

    def parse_transactions_from_text(text)
      transactions = []
      lines = text.split("\n")
      
      in_transactions_section = false
      current_date = nil
      
      lines.each do |line|
        # Detect start of transactions section
        if line.match?(/transaction.*details|statement.*transactions/i)
          in_transactions_section = true
          next
        end
        
        next unless in_transactions_section
        next if line.strip.empty?
        
        # Skip summary/total lines
        next if line.match?(/^(total|sub.*total|minimum|payment.*due|credit.*limit)/i)
        
        # Look for date
        if match = line.match(/(\d{1,2}[\/\-][A-Za-z]{3}[\/\-]\d{2,4})|(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/)
          parsed_date = parse_date(match[0])
          current_date = parsed_date if parsed_date
        end
        
        next unless current_date

        # Extract amount
        if amount_match = line.match(/([\d,]+\.\d{2})\s*(Cr|Dr)?/i)
          amount = BigDecimal(amount_match[1].gsub(",", ""))
          
          # Check if credit (payment, cashback) or debit (purchase)
          is_credit = amount_match[2]&.downcase == "cr" ||
                      line.downcase.match?(/credit|refund|cashback|reward|payment.*thank/)
          
          amount = -amount unless is_credit

          description = extract_description(line, amount_match[0])
          
          # Special handling for Amazon transactions
          if description.downcase.include?("amazon")
            description = categorize_amazon_transaction(description)
          end

          transactions << {
            date: current_date,
            amount: amount,
            description: description.presence || "ICICI Amazon Pay Transaction",
            notes: "Imported from ICICI Amazon Pay statement",
            rewards: extract_rewards(line)
          }
        end
      end

      transactions.uniq { |t| [t[:date], t[:amount].to_s, t[:description]] }
    end

    def extract_description(line, amount_match)
      desc = line.dup
      # Remove date patterns
      desc = desc.gsub(/\d{1,2}[\/\-][A-Za-z]{3}[\/\-]\d{2,4}/, "")
      desc = desc.gsub(/\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/, "")
      desc = desc.sub(amount_match, "")
      desc = desc.gsub(/\s*(Cr|Dr)\s*/i, "")
      clean_description(desc)
    end

    def categorize_amazon_transaction(description)
      case description.downcase
      when /prime/
        "Amazon Prime Subscription"
      when /fresh/
        "Amazon Fresh"
      when /pantry/
        "Amazon Pantry"
      when /kindle/
        "Amazon Kindle"
      when /aws|web.*services/
        "Amazon Web Services"
      else
        "Amazon Purchase"
      end
    end

    def extract_rewards(line)
      if match = line.match(/(\d+)\s*(reward|point|cashback)/i)
        match[1].to_i
      end
    end
  end
end
