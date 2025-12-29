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
      You are an assistant to a consumer personal finance app. You will be provided a list
      of the user's transactions and a list of the user's categories. Your job is to auto-categorize
      each transaction.

      Closely follow ALL the rules below while auto-categorizing:

      - Return 1 result per transaction
      - Correlate each transaction by ID (transaction_id)
      - Attempt to match the most specific category possible (i.e. subcategory over parent category)
      - Category and transaction classifications should match (i.e. if transaction is an "expense", the category must have classification of "expense")
      - If you don't know the category, return "null"
        - You should always favor "null" over false positives
        - Be slightly pessimistic. Only match a category if you're 60%+ confident it is the correct one.
      - Each transaction has varying metadata that can be used to determine the category
        - Note: "hint" comes from 3rd party aggregators and typically represents a category name that
          may or may not match any of the user-supplied categories

      IMPORTANT:
      - Use EXACT category names from the provided list
      - Return "null" (as a string) if you cannot confidently match a category
      - Match expense transactions only to expense categories
      - Match income transactions only to income categories
    INSTRUCTIONS
  end

  def format_transactions
    transactions.map do |t|
      "- ID: #{t[:id]}, Amount: #{t[:amount]}, Type: #{t[:classification]}, Description: \"#{t[:description]}\""
    end.join("\n")
  end

  def json_schema
    # NOTE: Removed enum constraints for transaction_id and category_name
    # because Gemini 3 Flash Preview returns 400 when enums are too large (177+ items)
    # The prompt already instructs the model on valid category names
    {
      type: "object",
      properties: {
        categorizations: {
          type: "array",
          description: "An array of auto-categorizations for each transaction",
          items: {
            type: "object",
            properties: {
              transaction_id: {
                type: "string",
                description: "The internal UUID of the original transaction"
              },
              category_name: {
                type: "string",
                description: "The matched category name of the transaction, or 'null' if no match"
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
