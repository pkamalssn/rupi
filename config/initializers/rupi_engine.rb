# frozen_string_literal: true

# RupiEngineConfig - Configuration for rupi-engine integration
#
# Environment Variables:
#   USE_ENGINE_CHAT_STREAM - Enable SSE streaming for chat (default: true)
#                            Set to "false" to use non-streaming endpoint
#
# Usage:
#   RupiEngineConfig.stream_chat?  # => true/false
#
module RupiEngineConfig
  class << self
    # Whether to use SSE streaming for chat responses
    # Disable this if SSE has issues in production (proxies, firewalls, etc.)
    def stream_chat?
      ENV.fetch("USE_ENGINE_CHAT_STREAM", "true").downcase == "true"
    end
    
    # Debug mode for verbose logging
    def debug?
      ENV.fetch("DEBUG_SIDECAR", "false").downcase == "true"
    end
  end
end
