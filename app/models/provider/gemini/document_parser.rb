# frozen_string_literal: true

class Provider::Gemini::DocumentParser
  Error = Class.new(StandardError)

  LOAN_EXTRACTION_PROMPT = <<~PROMPT
    You are an expert financial document analyzer specializing in Indian loan documents.
    
    Analyze this loan document image and extract the following information.
    Return ONLY a valid JSON object with these fields:
    
    {
      "lender_name": "Name of the bank/NBFC (e.g., HDFC Bank, ICICI Bank, Cred, Bajaj Finance)",
      "loan_type": "One of: home_loan, personal, car_loan, education_loan, gold, business, lap, two_wheeler, consumer_durable, other",
      "principal_amount": 0,
      "currency": "INR",
      "interest_rate": 0.0,
      "rate_type": "fixed or floating",
      "tenure_months": 0,
      "emi_amount": 0,
      "emi_day": 0,
      "disbursement_date": "YYYY-MM-DD or null",
      "loan_account_number": "string or null",
      "outstanding_balance": 0,
      "maturity_date": "YYYY-MM-DD or null",
      "processing_fee": 0,
      "prepayment_charges": "string description or null",
      "confidence": 0.0,
      "notes": "Any additional relevant information from the document",
      "transactions": [
        {
          "date": "YYYY-MM-DD",
          "amount": 0.0,
          "type": "payment or interest or disbursement or prepayment or charge",
          "description": "Transaction description",
          "principal_component": 0.0,
          "interest_component": 0.0
        }
      ]
    }
    
    Rules:
    1. For amounts, extract numeric values only (no commas, no currency symbols)
    2. Interest rate should be annual percentage (e.g., 8.5 for 8.5% p.a.)
    3. Tenure should be in months (convert years to months if needed)
    4. EMI day is the day of the month when EMI is debited (1-28)
    5. Confidence should be 0.0 to 1.0 based on how clearly you could extract the data
    6. If a field cannot be determined, use null for strings/dates, 0 for numbers
    7. For loan_type, map common variations:
       - "Housing Loan" / "Mortgage" / "HOUSING" / "Property Loan" → "home_loan"
       - "Personal Loan" / "Consumer Loan" → "personal"
       - "Vehicle Loan" / "Auto Loan" → "car_loan"
       - "Education Loan" / "Student Loan" → "education_loan"
       - "Loan Against Property" → "lap"
    
    8. TRANSACTION EXTRACTION (CRITICAL - EXTRACT EVERY ROW):
       
       ⚠️ IMPORTANT: You MUST extract EVERY SINGLE transaction row from ALL pages of the document.
       Do NOT summarize. Do NOT skip rows. Extract each row individually.
       If there are 50 EMI payments, return all 50 transactions.
       
       For AMORTIZATION SCHEDULES (Home Loans, etc.):
       - Scan ALL PAGES of the document, not just the first page
       - Each row in the EMI table represents one payment - extract EVERY row marked "Amrt"
       - Each row becomes one transaction object:
         {
           "date": "end date of that EMI period (To Date column, e.g., 2021-10-31)",
           "amount": "EMI amount paid (from EMI column)",
           "type": "payment",
           "description": "EMI Payment",
           "principal_component": "Principal paid portion (from Princ column)",
           "interest_component": "Interest paid portion (from Int column)"
         }
       - PREPAYMENTS: Rows with values in "Prep/Adj/Disb" column (usually negative) are prepayments:
         {
           "date": "date of prepayment",
           "amount": "absolute prepayment amount",
           "type": "prepayment",
           "description": "Loan Prepayment"
         }
       - ONLY extract rows where column says "Amrt" (Amortization = Actual paid).
       - SKIP rows where column says "Proj" (Projected = Future estimates).
       
       For PERSONAL LOAN STATEMENTS / LEDGERS:
       - Extract EVERY transaction row from the ledger
       - 'payment': EMI received, Payment Received
       - 'disbursement': Initial loan amount disbursed
       - 'interest': Interest applied/charged
       - 'charge': Fees, penalties, bounced EMI charges
       - SKIP "Due for Installment" / "EMI Due" entries (demand notices, not actual transactions)
    
    9. For outstanding_balance: Use the closing balance from the LAST "Amrt" row (not "Proj" rows)
    
    Return ONLY the JSON object, no markdown formatting, no explanation.
  PROMPT

  def initialize(connection, api_key:, model:)
    @connection = connection
    @api_key = api_key
    @model = model
  end

  def parse_loan_document(file)
    # Read file and convert to base64
    file_content = read_file_content(file)
    mime_type = detect_mime_type(file)
    base64_data = Base64.strict_encode64(file_content)

    # Build request with image
    response = make_api_request(base64_data, mime_type)
    
    # Parse and validate response
    parse_response(response)
  end

  private

  def read_file_content(file)
    if file.respond_to?(:download)
      # ActiveStorage attachment
      file.download
    elsif file.respond_to?(:read)
      # File object or uploaded file
      file.rewind if file.respond_to?(:rewind)
      file.read
    elsif file.is_a?(String) && File.exist?(file)
      # File path
      File.read(file, mode: 'rb')
    else
      raise Error, "Unable to read file content"
    end
  end

  def detect_mime_type(file)
    if file.respond_to?(:content_type)
      file.content_type
    elsif file.respond_to?(:original_filename)
      mime_from_filename(file.original_filename)
    elsif file.is_a?(String)
      mime_from_filename(file)
    else
      "application/octet-stream"
    end
  end

  def mime_from_filename(filename)
    ext = File.extname(filename).downcase
    case ext
    when ".pdf" then "application/pdf"
    when ".png" then "image/png"
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".webp" then "image/webp"
    when ".gif" then "image/gif"
    else "application/octet-stream"
    end
  end

  def make_api_request(base64_data, mime_type)
    # Gemini 3 compatibility: use default temperature (1.0), avoid low values
    gen_config = if @model.start_with?("gemini-3")
      {
        topP: 0.95,
        maxOutputTokens: 16384  # Higher limit for large transaction tables
      }
    else
      {
        temperature: 0.1,
        topP: 0.95,
        maxOutputTokens: 16384
      }
    end

    body = {
      contents: [
        {
          parts: [
            { text: LOAN_EXTRACTION_PROMPT },
            {
              inline_data: {
                mime_type: mime_type,
                data: base64_data
              }
            }
          ]
        }
      ],
      generationConfig: gen_config
    }

    response = @connection.post("/v1beta/models/#{@model}:generateContent?key=#{@api_key}") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = body.to_json
    end

    unless response.success?
      error_message = begin
        body = response.body
        if body.is_a?(Hash)
          body.dig("error", "message") || body.to_s
        else
          JSON.parse(body).dig("error", "message") || body
        end
      rescue
        response.body.to_s
      end
      raise Error, "Gemini API error: #{error_message}"
    end

    response
  end

  def parse_response(response)
    body = response.body
    body = JSON.parse(body) if body.is_a?(String)
    
    
    # Extract text from response
    text = body.dig("candidates", 0, "content", "parts", 0, "text")
    
    unless text.present?
      raise Error, "No response from Gemini"
    end

    # Clean up the response (remove markdown if present)
    json_text = text.strip
    
    # Try to extract JSON from code blocks first
    if json_text.include?("```")
      json_text = json_text.gsub(/```json\s*/i, "").gsub(/```/, "")
    end

    # Fallback: Find the first { and last } to isolate the object
    if json_text.include?("{") && json_text.include?("}")
      first_brace = json_text.index("{")
      last_brace = json_text.rindex("}")
      json_text = json_text[first_brace..last_brace]
    end

    # Parse JSON with repair attempts
    data = nil
    begin
      data = JSON.parse(json_text)
    rescue JSON::ParserError => e
      Rails.logger.warn("Initial JSON parse failed: #{e.message}")
      
      # Try to repair common issues
      repaired = repair_json(json_text)
      begin
        data = JSON.parse(repaired)
        Rails.logger.info("JSON repair successful")
      rescue JSON::ParserError => e2
        Rails.logger.error("AI Raw Response (first 2000 chars): #{text[0..2000]}")
        Rails.logger.error("JSON repair also failed: #{e2.message}")
        
        # Last resort: Try to extract just the base fields without transactions
        begin
          # Remove the transactions array and try again
          simple_json = json_text.sub(/"transactions"\s*:\s*\[.*$/m, '"transactions": []}')
          data = JSON.parse(simple_json)
          Rails.logger.info("Parsed without transactions array")
        rescue
          raise Error, "Failed to parse AI response: #{e.message}"
        end
      end
    end

    # Validate and normalize the extracted data
    normalize_extracted_data(data)
  end

  # Attempt to repair truncated/malformed JSON
  def repair_json(json_str)
    repaired = json_str.dup
    
    # Count braces and brackets
    open_braces = repaired.count("{")
    close_braces = repaired.count("}")
    open_brackets = repaired.count("[")
    close_brackets = repaired.count("]")
    
    # If we have unclosed brackets (common with truncated transaction arrays)
    # Try to close them
    if open_brackets > close_brackets
      # Find where the transactions array starts
      tx_start = repaired.index('"transactions"')
      if tx_start
        # Try to find the last complete transaction object
        last_complete_obj = repaired.rindex("},")
        if last_complete_obj && last_complete_obj > tx_start
          # Truncate at the last complete object and close properly
          repaired = repaired[0..last_complete_obj] + "}]}"
        else
          # Just close all open brackets and braces
          (open_brackets - close_brackets).times { repaired += "]" }
          (open_braces - close_braces).times { repaired += "}" }
        end
      end
    end
    
    # Fix trailing commas before closing brackets/braces
    repaired.gsub!(/,\s*\]/, "]")
    repaired.gsub!(/,\s*\}/, "}")
    
    repaired
  end

  def normalize_extracted_data(data)
    {
      lender_name: data["lender_name"].presence,
      loan_type: normalize_loan_type(data["loan_type"]),
      principal_amount: data["principal_amount"].to_f,
      currency: data["currency"].presence || "INR",
      interest_rate: data["interest_rate"].to_f,
      rate_type: normalize_rate_type(data["rate_type"]),
      tenure_months: data["tenure_months"].to_i,
      emi_amount: data["emi_amount"].to_f,
      emi_day: normalize_emi_day(data["emi_day"]),
      disbursement_date: parse_date(data["disbursement_date"]),
      loan_account_number: data["loan_account_number"].presence,
      outstanding_balance: data["outstanding_balance"].to_f,
      maturity_date: parse_date(data["maturity_date"]),
      processing_fee: data["processing_fee"].to_f,
      prepayment_charges: data["prepayment_charges"].presence,
      confidence: data["confidence"].to_f.clamp(0.0, 1.0),
      notes: data["notes"].presence,
      transactions: normalize_transactions(data["transactions"])
    }
  end

  def normalize_transactions(transactions)
    return [] unless transactions.is_a?(Array)
    
    transactions.map do |tx|
      type = normalize_transaction_type(tx["type"])
      {
        date: parse_date(tx["date"]),
        amount: tx["amount"].to_f.abs,
        type: type,
        description: tx["description"],
        principal_component: tx["principal_component"].to_f.abs,
        interest_component: tx["interest_component"].to_f.abs
      }
    end.select { |tx| tx[:date].present? && tx[:amount] > 0 }
  end

  def normalize_transaction_type(type)
    return "payment" if type.blank?
    
    case type.to_s.downcase
    when "payment", "emi", "emi payment" then "payment"
    when "prepayment", "prepay", "part payment", "partial prepayment" then "prepayment"
    when "interest", "interest charged" then "interest"
    when "disbursement", "disbursal" then "disbursement"
    when "charge", "fee", "penalty" then "charge"
    else "payment"
    end
  end

  def normalize_loan_type(type)
    return "other" if type.blank?
    
    valid_types = %w[home_loan personal car_loan education_loan gold business lap two_wheeler consumer_durable other mortgage student auto]
    
    normalized = type.to_s.downcase.gsub(/\s+/, "_")
    
    # Map variations
    case normalized
    when "mortgage", "housing_loan", "home" then "home_loan"
    when "student", "student_loan" then "education_loan"
    when "auto", "vehicle_loan", "car", "vehicle" then "car_loan"
    when "consumer", "consumer_loan" then "consumer_durable"
    else
      valid_types.include?(normalized) ? normalized : "other"
    end
  end

  def normalize_rate_type(type)
    return "fixed" if type.blank?
    
    case type.to_s.downcase
    when "floating", "variable", "adjustable" then "floating"
    else "fixed"
    end
  end

  def normalize_emi_day(day)
    day_int = day.to_i
    day_int.between?(1, 28) ? day_int : nil
  end

  def parse_date(date_str)
    return nil if date_str.blank?
    
    Date.parse(date_str.to_s)
  rescue Date::Error
    nil
  end
end
