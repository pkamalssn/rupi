class OnboardingsController < ApplicationController
  layout "wizard", except: [:dismiss, :restart]

  before_action :set_user
  before_action :load_invitation, except: [:dismiss, :restart]

  def show
  end

  def preferences
  end

  def trial
  end

  # Dismiss guided onboarding
  def dismiss
    Current.user.update!(
      preferences: Current.user.preferences.merge("guided_onboarding_completed" => true)
    )
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: root_path) }
      format.json { head :ok }
    end
  end

  # Restart guided onboarding
  def restart
    Current.user.update!(
      preferences: Current.user.preferences.merge(
        "guided_onboarding_completed" => false,
        "tour_completed" => false
      )
    )
    
    respond_to do |format|
      format.html { redirect_to root_path, notice: "Guided onboarding restarted!" }
      format.json { head :ok }
    end
  end

  private
    def set_user
      @user = Current.user
    end

    def load_invitation
      @invitation = Current.family.invitations.accepted.find_by(email: Current.user.email)
    end
end

