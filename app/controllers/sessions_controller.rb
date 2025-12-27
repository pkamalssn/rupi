class SessionsController < ApplicationController
  before_action :set_session, only: :destroy
  skip_authentication only: %i[new create openid_connect failure]

  layout "auth"

  def new
    demo = demo_config
    @prefill_demo_credentials = demo_host_match?(demo)

    if @prefill_demo_credentials
      @email = params[:email].presence || demo["email"]
      @password = params[:password].presence || demo["password"]
    else
      @email = params[:email]
      @password = params[:password]
    end
  end

  def create
    user = User.find_by(email: params[:email]&.strip&.downcase)
    
    # Check if account exists
    unless user
      flash.now[:alert] = t(".invalid_credentials")
      render :new, status: :unprocessable_entity
      return
    end
    
    # Check if account is locked
    if user.access_locked?
      flash.now[:alert] = t(".account_locked", time: user.remaining_lock_time_in_words)
      render :new, status: :unprocessable_entity
      return
    end
    
    # Attempt authentication
    if user.authenticate(params[:password])
      # Success - reset failed attempts and proceed
      user.reset_failed_attempts!
      
      if user.otp_required?
        session[:mfa_user_id] = user.id
        redirect_to verify_mfa_path
      else
        @session = create_session_for(user)
        redirect_to root_path
      end
    else
      # Failed - increment attempts
      attempts = user.increment_failed_attempts!
      remaining = Lockable::MAX_FAILED_ATTEMPTS - attempts
      
      if user.access_locked?
        flash.now[:alert] = t(".account_locked", time: user.remaining_lock_time_in_words)
      elsif remaining > 0
        flash.now[:alert] = t(".invalid_credentials_with_warning", remaining: remaining)
      else
        flash.now[:alert] = t(".invalid_credentials")
      end
      
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @session.destroy
    redirect_to new_session_path, notice: t(".logout_successful")
  end

  def openid_connect
    auth = request.env["omniauth.auth"]

    # Nil safety: ensure auth and required fields are present
    unless auth&.provider && auth&.uid
      redirect_to new_session_path, alert: t("sessions.openid_connect.failed")
      return
    end

    # Security fix: Look up by provider + uid, not just email
    oidc_identity = OidcIdentity.find_by(provider: auth.provider, uid: auth.uid)

    if oidc_identity
      # Existing OIDC identity found - authenticate the user
      user = oidc_identity.user
      oidc_identity.record_authentication!

      # MFA check: If user has MFA enabled, require verification
      if user.otp_required?
        session[:mfa_user_id] = user.id
        redirect_to verify_mfa_path
      else
        @session = create_session_for(user)
        redirect_to root_path
      end
    else
      # No existing OIDC identity - need to link to account
      # Store auth data in session and redirect to linking page
      session[:pending_oidc_auth] = {
        provider: auth.provider,
        uid: auth.uid,
        email: auth.info&.email,
        name: auth.info&.name,
        first_name: auth.info&.first_name,
        last_name: auth.info&.last_name
      }
      redirect_to link_oidc_account_path
    end
  end

  def failure
    redirect_to new_session_path, alert: t("sessions.failure.failed")
  end

  private
    def set_session
      @session = Current.user.sessions.find(params[:id])
    end
end
