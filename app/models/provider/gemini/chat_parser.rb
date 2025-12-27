class Provider::Gemini::ChatParser
  Error = Class.new(StandardError)

  def initialize(object)
    @object = object
  end

  def parsed
    ChatResponse.new(
      id: response_id,
      model: response_model,
      messages: messages,
      function_requests: function_requests
    )
  end

  private
    attr_reader :object

    ChatResponse = Provider::LlmConcept::ChatResponse
    ChatMessage = Provider::LlmConcept::ChatMessage
    ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

    def response_id
      # Gemini doesn't return a response ID, generate one
      "gemini-#{Time.now.to_i}"
    end

    def response_model
      # Model is not in response, use a default
      "gemini"
    end

    def messages
      content_parts = object.dig("candidates", 0, "content", "parts") || []
      text_parts = content_parts.select { |part| part["text"].present? }

      return [] if text_parts.empty?

      [
        ChatMessage.new(
          id: response_id,
          output_text: text_parts.map { |part| part["text"] }.join("\n")
        )
      ]
    end

    def function_requests
      content_parts = object.dig("candidates", 0, "content", "parts") || []
      function_call_parts = content_parts.select { |part| part["functionCall"].present? }

      function_call_parts.map.with_index do |part, index|
        function_call = part["functionCall"]
        ChatFunctionRequest.new(
          id: "#{response_id}-fn-#{index}",
          call_id: "#{response_id}-call-#{index}",
          function_name: function_call["name"],
          function_args: function_call["args"].to_json
        )
      end
    end
end
