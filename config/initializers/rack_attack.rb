# frozen_string_literal: true

class Rack::Attack
  # Enable Rack::Attack only in production/staging
  enabled = Rails.env.production? || Rails.env.staging?

  # Use Redis for cross-process tracking if available, fallback to ActiveSupport::Cache
  if Rails.env.production? && ENV["REDIS_URL"].present?
    Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"])
  end

  # ==========================================
  # LOGIN BRUTE FORCE PROTECTION
  # ==========================================
  
  # Throttle login attempts by IP (10 attempts per 5 minutes)
  throttle("logins/ip", limit: 10, period: 5.minutes) do |request|
    if request.path == "/sessions" && request.post?
      request.ip
    end
  end

  # Throttle login attempts by email (5 attempts per 15 minutes)
  throttle("logins/email", limit: 5, period: 15.minutes) do |request|
    if request.path == "/sessions" && request.post?
      # Normalize email for consistent tracking
      request.params.dig("email")&.to_s&.strip&.downcase&.presence
    end
  end

  # ==========================================
  # PASSWORD RESET PROTECTION
  # ==========================================
  
  # Throttle password reset requests by IP (5 per hour)
  throttle("password_resets/ip", limit: 5, period: 1.hour) do |request|
    if request.path == "/password_reset" && request.post?
      request.ip
    end
  end

  # Throttle password reset requests by email (3 per hour)
  throttle("password_resets/email", limit: 3, period: 1.hour) do |request|
    if request.path == "/password_reset" && request.post?
      request.params.dig("email")&.to_s&.strip&.downcase&.presence
    end
  end

  # ==========================================
  # REGISTRATION SPAM PROTECTION
  # ==========================================
  
  # Throttle registration attempts by IP (5 per hour)
  throttle("registrations/ip", limit: 5, period: 1.hour) do |request|
    if request.path == "/registration" && request.post?
      request.ip
    end
  end

  # ==========================================
  # API RATE LIMITING (Existing)
  # ==========================================

  # Throttle requests to the OAuth token endpoint
  throttle("oauth/token", limit: 10, period: 1.minute) do |request|
    request.ip if request.path == "/oauth/token"
  end

  # Determine limits based on self-hosted mode
  self_hosted = Rails.application.config.app_mode.self_hosted?

  # Throttle API requests per access token
  throttle("api/requests", limit: self_hosted ? 10_000 : 100, period: 1.hour) do |request|
    if request.path.start_with?("/api/")
      # Extract access token from Authorization header
      auth_header = request.get_header("HTTP_AUTHORIZATION")
      if auth_header&.start_with?("Bearer ")
        token = auth_header.split(" ").last
        "api_token:#{Digest::SHA256.hexdigest(token)}"
      else
        # Fall back to IP-based limiting for unauthenticated requests
        "api_ip:#{request.ip}"
      end
    end
  end

  # More permissive throttling for API requests by IP (for development/testing)
  throttle("api/ip", limit: self_hosted ? 20_000 : 200, period: 1.hour) do |request|
    request.ip if request.path.start_with?("/api/")
  end

  # ==========================================
  # MALICIOUS REQUEST BLOCKING
  # ==========================================

  # Block requests that appear to be malicious
  blocklist("block malicious requests") do |request|
    # Block requests with suspicious user agents
    suspicious_user_agents = [
      /sqlmap/i,
      /nmap/i,
      /nikto/i,
      /masscan/i
    ]

    user_agent = request.user_agent
    suspicious_user_agents.any? { |pattern| user_agent =~ pattern } if user_agent
  end

  # ==========================================
  # RESPONSE HANDLERS
  # ==========================================

  # Configure response for throttled requests
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = Time.current
    retry_after = (match_data[:period] - (now.to_i % match_data[:period])).to_s
    
    # Different response for HTML vs JSON
    if request.env["HTTP_ACCEPT"]&.include?("application/json") || request.path.start_with?("/api/")
      [
        429, # status
        {
          "Content-Type" => "application/json",
          "Retry-After" => retry_after
        },
        [ { error: "Too many requests. Please try again later." }.to_json ]
      ]
    else
      # For HTML requests, redirect back with error message
      [
        429,
        {
          "Content-Type" => "text/html",
          "Retry-After" => retry_after,
          "Location" => request.path
        },
        [ "<html><body><h1>Too Many Requests</h1><p>You've made too many attempts. Please wait a few minutes and try again.</p><p><a href='#{request.path}'>Try again</a></p></body></html>" ]
      ]
    end
  end

  # Configure response for blocked requests
  self.blocklisted_responder = lambda do |request|
    [
      403, # status
      { "Content-Type" => "application/json" },
      [ { error: "Request blocked." }.to_json ]
    ]
  end
end
