class Assistant::Responder
  def initialize(message:, instructions:, function_tool_caller:, llm:)
    @message = message
    @instructions = instructions
    @function_tool_caller = function_tool_caller
    @llm = llm
  end

  def on(event_name, &block)
    listeners[event_name.to_sym] << block
  end

  def respond(previous_response_id: nil)
    # Track whether response was handled by streamer
    response_handled = false

    # For the first response - accumulate text in case we have function calls
    initial_text_chunks = []
    
    streamer = proc do |chunk|
      case chunk.type
      when "output_text"
        # Accumulate text - we'll emit it only if there are no function requests
        initial_text_chunks << chunk.data
      when "response"
        response = chunk.data
        response_handled = true

        if response.function_requests.any?
          # Don't emit the initial text - only use the follow-up response text
          # This prevents duplication when AI sends text + function call together
          handle_follow_up_response(response)
        else
          # No function requests - emit all the accumulated text
          initial_text_chunks.each { |text| emit(:output_text, text) }
          emit(:response, { id: response.id, messages: response.messages })
        end
      end
    end

    response = get_llm_response(streamer: streamer, previous_response_id: previous_response_id)

    # For synchronous (non-streaming) responses, handle function requests if not already handled by streamer
    unless response_handled
      if response && response.function_requests.any?
        handle_follow_up_response(response)
      elsif response
        emit(:response, { id: response.id })
      end
    end
  end

  private
    attr_reader :message, :instructions, :function_tool_caller, :llm

    def handle_follow_up_response(response)
      Rails.logger.info("[Responder] handle_follow_up_response called with #{response.function_requests.size} function_requests")
      response.function_requests.each do |fr|
        Rails.logger.info("[Responder] Function request: #{fr.function_name}")
      end
      
      streamer = proc do |chunk|
        case chunk.type
        when "output_text"
          emit(:output_text, chunk.data)
        when "response"
          Rails.logger.info("[Responder] Follow-up streamer received response chunk")
          # Don't include messages - text was already streamed via output_text events
          # Just pass the id for tracking (no messages to avoid duplication)
          emit(:response, { id: chunk.data.id })
        end
      end

      function_tool_calls = function_tool_caller.fulfill_requests(response.function_requests)
      Rails.logger.info("[Responder] Executed #{function_tool_calls.size} tool calls")

      emit(:response, {
        id: response.id,
        function_tool_calls: function_tool_calls
      })

      # Get follow-up response with tool call results
      Rails.logger.info("[Responder] Calling get_llm_response with #{function_tool_calls.size} function_results")
      get_llm_response(
        streamer: streamer,
        function_results: function_tool_calls.map(&:to_result),
        previous_response_id: response.id
      )
    end

    def get_llm_response(streamer:, function_results: [], previous_response_id: nil)
      response = llm.chat_response(
        message.content,
        model: message.ai_model,
        instructions: instructions,
        functions: function_tool_caller.function_definitions,
        function_results: function_results,
        streamer: streamer,
        previous_response_id: previous_response_id,
        session_id: chat_session_id,
        user_identifier: chat_user_identifier,
        family: message.chat&.user&.family,
        chat_history: build_chat_history
      )

      unless response.success?
        raise response.error
      end

      response.data
    end

    def build_chat_history
      return [] unless chat

      # Get previous messages from this chat (excluding the current message)
      previous_messages = chat.messages
        .where.not(id: message.id)
        .order(created_at: :asc)
        .limit(20) # Limit to last 20 messages for token efficiency

      previous_messages.map do |msg|
        {
          role: msg.is_a?(UserMessage) ? "user" : "assistant",
          content: msg.content.presence || ""
        }
      end.reject { |m| m[:content].blank? }
    end

    def emit(event_name, payload = nil)
      listeners[event_name.to_sym].each { |block| block.call(payload) }
    end

    def listeners
      @listeners ||= Hash.new { |h, k| h[k] = [] }
    end

    def chat_session_id
      chat&.id&.to_s
    end

    def chat_user_identifier
      return unless chat&.user_id

      ::Digest::SHA256.hexdigest(chat.user_id.to_s)
    end

    def chat
      @chat ||= message.chat
    end
end
