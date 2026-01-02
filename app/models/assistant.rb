class Assistant
  include Provided, Configurable, Broadcastable

  attr_reader :chat, :instructions

  class << self
    def for_chat(chat)
      config = config_for(chat)
      new(chat, instructions: config[:instructions], functions: config[:functions])
    end
  end

  def initialize(chat, instructions: nil, functions: [])
    @chat = chat
    @instructions = instructions
    @functions = functions
  end

  def respond_to(message)
    assistant_message = AssistantMessage.new(
      chat: chat,
      content: "",
      ai_model: message.ai_model
    )

    llm_provider = get_model_provider(message.ai_model)

    unless llm_provider
      error_message = build_no_provider_error_message(message.ai_model)
      raise StandardError, error_message
    end

    responder = Assistant::Responder.new(
      message: message,
      instructions: instructions,
      function_tool_caller: function_tool_caller,
      llm: llm_provider
    )

    latest_response_id = chat.latest_assistant_response_id
    text_was_streamed = false  # Track if text was streamed via output_text

    responder.on(:output_text) do |text|
      text_was_streamed = true
      
      if assistant_message.content.blank?
        stop_thinking

        Chat.transaction do
          assistant_message.append_text!(text)
          chat.update_latest_response!(latest_response_id)
        end
      else
        assistant_message.append_text!(text)
      end
    end

    responder.on(:response) do |data|
      update_thinking("Analyzing your data...")

      # Save the assistant message if it hasn't been saved yet
      if assistant_message.new_record?
        # Extract text from messages if available, but only if we don't already have content
        if data[:messages].present? && assistant_message.content.blank?
          text = data[:messages].map { |msg| msg.output_text }.compact.join(" ")
          assistant_message.content = text if text.present?
        end
        # Always save if new_record, even if content is blank (function calls only)
        assistant_message.save!
        chat.update_latest_response!(data[:id]) if data[:id].present?
      elsif data[:messages].present? && !text_was_streamed
        # Only append from messages if we didn't already stream the text
        # This handles non-streaming fallback or follow-up responses
        text = data[:messages].map { |msg| msg.output_text }.compact.join(" ")
        if text.present? && !assistant_message.content.to_s.include?(text[0..50])
          assistant_message.append_text!(text)
        end
        chat.update_latest_response!(data[:id]) if data[:id].present?
      else
        # Text was already streamed, just update response ID
        chat.update_latest_response!(data[:id]) if data[:id].present?
      end

      if data[:function_tool_calls].present?
        assistant_message.tool_calls = data[:function_tool_calls]
        latest_response_id = data[:id]
        text_was_streamed = false  # Reset for follow-up response
      elsif data[:id].present?
        chat.update_latest_response!(data[:id])
      end
    end

    responder.respond(previous_response_id: latest_response_id)
  rescue => e
    stop_thinking
    chat.add_error(e)
  end

  private
    attr_reader :functions

    def function_tool_caller
      function_instances = functions.map do |fn|
        fn.new(chat.user)
      end

      @function_tool_caller ||= FunctionToolCaller.new(function_instances)
    end

    def build_no_provider_error_message(requested_model)
      available_providers = registry.providers

      if available_providers.empty?
        "No LLM provider configured that supports model '#{requested_model}'. " \
        "Please configure an LLM provider (e.g., Google Gemini) in settings."
      else
        provider_details = available_providers.map do |provider|
          "  - #{provider.provider_name}: #{provider.supported_models_description}"
        end.join("\n")

        "No LLM provider configured that supports model '#{requested_model}'.\n\n" \
        "Available providers:\n#{provider_details}\n\n" \
        "Please either:\n" \
        "  1. Use a supported model from the list above, or\n" \
        "  2. Configure a provider that supports '#{requested_model}' in settings."
      end
    end
end
