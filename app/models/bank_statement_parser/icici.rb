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
        
        # Memory efficient: Split by page and process lines directly
        lines = []
        reader.pages.each do |page| 
          lines.concat(page.text.split("\n"))
          
          # Metadata Extraction
          if match = page.text.match(/Opening Balance\s*[:\-]?\s*([\d,]+\.\d{2})/i)
             @metadata[:opening_balance] = parse_amount(match[1])
          end
          if match = page.text.match(/Closing Balance\s*[:\-]?\s*([\d,]+\.\d{2})/i)
             @metadata[:closing_balance] = parse_amount(match[1])
          end
        end
        
        return lines
      rescue PDF::Reader::EncryptedPDFError, PDF::Reader::MalformedPDFError => e
      # Try with HexaPDF and empty password
      Rails.logger.info("ICICI PDF encrypted, trying empty password...")
      
      doc = HexaPDF::Document.open(file_path, decryption_opts: { password: password.presence || "" })
      doc.encrypt(name: nil)
      
      temp = Tempfile.new(['icici_decrypted', '.pdf'])
      doc.write(temp.path)
      
      reader = PDF::Reader.new(temp.path)
      lines = []
      reader.pages.each do |page| 
        lines.concat(page.text.split("\n"))
        
        # Metadata Extraction
        if match = page.text.match(/Opening Balance\s*[:\-]?\s*([\d,]+\.\d{2})/i)
           @metadata[:opening_balance] = parse_amount(match[1])
        end
        if match = page.text.match(/Op\. Balance\s*[:\-]?\s*([\d,]+\.\d{2})/i)
           @metadata[:opening_balance] = parse_amount(match[1])
        end
        if match = page.text.match(/Closing Balance\s*[:\-]?\s*([\d,]+\.\d{2})/i)
           @metadata[:closing_balance] = parse_amount(match[1])
        end
        if match = page.text.match(/Cl\. Balance\s*[:\-]?\s*([\d,]+\.\d{2})/i)
           @metadata[:closing_balance] = parse_amount(match[1])
        end
      end
      temp.unlink
      
      parse_transactions_from_text(lines)
      end
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

    def parse_transactions_from_text(lines)
      # Compatibility wrapper
      if lines.is_a?(String)
        lines = lines.split("\n")
      end

      # AI PARSING PATH
      api_key = ENV["GOOGLE_AI_API_KEY"].presence || ENV["GEMINI_API_KEY"].presence
      
      if api_key.present?
        begin
          Rails.logger.info "Attempting ICICI Parsing with Gemini AI..."
          return parse_with_gemini(lines.join("\n"), api_key)
        rescue => e
          Rails.logger.error "Gemini Parsing Failed: #{e.message}. Falling back to Regex."
          Rails.logger.error e.backtrace.join("\n")
        end
      end

      # Fallback to Regex
      parse_with_regex(lines)
    end

    def parse_with_gemini(text, api_key)
      require "json"
      
      prompt = <<~PROMPT
        You are a precise financial data extraction engine. 
        Extract relevant bank transactions from the provided ICICI Bank Statement text.

        OUTPUT FORMAT:
        Return a single valid JSON object with this structure:
        {
          "metadata": {
            "opening_balance": 0.0,
            "closing_balance": 0.0
          },
          "transactions": [
            {
              "date": "YYYY-MM-DD",
              "description": "Clean Description",
              "amount": 0.0,
              "balance": 0.0
            }
          ]
        }

        RULES:
        1. **Date**: Convert to YYYY-MM-DD.
        2. **Amount**: 
           - NEGATIVE for Debits/Withdrawals.
           - POSITIVE for Credits/Deposits.
           - Ensure correct polarity based on "Withdrawal" vs "Deposit" columns or context.
        3. **Balance**: Extract the running balance for the row.
        4. **Order**: Maintain the order found in the text.
        5. **Metadata**:
           - opening_balance: Balance BEFORE the transactions in this period.
           - closing_balance: Balance AFTER the transactions in this period.
        6. **Extract ALL transactions**. Do not summarize.
        7. **Ignore Headers/Page numbers**.

        TEXT CONTENT:
        #{text.truncate(900_000)} 
      PROMPT

      client = ::Provider::Gemini.new(api_key)
      
      response = client.chat_response(
        prompt,
        model: "gemini-3-flash-preview",
        family: nil
      )
      
      json_str = response.to_s
      json_str = json_str.gsub(/```json/, "").gsub(/```/, "")
      
      data = JSON.parse(json_str)
      
      if meta = data["metadata"]
        @metadata[:opening_balance] = meta["opening_balance"]&.to_f
        @metadata[:closing_balance] = meta["closing_balance"]&.to_f
      end
      
      data["transactions"].map do |tx|
        {
          date: parse_date(tx["date"]),
          amount: tx["amount"]&.to_f,
          description: clean_description(tx["description"]),
          notes: "Imported from ICICI via Gemini AI",
          _running_balance: tx["balance"]&.to_f
        }
      end
    end

    def parse_with_regex(lines)
      transactions = []
      current_txn = nil
      last_balance = nil
      
      # Tracking for Metadata (Reverse Chronological)
      closing_balance_found = false

      lines.each do |line|
        line = line.strip
        next if line.empty?
        next if line.match?(/^(S No|Value Date|Transaction|Search|Account Number|Transactions List|Page \d)/i)
        
        # Check for date pattern (handle optional S No at start)
        # Pattern: [optional S No] DD/MM/YYYY DD/MM/YYYY
        if match = line.match(/^\s*\d*\s*(\d{2}\/\d{2}\/\d{4})\s+(\d{2}\/\d{2}\/\d{4})/)
          # Save previous transaction if exists
          if current_txn && current_txn[:amount]
            transactions << current_txn
          end
          
          value_date = parse_date(match[1])
          
          # Remove Date from line to avoid scanning year as amount
          line_content = line.sub(match[0], "").strip
          
          # Extract all potential numbers (amounts), KEEPING ZEROS
          # Include optional negative sign for ODraft balances
          amounts_found = line_content.scan(/(-?[\d,]+\.?\d{0,2})/).flatten.map { |s| parse_amount(s) }.compact
          # Do NOT filter out zeros, as 0.00 is significant for column positioning
          amounts = amounts_found
          

          
          amount = nil
          balance = nil
          
          if amounts.length >= 3
            # Explicit Columns Detected: Withdrawal | Deposit | Balance
            balance = amounts.last
            deposit = amounts[-2]
            withdrawal = amounts[-3]
            
            # Sanity check: One should be zero ideally, or both non-zero (rare)
            if withdrawal > 0
              amount = -withdrawal
            elsif deposit > 0
              amount = deposit
            else
              # Both zero? Rare.
              amount = 0
            end

            # Capture Closing Balance (First processed row)
            unless closing_balance_found
               @metadata[:closing_balance] = balance
               closing_balance_found = true
            end
            
            last_balance = balance

          elsif amounts.length == 2
            # Fallback for lines where 0.00 is missing/merged
            balance = amounts.last
            raw_amount = amounts[-2] 
            
            # Capture Closing Balance
            unless closing_balance_found
               @metadata[:closing_balance] = balance
               closing_balance_found = true
            end

            # ICICI Statement is REVERSE CHRONOLOGICAL (Newest First)
            if last_balance
              diff = last_balance - balance
              
              if (diff.abs - raw_amount.abs).abs < 1.0
                 if diff > 0
                   amount = raw_amount.abs # Credit
                 else
                   amount = -raw_amount.abs # Debit
                 end
              else
                 # Fallback
                 amount = -raw_amount.abs
              end
            else
              # First entry
              amount = -raw_amount.abs
            end
            
            last_balance = balance
          else
             # Dropped Row
          end
          
          description = line.sub(match[0], "").strip
          description = description.gsub(/[\d,]+\.\d{2}/, "").strip
          
          current_txn = {
            date: value_date,
            amount: amount, 
            description: clean_description(description),
            notes: "Imported from ICICI statement",
            _running_balance: balance # Internal for debug
          }
        elsif current_txn && !line.match?(/^\d/)
          # Continuation of description
          current_txn[:description] = [current_txn[:description], clean_description(line)].compact.join(" ")
        end
      end
      
      if current_txn && current_txn[:amount]
        transactions << current_txn
      end


      
      # Get Opening Balance from oldest transaction's balance BEFORE its amount
      if last_txn = transactions.last
        if last_balance = last_txn[:_running_balance]
          # Opening = Balance - Amount (reverse the transaction)
          @metadata[:opening_balance] = (last_balance - last_txn[:amount]).round(2)
        end
      end
      
      # Closing balance already set from first row

      # Cleanup internal key
      transactions.each do |t|
        t.delete(:_running_balance)
        t[:description] = t[:description].to_s.squeeze(" ").strip.presence || "ICICI Transaction"
      end

      transactions
    end
  end
end
