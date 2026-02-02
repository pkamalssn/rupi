class MessagesController < ApplicationController
  guard_feature unless: -> { Current.user.ai_enabled? }

  before_action :set_chat
  before_action :check_rate_limit, only: :create

  def create
    @message = UserMessage.create!(
      chat: @chat,
      content: message_params[:content],
      ai_model: message_params[:ai_model].presence || Chat.default_model
    )

    # Record this message for rate limiting
    Current.user.record_ai_message!

    redirect_to chat_path(@chat, thinking: true)
  end

  private
    def set_chat
      @chat = Current.user.chats.find(params[:chat_id])
    end

    def message_params
      params.require(:message).permit(:content, :ai_model)
    end

    def check_rate_limit
      # Check cooldown (spam prevention)
      if Current.user.ai_cooldown_active?
        remaining = Current.user.ai_cooldown_remaining
        flash[:alert] = "Please wait #{remaining} seconds before sending another message."
        redirect_to chat_path(@chat) and return
      end

      # Check daily limit
      unless Current.user.can_send_ai_message?
        status = Current.user.ai_rate_limit_status
        reset_time = status[:resets_at].strftime("%I:%M %p IST")
        flash[:alert] = "Daily message limit reached (#{status[:limit]}/day). Resets at #{reset_time}."
        redirect_to chat_path(@chat) and return
      end
    end
end

