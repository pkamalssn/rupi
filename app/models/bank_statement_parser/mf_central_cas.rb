# frozen_string_literal: true

module BankStatementParser
  class MfCentralCas < Base
    # MFCentral Consolidated Account Statement (CAS) parser
    # Parses the PDF from MFCentral containing all mutual fund holdings
    
    def parse
      if pdf_file?
        text = if scanned_pdf?
          extract_text_with_ocr
        elsif password_protected? && password.present?
          decrypt_pdf_and_extract_text
        else
          extract_text_from_pdf
        end
        parse_cas_from_text(text)
      else
        raise UnsupportedFormatError, "MFCentral CAS statements are PDF format"
      end
    rescue PasswordRequiredError
      raise
    rescue => e
      raise ParseError, "Failed to parse MFCentral CAS: #{e.message}"
    end

    # Returns structured MF data
    def parse_cas_from_text(text)
      {
        investor_info: extract_investor_info(text),
        holdings: extract_holdings(text),
        transactions: extract_transactions(text),
        summary: extract_summary(text)
      }
    end

    private

    def extract_investor_info(text)
      info = {}
      
      if match = text.match(/PAN[:\s]*([A-Z]{5}\d{4}[A-Z])/i)
        info[:pan] = match[1].upcase
      end
      
      if match = text.match(/Name[:\s]*([A-Za-z\s]+)/i)
        info[:name] = match[1].strip
      end
      
      if match = text.match(/Email[:\s]*([\w.+-]+@[\w.-]+)/i)
        info[:email] = match[1]
      end
      
      info
    end

    def extract_holdings(text)
      holdings = []
      current_amc = nil
      current_scheme = nil
      
      lines = text.split("\n")
      
      lines.each_with_index do |line, idx|
        # Detect AMC names
        if line.match?(/Mutual Fund|Asset Management|AMC/i) && !line.match?(/NAV|Units/i)
          current_amc = clean_amc_name(line)
          next
        end
        
        # Detect scheme names  
        if line.match?(/Direct|Regular|Growth|Dividend|IDCW/i) && line.length > 20
          current_scheme = clean_scheme_name(line)
        end
        
        # Extract holding data (units and NAV)
        if current_scheme && line.match?(/[\d,]+\.?\d*/)
          # Try to extract folio, units, NAV, value
          holding = extract_holding_from_line(line, current_amc, current_scheme)
          if holding
            holdings << holding
            current_scheme = nil
          end
        end
      end
      
      # Normalize holdings
      consolidate_holdings(holdings)
    end

    def extract_holding_from_line(line, amc, scheme)
      # Pattern 1: "Folio: 12345 | Units: 100.123 | NAV: 45.67 | Value: 4,573.02"
      # Pattern 2: "12345    100.123    45.67    4,573.02"
      
      numbers = line.scan(/([\d,]+\.?\d*)/).map { |m| m[0].gsub(",", "") }.reject(&:empty?)
      
      return nil if numbers.length < 2
      
      # Heuristics to identify which number is which
      units = nil
      nav = nil
      value = nil
      folio = nil
      
      numbers.each do |num|
        num_val = num.to_f
        if num_val > 1000 && num.length >= 5 && !num.include?(".")
          folio ||= num
        elsif num_val < 10000 && num.include?(".") && num_val > 0.01
          if nav.nil?
            nav = num_val
          else
            units ||= num_val
          end
        elsif num_val > 100
          value ||= num_val
        else
          units ||= num_val
        end
      end
      
      return nil unless units || value
      
      # Calculate missing value
      if units && nav && !value
        value = units * nav
      elsif value && nav && !units
        units = value / nav
      end
      
      {
        amc: amc,
        scheme: scheme,
        folio: folio,
        units: units ? BigDecimal(units.to_s) : nil,
        nav: nav ? BigDecimal(nav.to_s) : nil,
        value: value ? BigDecimal(value.to_s) : nil
      }
    end

    def extract_transactions(text)
      transactions = []
      
      lines = text.split("\n")
      current_scheme = nil
      
      lines.each do |line|
        # Detect scheme context
        if line.match?(/Direct|Regular|Growth/i) && line.length > 20
          current_scheme = clean_scheme_name(line)
        end
        
        # Look for transaction patterns
        if line.match?(/\d{1,2}[\/\-][A-Za-z]{3}[\/\-]\d{2,4}|\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/)
          if date_match = line.match(/(\d{1,2}[\/\-][A-Za-z]{3}[\/\-]\d{2,4})|(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/)
            date = parse_date(date_match[0])
            next unless date
            
            # Extract transaction type
            txn_type = if line.match?(/purchase|buy|sip|systematic/i)
              "Purchase"
            elsif line.match?(/redeem|sell|withdrawal/i)
              "Redemption"
            elsif line.match?(/switch.*in/i)
              "Switch In"
            elsif line.match?(/switch.*out/i)
              "Switch Out"
            elsif line.match?(/dividend|idcw/i)
              "Dividend"
            else
              "Transaction"
            end
            
            # Extract amount
            if amount_match = line.match(/([\d,]+\.\d{2})/)
              amount = BigDecimal(amount_match[1].gsub(",", ""))
              
              # Redemptions are positive (money in), purchases are negative (money out)
              amount = -amount if txn_type.include?("Purchase") || txn_type.include?("Switch In")

              transactions << {
                date: date,
                amount: amount,
                description: "#{current_scheme || 'MF'} - #{txn_type}",
                notes: "Imported from MFCentral CAS",
                metadata: {
                  scheme: current_scheme,
                  transaction_type: txn_type
                }
              }
            end
          end
        end
      end
      
      transactions
    end

    def extract_summary(text)
      summary = {}
      
      # Total portfolio value
      if match = text.match(/Total\s*Value[:\s]*([\d,]+\.?\d*)|Portfolio\s*Value[:\s]*([\d,]+\.?\d*)/i)
        summary[:total_value] = BigDecimal((match[1] || match[2]).gsub(",", ""))
      end
      
      # Total investment
      if match = text.match(/Total\s*Investment[:\s]*([\d,]+\.?\d*)|Cost[:\s]*([\d,]+\.?\d*)/i)
        summary[:total_investment] = BigDecimal((match[1] || match[2]).gsub(",", ""))
      end
      
      # Calculate gain/loss
      if summary[:total_value] && summary[:total_investment]
        summary[:gain_loss] = summary[:total_value] - summary[:total_investment]
        summary[:gain_loss_percent] = (summary[:gain_loss] / summary[:total_investment] * 100).round(2)
      end
      
      summary
    end

    def clean_amc_name(name)
      name.to_s
        .gsub(/Mutual Fund|Asset Management|AMC|Limited|Ltd/i, "")
        .gsub(/\s+/, " ")
        .strip
    end

    def clean_scheme_name(name)
      name.to_s
        .gsub(/\s+/, " ")
        .strip
        .truncate(100)
    end

    def consolidate_holdings(holdings)
      # Group by scheme and sum units/values
      grouped = holdings.group_by { |h| [h[:amc], h[:scheme], h[:folio]] }
      
      grouped.map do |(amc, scheme, folio), items|
        {
          amc: amc,
          scheme: scheme,
          folio: folio,
          units: items.map { |i| i[:units] }.compact.sum,
          nav: items.map { |i| i[:nav] }.compact.last,
          value: items.map { |i| i[:value] }.compact.sum
        }
      end
    end
  end
end
