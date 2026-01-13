class WelcomeMailer < ApplicationMailer
  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.welcome_mailer.welcome_email.subject
  #
  def welcome_email
    @user = params[:user]
    @product_name = Rails.configuration.x.product_name
    
    mail(
      to: @user.email,
      from: welcome_sender_address,
      subject: "Welcome to the #{@product_name} Beta! 🚀"
    )
  end
end

