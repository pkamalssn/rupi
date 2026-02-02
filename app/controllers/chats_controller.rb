class ChatsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_chat, only: [ :show, :edit, :update, :destroy, :export_markdown, :export_pdf ]

  def index
    @chat = nil # override application_controller default behavior of setting @chat to last viewed chat
    @chats = Current.user.chats.order(created_at: :desc)
  end

  def show
    set_last_viewed_chat(@chat)
  end

  def new
    @chat = Current.user.chats.new(title: "New chat #{Time.current.strftime("%Y-%m-%d %H:%M")}")
  end

  def create
    @chat = Current.user.chats.start!(chat_params[:content], model: chat_params[:ai_model])
    set_last_viewed_chat(@chat)
    redirect_to chat_path(@chat, thinking: true)
  end

  def edit
  end

  def update
    @chat.update!(chat_params)

    respond_to do |format|
      format.html { redirect_back_or_to chat_path(@chat), notice: "Chat updated" }
      format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(@chat, :title), partial: "chats/chat_title", locals: { chat: @chat }) }
    end
  end

  def destroy
    @chat.destroy
    clear_last_viewed_chat

    redirect_to chats_path, notice: "Chat was successfully deleted"
  end

  def retry
    @chat.retry_last_message!
    redirect_to chat_path(@chat, thinking: true)
  end

  # Export chat as Markdown file
  def export_markdown
    markdown_content = generate_markdown_export(@chat)
    filename = sanitize_filename("#{@chat.title}_#{@chat.created_at.strftime('%Y%m%d')}.md")
    
    send_data markdown_content,
              filename: filename,
              type: "text/markdown",
              disposition: "attachment"
  end

  # Export chat as printable PDF (renders HTML for browser print)
  def export_pdf
    render layout: "pdf"
  end

  private
    def set_chat
      @chat = Current.user.chats.find(params[:id])
    end

    def set_last_viewed_chat(chat)
      Current.user.update!(last_viewed_chat: chat)
    end

    def clear_last_viewed_chat
      Current.user.update!(last_viewed_chat: nil)
    end

    def chat_params
      params.require(:chat).permit(:title, :content, :ai_model)
    end

    def generate_markdown_export(chat)
      lines = []
      lines << "# #{chat.title}"
      lines << ""
      lines << "_Exported from RUPI on #{Time.current.strftime('%B %d, %Y at %I:%M %p IST')}_"
      lines << ""
      lines << "---"
      lines << ""

      chat.conversation_messages.ordered.each do |message|
        timestamp = message.created_at.strftime("%b %d, %Y %I:%M %p")
        
        if message.is_a?(UserMessage)
          lines << "## 👤 You"
          lines << "_#{timestamp}_"
          lines << ""
          lines << message.content
        else
          lines << "## 🤖 RUPI"
          lines << "_#{timestamp}_"
          lines << ""
          lines << message.content
        end
        
        lines << ""
        lines << "---"
        lines << ""
      end

      lines << ""
      lines << "_Chat ID: #{chat.id}_"

      lines.join("\n")
    end

    def sanitize_filename(filename)
      filename.gsub(/[^0-9A-Za-z.\-_]/, '_').gsub(/_+/, '_')
    end
end

