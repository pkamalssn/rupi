# Resend email delivery configuration
# Uses HTTP API instead of SMTP (more reliable on cloud platforms)

if ENV["RESEND_API_KEY"].present?
  Resend.api_key = ENV["RESEND_API_KEY"]
end
