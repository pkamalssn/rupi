# Auto-generate Active Record encryption keys when not configured
# This ensures encryption works out of the box without manual setup
# Works for both self-hosted and managed modes when credentials are missing
unless Rails.application.credentials.active_record_encryption.present?
  # Check if keys are provided via environment variables
  primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
  deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
  key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

  # If any key is missing, generate all of them based on SECRET_KEY_BASE
  if primary_key.blank? || deterministic_key.blank? || key_derivation_salt.blank?
    # Use SECRET_KEY_BASE as the seed for deterministic key generation
    # This ensures keys are consistent across container restarts
    secret_base = Rails.application.secret_key_base

    # Generate deterministic keys from the secret base
    primary_key = Digest::SHA256.hexdigest("#{secret_base}:primary_key")[0..63]
    deterministic_key = Digest::SHA256.hexdigest("#{secret_base}:deterministic_key")[0..63]
    key_derivation_salt = Digest::SHA256.hexdigest("#{secret_base}:key_derivation_salt")[0..63]
  end

  # Configure Active Record encryption
  Rails.application.config.active_record.encryption.primary_key = primary_key
  Rails.application.config.active_record.encryption.deterministic_key = deterministic_key
  Rails.application.config.active_record.encryption.key_derivation_salt = key_derivation_salt
end
