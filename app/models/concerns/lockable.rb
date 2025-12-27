# frozen_string_literal: true

# Account Lockable Security Module
# Implements brute-force protection for login attempts
#
# Configuration:
#   MAX_FAILED_ATTEMPTS = 5 (locks after 5 failed logins)
#   LOCK_DURATION = 1.hour (automatic unlock after 1 hour)
#
module Lockable
  extend ActiveSupport::Concern

  MAX_FAILED_ATTEMPTS = 5
  LOCK_DURATION = 1.hour

  included do
    # Reset failed attempts on successful password change
    after_update :reset_failed_attempts_if_password_changed
  end

  # Check if the account is currently locked
  def access_locked?
    return false if locked_at.nil?
    
    # Check if lock has expired (auto-unlock after LOCK_DURATION)
    if locked_at < LOCK_DURATION.ago
      unlock_access!
      false
    else
      true
    end
  end

  # Lock the account
  def lock_access!
    update_columns(
      locked_at: Time.current,
      unlock_token: SecureRandom.urlsafe_base64(32)
    )
    
    # Send notification email
    send_lock_notification
  end

  # Unlock the account
  def unlock_access!
    update_columns(
      locked_at: nil,
      unlock_token: nil,
      failed_attempts: 0
    )
  end

  # Increment failed attempts and lock if threshold reached
  def increment_failed_attempts!
    new_count = (failed_attempts || 0) + 1
    update_column(:failed_attempts, new_count)
    
    if new_count >= MAX_FAILED_ATTEMPTS
      lock_access!
    end
    
    new_count
  end

  # Reset failed attempts (called on successful login)
  def reset_failed_attempts!
    update_column(:failed_attempts, 0) if failed_attempts > 0
  end

  # Time remaining until auto-unlock (for display)
  def remaining_lock_time
    return 0 unless access_locked?
    
    unlock_time = locked_at + LOCK_DURATION
    [(unlock_time - Time.current).to_i, 0].max
  end

  # Human-readable lock time remaining
  def remaining_lock_time_in_words
    seconds = remaining_lock_time
    return "now" if seconds <= 0
    
    if seconds < 60
      "#{seconds} seconds"
    elsif seconds < 3600
      "#{(seconds / 60).ceil} minutes"
    else
      "#{(seconds / 3600.0).ceil} hour(s)"
    end
  end

  private

  def reset_failed_attempts_if_password_changed
    if saved_change_to_password_digest? && failed_attempts > 0
      update_column(:failed_attempts, 0)
    end
  end

  def send_lock_notification
    # TODO: Create a mailer for security notifications
    Rails.logger.warn "Account locked: #{email} after #{failed_attempts} failed attempts"
    
    # Optionally send email notification
    # SecurityMailer.account_locked(self).deliver_later
  end
end
