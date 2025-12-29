class ImportsController < ApplicationController
  include SettingsHelper

  before_action :set_import, only: %i[show publish destroy revert apply_template recategorize]

  def publish
    @import.publish_later

    redirect_to import_path(@import), notice: "Your import has started in the background."
  rescue Import::MaxRowCountExceededError
    redirect_back_or_to import_path(@import), alert: "Your import exceeds the maximum row count of #{@import.max_row_count}."
  end
  
  def recategorize
    # Get uncategorized transactions from this import
    uncategorized_transactions = Transaction.joins(:entry)
                                            .where(entries: { import_id: @import.id })
                                            .where(category_id: nil)
    
    uncategorized_count = uncategorized_transactions.count
    
    if uncategorized_count == 0
      redirect_to import_path(@import), notice: "All transactions are already categorized!"
      return
    end
    
    # Start AI categorization
    job = AutoCategorizeJob.perform_later(
      Current.family,
      transaction_ids: uncategorized_transactions.pluck(:id),
      import_id: @import.id
    )
    
    # Update import tracking
    @import.start_categorization!(
      job_id: job.job_id,
      total_count: uncategorized_count
    )
    
    redirect_to import_path(@import), notice: "AI categorization started for #{uncategorized_count} transactions..."
  end

  def index
    @imports = Current.family.imports
    @exports = Current.user.admin? ? Current.family.family_exports.ordered.limit(10) : nil
    @breadcrumbs = [
      [ "Home", root_path ],
      [ "Import/Export", imports_path ]
    ]
    render layout: "settings"
  end

  def new
    @pending_import = Current.family.imports.ordered.pending.first
  end

  def create
    account = Current.family.accounts.find_by(id: params.dig(:import, :account_id))
    import = Current.family.imports.create!(
      type: import_params[:type],
      account: account,
      date_format: Current.family.date_format,
    )

    redirect_to import_upload_path(import)
  end

  def show
    # BankStatementImport uses a simpler flow - no multi-step configuration needed
    if @import.is_a?(BankStatementImport)
      # Just show the status page - no redirects needed
      return
    end
    
    if !@import.uploaded?
      redirect_to import_upload_path(@import), alert: "Please finalize your file upload."
    elsif !@import.publishable?
      redirect_to import_confirm_path(@import), alert: "Please finalize your mappings before proceeding."
    end
  end

  def revert
    @import.revert_later
    redirect_to imports_path, notice: "Import is reverting in the background."
  end

  def apply_template
    if @import.suggested_template
      @import.apply_template!(@import.suggested_template)
      redirect_to import_configuration_path(@import), notice: "Template applied."
    else
      redirect_to import_configuration_path(@import), alert: "No template found, please manually configure your import."
    end
  end

  def destroy
    @import.destroy

    redirect_to imports_path, notice: "Your import has been deleted."
  end

  private
    def set_import
      @import = Current.family.imports.find(params[:id])
    end

    def import_params
      params.require(:import).permit(:type)
    end
end
