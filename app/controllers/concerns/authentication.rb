module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_request_details
    before_action :authenticate_user!
    before_action :set_sentry_user
  end

  class_methods do
    def skip_authentication(**options)
      skip_before_action :authenticate_user!, **options
      skip_before_action :set_sentry_user, **options
    end
  end

  private
    def authenticate_user!
      if session_record = find_session_by_cookie
        Current.session = session_record
      else
        if self_hosted_first_login?
          redirect_to new_registration_url
        else
          redirect_to new_session_url
        end
      end
    end

    def find_session_by_cookie
      session_id = session[:session_token] || cookies.signed[:session_token]
      return nil unless session_id.present?
      
      Session.find_by(id: session_id)
    end

    def create_session_for(user)
      # Clear any stale session data to prevent conflicts
      cookies.delete(:session_token)
      session.delete(:session_token)
      
      # Create new session
      user_session = user.sessions.create!
      
      # Store in both Rails session AND signed cookie for redundancy
      session[:session_token] = user_session.id
      cookies.signed[:session_token] = {
        value: user_session.id,
        expires: 20.years.from_now,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax
      }
      
      user_session
    end

    def self_hosted_first_login?
      Rails.application.config.app_mode.self_hosted? && User.count.zero?
    end

    def set_request_details
      Current.user_agent = request.user_agent
      Current.ip_address = request.ip
    end

    def set_sentry_user
      return unless defined?(Sentry) && ENV["SENTRY_DSN"].present?

      if Current.user
        Sentry.set_user(
          id: Current.user.id,
          email: Current.user.email,
          username: Current.user.display_name,
          ip_address: Current.ip_address
        )
      end
    end
end
