# Branding configuration for RUPI
# Your AI powered money managing buddy

Rails.application.configure do
  config.x.product_name = ENV.fetch("PRODUCT_NAME", "RUPI")
  config.x.brand_name = ENV.fetch("BRAND_NAME", "")
  config.x.tagline = "Your AI powered money managing buddy"
end
