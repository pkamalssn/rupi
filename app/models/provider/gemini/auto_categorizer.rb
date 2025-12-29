class Provider::Gemini::AutoCategorizer
  attr_reader :connection, :api_key, :model, :transactions, :user_categories, :family

  def initialize(connection, api_key:, model: "", transactions: [], user_categories: [], family: nil)
    @connection = connection
    @api_key = api_key
    @model = model.presence || Provider::Gemini::DEFAULT_MODEL
    @transactions = transactions
    @user_categories = user_categories
    @family = family
  end

  def auto_categorize
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
    categorizations = JSON.parse(raw_json).dig("categorizations")

    result = build_response(categorizations)

    # Record usage
    usage = map_gemini_usage(response.body.dig("usageMetadata"))
    record_usage(usage)

    result
  rescue => e
    Rails.logger.error("Gemini auto-categorization failed: #{e.message}")
    raise Provider::Gemini::Error, "Auto-categorization failed: #{e.message}"
  end

  private

  def full_prompt
    <<~PROMPT.strip_heredoc
      #{instructions}

      AVAILABLE CATEGORIES:
      #{user_categories.map { |c| "- #{c[:name]}" }.join("\n")}

      TRANSACTIONS TO CATEGORIZE:
      #{format_transactions}
    PROMPT
  end


  def instructions
    <<~INSTRUCTIONS.strip_heredoc
      You are an assistant to a consumer personal finance app for Indian users. You will be provided a list
      of the user's transactions and a list of their existing categories. Your job is to categorize
      each transaction - either to an existing category OR suggest a new appropriate category.

      RULES FOR CATEGORIZATION:

      1. EXISTING CATEGORIES (Preferred):
         - Match to existing categories from the provided list when possible
         - Use exact category names from the list
         - Match expense transactions only to expense categories
         - Match income transactions only to income categories
         - Only match if 60%+ confident

      2. SUGGEST NEW CATEGORIES (For unmatched transactions):
         - If no existing category fits, SUGGEST a new category name
         - Use clear, descriptive Indian-context names like:
           * "UPI Transfers" for personal UPI payments
           * "Paytm Payments" for PayTM merchant payments
           * "PhonePe" for PhonePe payments
           * "Google Pay" for GPay payments
           * "ATM Withdrawal" for ATM transactions
           * "NEFT/IMPS" for bank transfers
           * "Rent" for rent payments
           * "Salary" for salary credits
           * "Interest Earned" for bank interest
           * "EMI Payments" for loan EMIs
         - Prefix suggested categories with "NEW:" (e.g., "NEW:Paytm Payments")
         - Keep names short (2-3 words max)
         - Use Title Case

      3. UNKNOWN TRANSACTIONS:
         - Only return "null" if the transaction is truly unidentifiable
         - Examples: encrypted references, blank descriptions
         - DO NOT return null for recognizable patterns like UPI, PayTM, PhonePe

      INDIAN TRANSACTION PATTERNS TO RECOGNIZE:
      - UPI: "UPIOUT", "UPIIN", "@oksbi", "@okaxis", "@okhdfcbank", "@ybl", "@paytm"
      - PayTM: "paytmqr", "@ptys", "paytm"
      - PhonePe: "phonepe", "@ybl"
      - Google Pay: "gpay", "@okicici", "gpay@"
      - NEFT/IMPS: "NEFT", "IMPS", "RTGS"
      - ATM: "ATM", "CASH WDL"
      - Salary: "SALARY", "SAL CR", "NEFT-SALARY"
      - EMI: "EMI", "LOAN"

      OUTPUT FORMAT:
      - For existing category: just the category name (e.g., "Swiggy/Zomato")
      - For new category: prefix with "NEW:" (e.g., "NEW:UPI Transfers")
      - For unknown: "null"
    INSTRUCTIONS
  end

  def format_transactions
    transactions.map do |t|
      "- ID: #{t[:id]}, Amount: #{t[:amount]}, Type: #{t[:classification]}, Description: \"#{t[:description]}\""
    end.join("\n")
  end

  def json_schema
    # NOTE: No enum constraints - AI can return existing category OR suggest new ones
    # New categories are prefixed with "NEW:" (e.g., "NEW:Paytm Payments")
    {
      type: "object",
      properties: {
        categorizations: {
          type: "array",
          description: "An array of categorizations for each transaction",
          items: {
            type: "object",
            properties: {
              transaction_id: {
                type: "string",
                description: "The UUID of the transaction"
              },
              category_name: {
                type: "string",
                description: "Existing category name, OR 'NEW:CategoryName' for suggestions, OR 'null' if unknown"
              }
            },
            required: ["transaction_id", "category_name"]
          }
        }
      },
      required: ["categorizations"]
    }
  end

  def extract_json_from_response(body)
    # Gemini returns JSON in candidates[0].content.parts[0].text
    raw = body.dig("candidates", 0, "content", "parts", 0, "text")

    raise Provider::Gemini::Error, "No content found in response" if raw.nil?

    # Strip markdown code blocks if present
    cleaned = raw.gsub(/^```json\s*/, "").gsub(/^```\s*/, "").gsub(/```\s*$/, "").strip

    cleaned
  end

  def build_response(categorizations)
    categorizations.map do |categorization|
      Provider::LlmConcept::AutoCategorization.new(
        transaction_id: categorization.dig("transaction_id"),
        category_name: normalize_category_name(categorization.dig("category_name"))
      )
    end
  end

  def normalize_category_name(category_name)
    # Convert to string to handle non-string LLM outputs
    normalized = category_name.to_s.strip
    return nil if normalized.empty? || normalized == "null" || normalized.downcase == "null"

    # Try exact match first
    exact_match = user_categories.find { |c| c[:name] == normalized }
    return exact_match[:name] if exact_match

    # Try case-insensitive match
    case_insensitive_match = user_categories.find { |c| c[:name].to_s.downcase == normalized.downcase }
    return case_insensitive_match[:name] if case_insensitive_match

    # Try partial/fuzzy match
    fuzzy_match = find_fuzzy_category_match(normalized)
    return fuzzy_match if fuzzy_match

    # Return normalized string if no match found
    normalized
  end

  def find_fuzzy_category_match(category_name)
    input_str = category_name.to_s
    normalized_input = input_str.downcase.gsub(/[^a-z0-9]/, "")

    user_categories.each do |cat|
      cat_name_str = cat[:name].to_s
      normalized_cat = cat_name_str.downcase.gsub(/[^a-z0-9]/, "")

      return cat[:name] if normalized_input.include?(normalized_cat) || normalized_cat.include?(normalized_input)

      return cat[:name] if fuzzy_name_match?(input_str, cat_name_str)
    end

    nil
  end

  def fuzzy_name_match?(input, category)
    variations = {
      "gas" => ["gas & fuel", "gas and fuel", "fuel", "gasoline"],
      "restaurants" => ["restaurant", "dining", "food"],
      "groceries" => ["grocery", "supermarket", "food store"],
      "streaming" => ["streaming services", "streaming service"],
      "rideshare" => ["ride share", "ride-share", "uber", "lyft"],
      "coffee" => ["coffee shops", "coffee shop", "cafe"],
      "fast food" => ["fastfood", "quick service"],
      "gym" => ["gym & fitness", "fitness", "gym and fitness"]
    }

    input_lower = input.to_s.downcase
    category_lower = category.to_s.downcase

    variations.each do |_key, synonyms|
      if synonyms.include?(input_lower) && synonyms.include?(category_lower)
        return true
      end
    end

    false
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
      operation: "auto_categorize",
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens,
      estimated_cost: estimated_cost,
      metadata: {
        transaction_count: transactions.size,
        category_count: user_categories.size
      }
    )

    Rails.logger.info("Gemini auto-categorize usage - Cost: #{estimated_cost.inspect}")
  rescue => e
    Rails.logger.error("Failed to record Gemini usage: #{e.message}")
  end
end
