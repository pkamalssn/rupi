class Message < ApplicationRecord
  belongs_to :chat
  has_many :tool_calls, dependent: :destroy

  enum :status, {
    pending: "pending",
    complete: "complete",
    failed: "failed"
  }

  # Allow blank content for:
  # 1. Messages with tool_calls
  # 2. AssistantMessage during function call processing (tool_calls may be set after save)
  validates :content, presence: true, unless: -> { tool_calls.any? || is_a?(AssistantMessage) }

  after_create_commit -> { broadcast_append_to chat, target: "messages" }, if: :broadcast?
  after_update_commit -> { broadcast_update_to chat }, if: :broadcast?

  scope :ordered, -> { order(created_at: :asc) }

  private
    def broadcast?
      true
    end
end
