class Provider::Gemini < Provider
  include LlmConcept

  # Subclass so errors caught in this provider are raised as Provider::Gemini::Error
  Error = Class.new(Provider::Error)

  # Supported Gemini model prefixes
  DEFAULT_GEMINI_MODEL_PREFIXES = %w[gemini-2.5 gemini-2.0 gemini-1.5 gemini-3 gemini-exp]
  DEFAULT_MODEL = "gemini-3-flash-preview"  # December 2025: Latest and fastest!

  class << self
    def effective_model
      configured_model = ENV.fetch("GOOGLE_AI_MODEL", Setting.google_ai_model)
      configured_model.presence || DEFAULT_MODEL
    end
  end

  def initialize(api_key, model: nil)
    raise Error, "API key is required" if api_key.blank?

    @api_key = api_key
    @default_model = model.presence || DEFAULT_MODEL
    @connection = build_connection
  end

  def supports_model?(model)
    DEFAULT_GEMINI_MODEL_PREFIXES.any? { |prefix| model.start_with?(prefix) }
  end

  def provider_name
    "Google Gemini"
  end

  def supported_models_description
    "models starting with: #{DEFAULT_GEMINI_MODEL_PREFIXES.join(', ')}"
  end

  def auto_categorize(transactions: [], user_categories: [], model: "", family: nil, json_mode: nil)
    with_provider_response do
      raise Error, "Too many transactions to auto-categorize. Max is 100 per request." if transactions.size > 100
      if user_categories.blank?
        family_id = family&.id || "unknown"
        Rails.logger.error("Cannot auto-categorize transactions for family #{family_id}: no categories available")
        raise Error, "No categories available for auto-categorization"
      end

      effective_model = model.presence || @default_model

      result = AutoCategorizer.new(
        @connection,
        api_key: @api_key,
        model: effective_model,
        transactions: transactions,
        user_categories: user_categories,
        family: family
      ).auto_categorize

      result
    end
  end

  def auto_detect_merchants(transactions: [], user_merchants: [], model: "", family: nil, json_mode: nil)
    with_provider_response do
      raise Error, "Too many transactions to auto-detect merchants. Max is 100 per request." if transactions.size > 100

      effective_model = model.presence || @default_model

      result = AutoMerchantDetector.new(
        @connection,
        api_key: @api_key,
        model: effective_model,
        transactions: transactions,
        user_merchants: user_merchants,
        family: family
      ).auto_detect_merchants

      result
    end
  end

  def parse_loan_document(file:, model: nil, family: nil)
    with_provider_response do
      effective_model = model.presence || @default_model
      
      result = DocumentParser.new(
        @connection,
        api_key: @api_key,
        model: effective_model
      ).parse_loan_document(file)

      # Track LLM usage
      # TODO: Refactor DocumentParser to return usage metadata so we can track cost
      # if family.present?
      #   LlmUsage.record(...) # This method doesn't exist
      # end

      result
    end
  end

  def chat_response(
    prompt,
    model:,
    instructions: nil,
    functions: [],
    function_results: [],
    streamer: nil,
    previous_response_id: nil,
    session_id: nil,
    user_identifier: nil,
    family: nil,
    chat_history: []
  )
    with_provider_response do
      if streamer.present?
        stream_chat_response(
          prompt: prompt,
          model: model,
          instructions: instructions,
          functions: functions,
          function_results: function_results,
          streamer: streamer,
          session_id: session_id,
          user_identifier: user_identifier,
          family: family,
          chat_history: chat_history
        )
      else
        non_stream_chat_response(
          prompt: prompt,
          model: model,
          instructions: instructions,
          functions: functions,
          function_results: function_results,
          session_id: session_id,
          user_identifier: user_identifier,
          family: family,
          chat_history: chat_history
        )
      end
    end
  end

  private

  # Reference LlmConcept classes for use in private methods
  ChatResponse = Provider::LlmConcept::ChatResponse
  ChatMessage = Provider::LlmConcept::ChatMessage

  def build_connection
    Faraday.new(url: "https://generativelanguage.googleapis.com") do |conn|
      conn.request :json
      conn.response :json
      conn.response :raise_error
      # Extended timeout for document parsing (large PDFs can take time)
      conn.options.timeout = 180        # 3 minutes total
      conn.options.open_timeout = 30    # 30 seconds to connect
      conn.use Faraday::Retry::Middleware,
        max: 3,
        interval: 1,
        backoff_factor: 2,
        retry_statuses: [429, 500, 502, 503, 504]
      conn.adapter :net_http
    end
  end

  def generate_content_endpoint(model, streaming: false)
    method = streaming ? "streamGenerateContent" : "generateContent"
    "/v1beta/models/#{model}:#{method}"
  end

  def build_contents(prompt, instructions, function_results, chat_history: [], model: nil)
    contents = []

    # Gemini 3 requires thought signatures for function calls
    # Using the documented bypass string for migrations
    gemini3_thought_signature = "context_engineering_is_the_way_to_go"
    is_gemini3 = model&.start_with?("gemini-3")

    # Add chat history first to maintain conversation context
    chat_history.each do |msg|
      role = msg[:role] == "user" ? "user" : "model"
      contents << {
        role: role,
        parts: [{ text: msg[:content] }]
      }
    end

    # Add user prompt (current message)
    contents << {
      role: "user",
      parts: [{ text: prompt }]
    }

    # If there are function results, we need to reconstruct the conversation
    if function_results.any?
      # Add assistant message with tool calls
      tool_calls = function_results.each_with_index.map do |fn_result, index|
        call_id = fn_result[:call_id]
        function_args = fn_result[:arguments]
        function_args_str = function_args.is_a?(String) ? function_args : function_args.to_json

        part = {
          functionCall: {
            name: fn_result[:name],
            args: JSON.parse(function_args_str)
          }
        }
        
        # Gemini 3: Only first function call in parallel calls needs thought signature
        if is_gemini3 && index == 0
          part[:thoughtSignature] = fn_result[:thought_signature] || gemini3_thought_signature
        end
        
        part
      end

      contents << {
        role: "model",
        parts: tool_calls
      }

      # Add function results as user messages (grouped together for Gemini 3)
      function_response_parts = function_results.map do |fn_result|
        output = fn_result[:output]
        content = if output.nil?
          ""
        elsif output.is_a?(String)
          output
        else
          output.to_json
        end

        {
          functionResponse: {
            name: fn_result[:name],
            response: { content: content }
          }
        }
      end

      contents << {
        role: "user",
        parts: function_response_parts
      }
    end

    contents
  end

  def build_tools(functions)
    return [] if functions.blank?

    tools_array = [{
      functionDeclarations: functions.map do |fn|
        schema = fn[:params_schema] || {}
        cleaned_schema = clean_schema_for_gemini(schema)
        {
          name: fn[:name],
          description: fn[:description],
          parameters: cleaned_schema
        }
      end
    }]

    tools_array
  end

  # Gemini doesn't support all JSON Schema keywords.
  # Remove unsupported properties like additionalProperties, uniqueItems, etc.
  def clean_schema_for_gemini(schema)
    return schema unless schema.is_a?(Hash)

    # Gemini doesn't support these JSON Schema keywords
    unsupported_keys = %w[additionalProperties uniqueItems $schema title examples default]

    cleaned = schema.reject do |k, v|
      unsupported_keys.include?(k.to_s)
    end

    # Recursively clean nested properties (handle both string and symbol keys)
    props = cleaned[:properties] || cleaned["properties"]
    if props
      if cleaned.key?(:properties)
        cleaned[:properties] = props.transform_values { |prop_schema| clean_schema_for_gemini(prop_schema) }
      else
        cleaned["properties"] = props.transform_values { |prop_schema| clean_schema_for_gemini(prop_schema) }
      end
    end

    # Clean array item schemas (handle both string and symbol keys)
    items = cleaned[:items] || cleaned["items"]
    if items
      cleaned_items = clean_schema_for_gemini(items)
      # Gemini doesn't support enum in array items - always remove it
      if cleaned_items.key?(:enum)
        cleaned_items.delete(:enum)
      end
      if cleaned_items.key?("enum")
        cleaned_items.delete("enum")
      end
      if cleaned.key?(:items)
        cleaned[:items] = cleaned_items
      else
        cleaned["items"] = cleaned_items
      end
    end

    # Handle enum: if present, ensure type is "string"
    has_enum = cleaned.key?(:enum) || cleaned.key?("enum")
    has_type = cleaned.key?(:type) || cleaned.key?("type")
    if has_enum && !has_type
      if cleaned.key?(:enum)
        cleaned[:type] = "string"
      else
        cleaned["type"] = "string"
      end
    end

    cleaned
  end

  def non_stream_chat_response(
    prompt:,
    model:,
    instructions: nil,
    functions: [],
    function_results: [],
    session_id: nil,
    user_identifier: nil,
    family: nil,
    chat_history: []
  )
    contents = build_contents(prompt, instructions, function_results, chat_history: chat_history, model: model)
    tools = build_tools(functions)

    payload = {
      contents: contents,
      tools: tools
    }

    # Add system instruction separately
    if instructions.present?
      payload[:systemInstruction] = {
        parts: [{ text: instructions }]
      }
    end

    response = @connection.post("#{generate_content_endpoint(model)}?key=#{@api_key}") do |req|
      req.body = payload
    end

    parsed = ChatParser.new(response.body).parsed

    # Map Gemini usage to OpenAI format
    usage = map_gemini_usage(response.body.dig("usageMetadata"))

    record_usage(
      model,
      usage,
      operation: "chat",
      family: family,
      metadata: {}
    )

    parsed
  rescue => e
    record_usage_error(model, operation: "chat", error: e, family: family)
    raise
  end

  def stream_chat_response(
    prompt:,
    model:,
    instructions: nil,
    functions: [],
    function_results: [],
    streamer:,
    session_id: nil,
    user_identifier: nil,
    family: nil,
    chat_history: []
  )
    contents = build_contents(prompt, instructions, function_results, chat_history: chat_history, model: model)
    tools = build_tools(functions)

    payload = {
      contents: contents,
      tools: tools
    }

    # Gemini 3 compatibility: Don't set temperature for Gemini 3 models
    # Gemini 3 defaults to 1.0 and low values can cause issues
    unless model.start_with?("gemini-3")
      payload[:generationConfig] = {
        temperature: 0.7
      }
    end

    if instructions.present?
      payload[:systemInstruction] = {
        parts: [{ text: instructions }]
      }
    end

    collected_chunks = []
    final_usage = nil

    begin
      response = @connection.post("#{generate_content_endpoint(model, streaming: true)}?alt=sse&key=#{@api_key}") do |req|
        req.body = payload
      end
    rescue Faraday::ClientError => e
      # Log the actual error response for debugging
      if e.response
        error_body = e.response[:body]
        Rails.logger.error("Gemini API Error Response: #{error_body}")
      end
      raise
    end

    # Parse the SSE body directly
    body = response.body

    parse_sse_chunks(body) do |parsed_data|
      stream_chunk = ChatStreamParser.new(parsed_data).parsed

      unless stream_chunk.nil?
        streamer.call(stream_chunk)
        collected_chunks << stream_chunk
        final_usage = stream_chunk.usage if stream_chunk.usage
      end
    end

    # Find and return the response chunk
    response_chunk = collected_chunks.find { |chunk| chunk.type == "response" }
    response_data = response_chunk&.data

    if response_data && final_usage
      record_usage(
        model,
        final_usage,
        operation: "chat",
        family: family,
        metadata: {}
      )
    end

    response_data
  rescue => e
    record_usage_error(model, operation: "chat", error: e, family: family)
    raise
  end

  def parse_sse_chunks(raw_body)
    return if raw_body.blank?

    # SSE format: "data: {...}\n\n" or "data: {...}\ndata: {...}\n\n"
    # Split by newlines and process each data line
    raw_body.each_line do |line|
      line = line.strip
      next if line.empty?
      next unless line.start_with?("data:")

      json_str = line.sub(/^data:\s*/, "")
      next if json_str.empty? || json_str == "[DONE]"

      begin
        yield JSON.parse(json_str)
      rescue JSON::ParserError => e
        Rails.logger.warn("Failed to parse Gemini SSE chunk: #{e.message} - Content: #{json_str[0..100]}")
      end
    end
  end

  def map_gemini_usage(usage_metadata)
    return {} unless usage_metadata

    {
      "prompt_tokens" => usage_metadata["promptTokenCount"] || 0,
      "completion_tokens" => usage_metadata["candidatesTokenCount"] || 0,
      "total_tokens" => usage_metadata["totalTokenCount"] || 0
    }
  end

  def record_usage(model_name, usage_data, operation:, family:, metadata: {})
    return unless family && usage_data

    prompt_tokens = usage_data["prompt_tokens"] || 0
    completion_tokens = usage_data["completion_tokens"] || 0
    total_tokens = usage_data["total_tokens"] || 0

    estimated_cost = LlmUsage.calculate_cost(
      model: model_name,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens
    )

    inferred_provider = LlmUsage.infer_provider(model_name)
    family.llm_usages.create!(
      provider: inferred_provider,
      model: model_name,
      operation: operation,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens,
      estimated_cost: estimated_cost,
      metadata: metadata
    )

    Rails.logger.info("LLM usage recorded - Operation: #{operation}, Cost: #{estimated_cost.inspect}")
  rescue => e
    Rails.logger.error("Failed to record LLM usage: #{e.message}")
  end

  def record_usage_error(model_name, operation:, error:, family:)
    return unless family

    Rails.logger.info("Recording failed LLM usage - Operation: #{operation}, Error: #{error.message}")

    http_status_code = extract_http_status_code(error)

    inferred_provider = LlmUsage.infer_provider(model_name)
    family.llm_usages.create!(
      provider: inferred_provider,
      model: model_name,
      operation: operation,
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
      estimated_cost: nil,
      metadata: {
        error: error.message,
        http_status_code: http_status_code
      }
    )

    Rails.logger.info("Failed LLM usage recorded - Operation: #{operation}, Status: #{http_status_code}")
  rescue => e
    Rails.logger.error("Failed to record LLM usage error: #{e.message}")
  end

  def extract_http_status_code(error)
    if error.respond_to?(:code)
      error.code
    elsif error.respond_to?(:status_code)
      error.status_code
    elsif error.respond_to?(:response) && error.response.respond_to?(:status)
      error.response.status
    elsif error.message =~ /(\d{3})/
      $1.to_i
    else
      nil
    end
  end
end
