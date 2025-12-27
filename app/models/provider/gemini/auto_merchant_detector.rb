class Provider::Gemini::AutoMerchantDetector
  attr_reader :connection, :api_key, :model, :transactions, :user_merchants, :family

  def initialize(connection, api_key:, model: "", transactions: [], user_merchants: [], family: nil)
    @connection = connection
    @api_key = api_key
    @model = model.presence || Provider::Gemini::DEFAULT_MODEL
    @transactions = transactions
    @user_merchants = user_merchants
    @family = family
  end

  def auto_detect_merchants
    endpoint = "/v1beta/models/#{model}:generateContent?key=#{api_key}"

    payload = {
      contents: [{
        parts: [{
          text: full_prompt
        }]
      }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: json_schema
      }
    }

    response = @connection.post(endpoint) do |req|
      req.body = payload
    end

    raw_json = extract_json_from_response(response.body)
    detections = JSON.parse(raw_json).dig("merchant_detections")

    result = build_response(detections)

    # Record usage
    usage = map_gemini_usage(response.body.dig("usageMetadata"))
    record_usage(usage)

    result
  rescue => e
    Rails.logger.error("Gemini merchant detection failed: #{e.message}")
    raise Provider::Gemini::Error, "Merchant detection failed: #{e.message}"
  end

  private

  def full_prompt
    <<~PROMPT.strip_heredoc
      #{instructions}

      KNOWN MERCHANTS:
      #{user_merchants.map { |m| "- #{m[:name]}" }.join("\n")}

      TRANSACTIONS TO ANALYZE:
      #{format_transactions}
    PROMPT
  end

  def instructions
    <<~INSTRUCTIONS.strip_heredoc
      You are an assistant to a consumer personal finance app. You will be provided a list
      of transactions and a list of the user's known merchants. Your job is to detect which
      merchant each transaction belongs to.

      Rules:
      - Return 1 result per transaction
      - Correlate each transaction by ID (transaction_id)
      - Try to match the transaction description to a known merchant name
      - Merchants may appear with slight variations in the description (e.g., "AMAZON", "Amazon.com", "AMZN*")
      - If you don't recognize the merchant, return "null" for both business_name and business_url
      - For recognized merchants, include their website URL if known (e.g., "https://amazon.com")
      - Return "null" if you're less than 70% confident in the match

      IMPORTANT:
      - Use EXACT merchant names from the provided list
      - Focus on the merchant/business name, not the transaction type
      - Be conservative - prefer "null" over false positives
    INSTRUCTIONS
  end

  def format_transactions
    transactions.map do |t|
      "- ID: #{t[:id]}, Description: \"#{t[:description]}\""
    end.join("\n")
  end

  def json_schema
    {
      type: "object",
      properties: {
        merchant_detections: {
          type: "array",
          description: "An array of merchant detections for each transaction",
          items: {
            type: "object",
            properties: {
              transaction_id: {
                type: "string",
                description: "The internal ID of the original transaction",
                enum: transactions.map { |t| t[:id].to_s }
              },
              business_name: {
                type: "string",
                description: "The matched merchant name, or null if not recognized",
                enum: [*user_merchants.map { |m| m[:name] }, "null"]
              },
              business_url: {
                type: "string",
                description: "The website URL of the merchant (e.g., https://amazon.com)"
              }
            },
            required: ["transaction_id", "business_name", "business_url"]
          }
        }
      },
      required: ["merchant_detections"]
    }
  end

  def extract_json_from_response(body)
    raw = body.dig("candidates", 0, "content", "parts", 0, "text")
    raise Provider::Gemini::Error, "No content found in response" if raw.nil?

    cleaned = raw.gsub(/^```json\s*/, "").gsub(/^```\s*/, "").gsub(/```\s*$/, "").strip
    cleaned
  end

  def build_response(detections)
    detections.map do |detection|
      Provider::LlmConcept::AutoDetectedMerchant.new(
        transaction_id: detection.dig("transaction_id"),
        business_name: normalize_merchant_name(detection.dig("business_name")),
        business_url: detection.dig("business_url")
      )
    end
  end

  def normalize_merchant_name(merchant_name)
    return nil if merchant_name.nil? || merchant_name == "null"

    normalized = merchant_name.to_s.strip
    return nil if normalized.empty? || normalized.downcase == "null"

    normalized
  end

  def map_gemini_usage(usage_metadata)
    return {} unless usage_metadata

    {
      "prompt_tokens" => usage_metadata["promptTokenCount"] || 0,
      "completion_tokens" => usage_metadata["candidatesTokenCount"] || 0,
      "total_tokens" => usage_metadata["totalTokenCount"] || 0
    }
  end

  def record_usage(usage_data)
    return unless family && usage_data

    prompt_tokens = usage_data["prompt_tokens"] || 0
    completion_tokens = usage_data["completion_tokens"] || 0
    total_tokens = usage_data["total_tokens"] || 0

    estimated_cost = LlmUsage.calculate_cost(
      model: model,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens
    )

    family.llm_usages.create!(
      provider: "google",
      model: model,
      operation: "auto_detect_merchants",
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens,
      estimated_cost: estimated_cost,
      metadata: {
        transaction_count: transactions.size,
        merchant_count: user_merchants.size
      }
    )

    Rails.logger.info("Gemini merchant detection usage - Cost: #{estimated_cost.inspect}")
  rescue => e
    Rails.logger.error("Failed to record Gemini usage: #{e.message}")
  end
end
