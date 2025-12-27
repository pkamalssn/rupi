class Provider::Gemini::ChatStreamParser
  Error = Class.new(StandardError)

  # Reference LlmConcept classes at class level
  Chunk = Provider::LlmConcept::ChatStreamChunk
  ChatResponse = Provider::LlmConcept::ChatResponse
  ChatMessage = Provider::LlmConcept::ChatMessage
  ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

  def initialize(object)
    @object = object
  end

  def parsed
    # First, extract any text content
    candidate = object.dig("candidates", 0)
    text_content = ""
    function_requests = []

    if candidate
      content_parts = candidate.dig("content", "parts")
      if content_parts
        # Check for function calls
        function_call_parts = content_parts.select { |part| part["functionCall"].present? }
        if function_call_parts.any?
          function_call_parts.each_with_index do |part, index|
            function_call = part["functionCall"]
            function_requests << ChatFunctionRequest.new(
              id: "gemini-#{Time.now.to_i}-fn-#{index}",
              call_id: "gemini-#{Time.now.to_i}-call-#{index}",
              function_name: function_call["name"],
              function_args: function_call["args"].to_json
            )
          end
        end

        # Extract text from parts
        text_parts = content_parts.select { |part| part["text"].present? }
        text_content = text_parts.map { |part| part["text"] }.join("")
      end
    end

    # If this is a usage metadata chunk (end of stream), return response chunk
    if object["usageMetadata"]
      usage = map_gemini_usage(object["usageMetadata"])

      # Build message with accumulated text
      message = if text_content.present?
        ChatMessage.new(
          id: "gemini-#{Time.now.to_i}",
          output_text: text_content
        )
      end

      return Chunk.new(
        type: "response",
        data: ChatResponse.new(
          id: "gemini-#{Time.now.to_i}",
          model: "gemini-2.5-flash",
          messages: message ? [message] : [],
          function_requests: function_requests
        ),
        usage: usage
      )
    end

    # If there's text content but no usage yet, return as output_text chunk
    if text_content.present?
      return Chunk.new(
        type: "output_text",
        data: text_content,
        usage: nil
      )
    end

    nil
  end

  private
    attr_reader :object

    def map_gemini_usage(usage_metadata)
      return nil unless usage_metadata

      {
        "prompt_tokens" => usage_metadata["promptTokenCount"] || 0,
        "completion_tokens" => usage_metadata["candidatesTokenCount"] || 0,
        "total_tokens" => usage_metadata["totalTokenCount"] || 0
      }
    end
end
