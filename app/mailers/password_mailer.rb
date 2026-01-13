class PasswordMailer < ApplicationMailer
  def password_reset
    @user = params[:user]
    @subject = t(".subject", product_name: product_name)
    @cta = t(".cta")

    mail to: @user.email, from: noreply_sender_address, subject: @subject
  end
end
