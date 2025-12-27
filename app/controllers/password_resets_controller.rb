class PasswordResetsController < ApplicationController
  skip_authentication

  layout "auth"

  before_action :set_user_by_token, only: %i[edit update]

  def new
  end

  def create
    email = params[:email]&.strip&.downcase
    
    if email.blank?
      flash.now[:alert] = t(".email_required")
      render :new, status: :unprocessable_entity
      return
    end
    
    user = User.find_by(email: email)
    
    if user
      # User exists - send reset email
      begin
        PasswordMailer.with(
          user: user,
          token: user.generate_token_for(:password_reset)
        ).password_reset.deliver_now
      rescue => e
        Rails.logger.error "Password reset email failed: #{e.class} - #{e.message}"
      end
      
      redirect_to new_password_reset_path(step: "pending")
    else
      # User doesn't exist - show helpful error
      flash.now[:alert] = t(".user_not_found")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @user = User.new
  end

  def update
    if @user.update(password_params)
      # Unlock account if it was locked (password reset unlocks)
      @user.unlock_access! if @user.access_locked?
      
      redirect_to new_session_path, notice: t(".success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

    def set_user_by_token
      @user = User.find_by_token_for(:password_reset, params[:token])
      redirect_to new_password_reset_path, alert: t("password_resets.update.invalid_token") unless @user.present?
    end

    def password_params
      params.require(:user).permit(:password, :password_confirmation)
    end
end
