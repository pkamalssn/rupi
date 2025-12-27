# frozen_string_literal: true

module BankStatementParser
  class NpsStatement < Base
    # NPS (National Pension System) Statement parser
    # Parses CRA statement PDFs
    
    def parse
      if pdf_file?
        text = if scanned_pdf?
          extract_text_with_ocr
        elsif password_protected? && password.present?
          decrypt_pdf_and_extract_text
        else
          extract_text_from_pdf
        end
        parse_statement_from_text(text)
      else
        raise UnsupportedFormatError, "NPS statements are typically PDF format"
      end
    rescue PasswordRequiredError
      raise
    rescue => e
      raise ParseError, "Failed to parse NPS statement: #{e.message}"
    end

    # Returns structured NPS data instead of transactions
    def parse_statement_from_text(text)
      {
        account_info: extract_account_info(text),
        contributions: extract_contributions(text),
        holdings: extract_holdings(text),
        transactions: extract_transactions(text)
      }
    end

    private

    def extract_account_info(text)
      info = {}
      
      # Extract PRAN (Permanent Retirement Account Number)
      if match = text.match(/PRAN[:\s]*(\d{12})/i)
        info[:pran] = match[1]
      end
      
      # Extract name
      if match = text.match(/Name[:\s]*([A-Za-z\s]+)/i)
        info[:name] = match[1].strip
      end
      
      # Extract NPS type (All Citizens / Corporate / Government)
      if match = text.match(/(All\s*Citizens|Corporate|Government)\s*Model/i)
        info[:nps_type] = match[1]
      end
      
      # Extract Tier (I or II)
      if match = text.match(/Tier[:\s]*(I{1,2}|1|2)/i)
        info[:tier] = match[1].gsub(/1/, "I").gsub(/2/, "II")
      end
      
      info
    end

    def extract_contributions(text)
      contributions = []
      
      # Look for contribution patterns
      # Format varies but typically: Date, Amount, Type (Employee/Employer/Voluntary)
      lines = text.split("\n")
      
      lines.each do |line|
        next unless line.match?(/contribution|deposit/i)
        next unless line.match?(/\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/)
        
        if date_match = line.match(/(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/)
          date = parse_date(date_match[1])
          next unless date
          
          if amount_match = line.match(/([\d,]+\.?\d*)\s*(Rs|INR|₹)?/i)
            amount = BigDecimal(amount_match[1].gsub(",", ""))
            
            contribution_type = if line.match?(/employer/i)
              "Employer"
            elsif line.match?(/voluntary/i)
              "Voluntary"
            else
              "Employee"
            end
            
            contributions << {
              date: date,
              amount: amount,
              type: contribution_type,
              description: clean_description(line)
            }
          end
        end
      end
      
      contributions
    end

    def extract_holdings(text)
      holdings = []
      
      # NPS fund options: E (Equity), C (Corporate Bonds), G (Government Securities), A (Alternative)
      fund_patterns = {
        "E" => /Equity|Scheme\s*E/i,
        "C" => /Corporate|Scheme\s*C/i,
        "G" => /Government|Scheme\s*G|Gilt/i,
        "A" => /Alternative|Scheme\s*A/i
      }
      
      lines = text.split("\n")
      
      lines.each do |line|
        fund_patterns.each do |code, pattern|
          next unless line.match?(pattern)
          
          # Look for units and NAV
          if units_match = line.match(/([\d,]+\.?\d*)\s*units?/i)
            units = BigDecimal(units_match[1].gsub(",", ""))
            
            nav = nil
            if nav_match = line.match(/NAV[:\s]*([\d.]+)|@\s*([\d.]+)/i)
              nav = BigDecimal(nav_match[1] || nav_match[2])
            end
            
            value = nil
            if value_match = line.match(/value[:\s]*([\d,]+\.?\d*)|₹\s*([\d,]+\.?\d*)/i)
              value = BigDecimal((value_match[1] || value_match[2]).gsub(",", ""))
            end
            
            value ||= units * nav if nav
            
            holdings << {
              fund_type: code,
              fund_name: fund_name_for_code(code),
              units: units,
              nav: nav,
              value: value
            }
          end
        end
      end
      
      # Also try to extract total value
      if match = text.match(/Total\s*Value[:\s]*([\d,]+\.?\d*)|Net\s*Asset[:\s]*([\d,]+\.?\d*)/i)
        holdings << {
          fund_type: "TOTAL",
          fund_name: "Total NPS Value",
          value: BigDecimal((match[1] || match[2]).gsub(",", ""))
        }
      end
      
      holdings
    end

    def extract_transactions(text)
      transactions = []
      
      lines = text.split("\n")
      
      lines.each do |line|
        next unless line.match?(/\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/)
        
        if date_match = line.match(/(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/)
          date = parse_date(date_match[1])
          next unless date
          
          if amount_match = line.match(/([\d,]+\.?\d*)/)
            amount_str = amount_match[1].gsub(",", "")
            next if amount_str.empty? || amount_str == "0"
            
            amount = BigDecimal(amount_str)
            
            # Determine transaction type
            is_contribution = line.match?(/contribution|deposit|credit/i)
            is_withdrawal = line.match?(/withdrawal|redemption|debit/i)
            
            next unless is_contribution || is_withdrawal
            
            amount = -amount if is_withdrawal

            transactions << {
              date: date,
              amount: amount,
              description: is_contribution ? "NPS Contribution" : "NPS Withdrawal",
              notes: "Imported from NPS statement"
            }
          end
        end
      end
      
      transactions.uniq { |t| [t[:date], t[:amount].to_s] }
    end

    def fund_name_for_code(code)
      {
        "E" => "NPS Equity (Scheme E)",
        "C" => "NPS Corporate Bonds (Scheme C)",
        "G" => "NPS Government Securities (Scheme G)",
        "A" => "NPS Alternative Assets (Scheme A)"
      }[code] || "NPS Fund"
    end
  end
end
