# Preview all emails at http://localhost:3000/rails/mailers/welcome_mailer
class WelcomeMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/welcome_mailer/welcome_email
  def welcome_email
    WelcomeMailer.welcome_email
  end
end
