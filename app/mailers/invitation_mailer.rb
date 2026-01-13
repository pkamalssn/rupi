class InvitationMailer < ApplicationMailer
  def invite_email(invitation)
    @invitation = invitation
    @accept_url = accept_invitation_url(@invitation.token)

    mail(
      to: @invitation.email,
      from: support_sender_address,
      subject: t(
        ".subject",
        inviter: @invitation.inviter.display_name,
        product: product_name
      )
    )
  end
end
