# frozen_string_literal: true

# Provider::Engine - Proxy provider that calls rupi-engine API
#
# This replaces Provider::Gemini in rupi-v3. All LLM logic lives in rupi-engine.
# This is just a thin HTTP client that:
# 1. Sends messages + tool definitions to engine
# 2. Receives text responses or tool_call requests
# 3. Supports streaming via SSE
#
# The tool execution still happens locally in v3 (we have DB access)
#
class Provider::Engine < Provider
  include LlmConcept
  
  Error = Class.new(Provider::Error)
  
  # Model prefixes we support (engine decides actual model)
  SUPPORTED_MODEL_PREFIXES = %w[gemini-2.5 gemini-2.0 gemini-1.5 gemini-3 gemini-exp]
  DEFAULT_MODEL = "gemini-3-flash-preview"
  
  class << self
    def effective_model
      ENV.fetch("GOOGLE_AI_MODEL", Setting.google_ai_model.presence || DEFAULT_MODEL)
    end
  end
  
  def initialize(api_key = nil, model: nil)
    # API key not needed - we use RUPI_ENGINE_API_KEY
    @default_model = model.presence || DEFAULT_MODEL
  end
  
  def supports_model?(model)
    SUPPORTED_MODEL_PREFIXES.any? { |prefix| model.to_s.start_with?(prefix) }
  end
  
  def provider_name
    "RUPI Engine (Gemini)"
  end
  
  def supported_models_description
    "Gemini models via RUPI Engine"
  end
  
  # =================================================================
  # MAIN CHAT RESPONSE - Called by Assistant::Responder
  # =================================================================
  
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
          chat_history: chat_history
        )
      else
        non_stream_chat_response(
          prompt: prompt,
          model: model,
          instructions: instructions,
          functions: functions,
          function_results: function_results,
          chat_history: chat_history
        )
      end
    end
  end
  
  private
  
  # Reference LlmConcept classes
  ChatResponse = Provider::LlmConcept::ChatResponse
  ChatMessage = Provider::LlmConcept::ChatMessage
  ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest
  ChatStreamChunk = Provider::LlmConcept::ChatStreamChunk
  
  # =================================================================
  # NON-STREAMING
  # =================================================================
  
  def non_stream_chat_response(
    prompt:,
    model:,
    instructions:,
    functions:,
    function_results:,
    chat_history:
  )
    response = engine_client.post(
      "/api/v1/ai/chat",
      body: build_request_body(
        message: prompt,
        instructions: instructions,
        functions: functions,
        function_results: function_results,
        chat_history: chat_history
      ).to_json,
      headers: request_headers
    )
    
    handle_response(response)
  end
  
  # =================================================================
  # STREAMING
  # =================================================================
  
  def stream_chat_response(
    prompt:,
    model:,
    instructions:,
    functions:,
    function_results:,
    streamer:,
    chat_history:
  )
    # Check feature flag for streaming vs non-streaming
    if RupiEngineConfig.stream_chat?
      begin
        stream_chat_via_sse(
          prompt: prompt,
          model: model,
          instructions: instructions,
          functions: functions,
          function_results: function_results,
          streamer: streamer,
          chat_history: chat_history
        )
      rescue => e
        Rails.logger.warn("[Provider::Engine] SSE streaming failed, falling back to non-stream: #{e.message}")
        non_stream_chat_response(
          prompt: prompt,
          model: model,
          instructions: instructions,
          functions: functions,
          function_results: function_results,
          streamer: streamer,
          chat_history: chat_history
        )
      end
    else
      non_stream_chat_response(
        prompt: prompt,
        model: model,
        instructions: instructions,
        functions: functions,
        function_results: function_results,
        streamer: streamer,
        chat_history: chat_history
      )
    end
  end
  
  # Non-streaming fallback - calls /api/v1/ai/chat and emits single response
  def non_stream_chat_response(
    prompt:,
    model:,
    instructions:,
    functions:,
    function_results:,
    streamer:,
    chat_history:
  )
    url = "#{engine_base_url}/api/v1/ai/chat"
    
    body = build_request_body(
      message: prompt,
      instructions: instructions,
      functions: functions,
      function_results: function_results,
      chat_history: chat_history
    )
    
    response = HTTParty.post(
      url,
      body: body.to_json,
      headers: request_headers.merge("Content-Type" => "application/json"),
      timeout: 120
    )
    
    unless response.success?
      error_body = response.parsed_response rescue {}
      raise Error, error_body["message"] || "Non-streaming chat failed"
    end
    
    data = response.parsed_response
    
    # Emit the response to the streamer
    case data["type"]
    when "tool_call"
      tool_calls = data["tool_calls"] || []
      function_requests = tool_calls.map do |tc|
        ChatFunctionRequest.new(
          id: tc["id"],
          call_id: tc["id"],
          function_name: tc["name"],
          function_args: tc["arguments"].to_json
        )
      end
      
      chunk = ChatStreamChunk.new(
        type: "response",
        data: ChatResponse.new(
          id: data["request_id"] || "engine-#{Time.now.to_i}",
          model: "gemini",
          messages: [],
          function_requests: function_requests
        ),
        usage: data["usage"]
      )
      streamer.call(chunk)
      
      build_chat_response("", function_requests, data["usage"])
      
    when "message"
      text = data["content"] || ""
      
      # Emit as output_text for UI streaming
      if text.present?
        text_chunk = ChatStreamChunk.new(
          type: "output_text",
          data: text,
          usage: nil
        )
        streamer.call(text_chunk)
      end
      
      # Build final response
      message = text.present? ? ChatMessage.new(
        id: "engine-#{Time.now.to_i}",
        output_text: text
      ) : nil
      
      final_chunk = ChatStreamChunk.new(
        type: "response",
        data: ChatResponse.new(
          id: data["request_id"] || "engine-#{Time.now.to_i}",
          model: "gemini",
          messages: message ? [message] : [],
          function_requests: []
        ),
        usage: data["usage"]
      )
      streamer.call(final_chunk)
      
      build_chat_response(text, [], data["usage"])
      
    else
      raise Error, "Unknown response type: #{data['type']}"
    end
  end
  
  # SSE streaming implementation
  def stream_chat_via_sse(
    prompt:,
    model:,
    instructions:,
    functions:,
    function_results:,
    streamer:,
    chat_history:
  )
    url = "#{engine_base_url}/api/v1/ai/chat/stream"
    
    body = build_request_body(
      message: prompt,
      instructions: instructions,
      functions: functions,
      function_results: function_results,
      chat_history: chat_history
    )
    
    # DEBUG: Log what we're sending
    if function_results.any?
      Rails.logger.info("[Provider::Engine] Sending function_results: #{function_results.inspect[0..500]}")
      Rails.logger.info("[Provider::Engine] Request body tool_results: #{body[:tool_results].inspect[0..500]}")
    end
    
    collected_text = String.new("")
    function_requests = []
    final_usage = nil
    done_handled = false  # Track if we've already processed the 'done' event
    
    # Stream using Net::HTTP directly for SSE support
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 120
    
    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Accept"] = "text/event-stream"
    request["X-Api-Key"] = engine_api_key
    request["X-Request-ID"] = SecureRandom.uuid
    request.body = body.to_json
    
    http.request(request) do |response|
      unless response.is_a?(Net::HTTPSuccess)
        error_body = response.body rescue "Unknown error"
        raise Error, "Engine streaming failed: #{error_body}"
      end
      
      buffer = String.new("")
      
      response.read_body do |chunk|
        buffer += chunk
        
        Rails.logger.debug("[Provider::Engine] SSE chunk received, buffer size: #{buffer.size}")
        
        # Process complete SSE events
        while buffer.include?("\n\n")
          event_end = buffer.index("\n\n")
          event_data = buffer[0...event_end]
          buffer = buffer[(event_end + 2)..]
          
          Rails.logger.debug("[Provider::Engine] Processing SSE event: #{event_data[0..100]}")
          done_handled = process_sse_event(event_data, streamer, collected_text, function_requests, final_usage, done_handled)
        end
      end
    end
    
    Rails.logger.info("[Provider::Engine] SSE complete. Collected text length: #{collected_text.length}")
    
    # Build final response
    build_chat_response(collected_text, function_requests, final_usage)
  end
  
  def process_sse_event(event_data, streamer, collected_text, function_requests, final_usage, done_handled = false)
    event_type = nil
    data_json = nil
    
    event_data.each_line do |line|
      line = line.strip
      if line.start_with?("event:")
        event_type = line.sub("event:", "").strip
      elsif line.start_with?("data:")
        data_json = line.sub("data:", "").strip
      end
    end
    
    return done_handled unless event_type && data_json
    
    begin
      data = JSON.parse(data_json)
      
      case event_type
      when "delta"
        text = data["content"]
        if text.present?
          collected_text << text
          
          # Emit to streamer
          chunk = ChatStreamChunk.new(
            type: "output_text",
            data: text,
            usage: nil
          )
          streamer.call(chunk)
        end
        
      when "tool_call"
        tool_calls = data["tool_calls"] || []
        tool_calls.each do |tc|
          function_requests << ChatFunctionRequest.new(
            id: tc["id"],
            call_id: tc["id"],
            function_name: tc["name"],
            function_args: tc["arguments"].to_json,
            thought_signature: tc["thought_signature"]
          )
        end
        
        # Emit tool call response
        chunk = ChatStreamChunk.new(
          type: "response",
          data: ChatResponse.new(
            id: "engine-#{Time.now.to_i}",
            model: "gemini",
            messages: [],
            function_requests: function_requests
          ),
          usage: nil
        )
        streamer.call(chunk)
        
      when "done"
        # CRITICAL: Only process the FIRST 'done' event - ignore duplicates
        # This prevents text duplication from multiple done events
        if done_handled
          Rails.logger.debug("[Provider::Engine] Ignoring duplicate 'done' event")
          return done_handled
        end
        
        final_usage = data["usage"]
        
        # Emit final response
        message = collected_text.present? ? ChatMessage.new(
          id: "engine-#{Time.now.to_i}",
          output_text: collected_text
        ) : nil
        
        chunk = ChatStreamChunk.new(
          type: "response",
          data: ChatResponse.new(
            id: "engine-#{Time.now.to_i}",
            model: "gemini",
            messages: message ? [message] : [],
            function_requests: function_requests
          ),
          usage: final_usage
        )
        streamer.call(chunk)
        
        return true  # Mark done as handled
        
      when "error"
        Rails.logger.error("[Provider::Engine] Stream error: #{data}")
        raise Error, data["message"] || "Engine stream error"
      end
      
    rescue JSON::ParserError => e
      Rails.logger.warn("[Provider::Engine] Failed to parse SSE data: #{e.message}")
    end
    
    done_handled  # Return current state
  end
  
  # =================================================================
  # HELPERS
  # =================================================================
  
  def build_request_body(message:, instructions:, functions:, function_results:, chat_history:)
    body = {
      message: message,
      chat_history: normalize_chat_history(chat_history)
    }
    
    body[:instructions] = instructions if instructions.present?
    
    # Only include tools if NOT sending tool_results (prevents nested tool calls)
    if function_results.any?
      body[:tool_results] = normalize_function_results(function_results)
      # Don't include available_tools - we want the AI to respond with text, not make more tool calls
    else
      body[:available_tools] = build_tool_definitions(functions) if functions.any?
    end
    
    body
  end
  
  def normalize_chat_history(chat_history)
    chat_history.map do |msg|
      {
        role: msg[:role].to_s,
        content: msg[:content].to_s
      }
    end
  end
  
  def build_tool_definitions(functions)
    functions.map do |fn|
      {
        name: fn[:name],
        description: fn[:description],
        params_schema: fn[:params_schema]
      }
    end
  end
  
  def normalize_function_results(function_results)
    function_results.map do |result|
      normalized = {
        call_id: result[:call_id],
        name: result[:name],
        arguments: result[:arguments],
        output: result[:output]
      }
      # Include thought_signature for Gemini 3 reasoning context
      normalized[:thought_signature] = result[:thought_signature] if result[:thought_signature].present?
      normalized
    end
  end
  
  def build_chat_response(text, function_requests, usage)
    message = text.present? ? ChatMessage.new(
      id: "engine-#{Time.now.to_i}",
      output_text: text
    ) : nil
    
    ChatResponse.new(
      id: "engine-#{Time.now.to_i}",
      model: "gemini",
      messages: message ? [message] : [],
      function_requests: function_requests
    )
  end
  
  def handle_response(response)
    unless response.success?
      error_data = response.parsed_response || {}
      raise Error, error_data["message"] || "Engine request failed"
    end
    
    data = response.parsed_response
    
    case data["type"]
    when "tool_call"
      function_requests = (data["tool_calls"] || []).map do |tc|
        ChatFunctionRequest.new(
          id: tc["id"],
          call_id: tc["id"],
          function_name: tc["name"],
          function_args: tc["arguments"].to_json
        )
      end
      
      ChatResponse.new(
        id: data["request_id"] || "engine-#{Time.now.to_i}",
        model: "gemini",
        messages: [],
        function_requests: function_requests
      )
      
    when "message"
      message = ChatMessage.new(
        id: "engine-#{Time.now.to_i}",
        output_text: data["content"]
      )
      
      ChatResponse.new(
        id: data["request_id"] || "engine-#{Time.now.to_i}",
        model: "gemini",
        messages: [message],
        function_requests: []
      )
      
    else
      raise Error, "Unknown response type: #{data['type']}"
    end
  end
  
  def engine_client
    @engine_client ||= HTTParty
  end
  
  def engine_base_url
    ENV.fetch("RUPI_ENGINE_URL", "http://localhost:4000")
  end
  
  def engine_api_key
    ENV.fetch("RUPI_ENGINE_API_KEY", "")
  end
  
  def request_headers
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "X-Api-Key" => engine_api_key,
      "X-Request-ID" => SecureRandom.uuid
    }
  end
end
