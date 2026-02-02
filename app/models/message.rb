class Message < ApplicationRecord
  belongs_to :chat
  has_many :tool_calls, dependent: :destroy

  # Encrypt message content at rest (contains sensitive financial data)
  # Uses same pattern as EnableBankingItem - only encrypt if keys are available
  def self.encryption_ready?
    creds_ready = Rails.application.credentials.active_record_encryption.present?
    env_ready = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present? &&
                ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].present? &&
                ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].present?
    # Also check if we're in self-hosted mode (auto-generates keys)
    self_hosted = Rails.application.config.respond_to?(:app_mode) && 
                  Rails.application.config.app_mode.self_hosted?
    creds_ready || env_ready || self_hosted
  end

  if encryption_ready?
    encrypts :content
  end

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
