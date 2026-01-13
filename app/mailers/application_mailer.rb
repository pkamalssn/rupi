class ApplicationMailer < ActionMailer::Base
  # Default sender for all emails (can be overridden by individual mailers)
  default from: -> { default_sender_address }
  
  layout "mailer"

  before_action :assign_branding

  helper_method :product_name, :brand_name

  private
    def assign_branding
      @product_name = product_name
      @brand_name = brand_name
    end

    def product_name
      Rails.configuration.x.product_name
    end

    def brand_name
      Rails.configuration.x.brand_name
    end

    # Email domain for sender addresses
    def email_domain
      ENV.fetch("EMAIL_DOMAIN", "mail.rupiapp.in")
    end

    # Default sender (used by most mailers)
    def default_sender_address
      email_address_with_name(
        ENV.fetch("EMAIL_SENDER", "vanakkam@#{email_domain}"),
        "#{brand_name} #{product_name}"
      )
    end

    # Welcome/greeting emails
    def welcome_sender_address
      email_address_with_name(
        "vanakkam@#{email_domain}",
        "#{brand_name} #{product_name}"
      )
    end

    # System notifications (password reset, email confirmation, etc.)
    def noreply_sender_address
      email_address_with_name(
        "noreply@#{email_domain}",
        "#{brand_name} #{product_name}"
      )
    end

    # Support/invitation emails
    def support_sender_address
      email_address_with_name(
        "support@#{email_domain}",
        "#{brand_name} #{product_name}"
      )
    end
end
