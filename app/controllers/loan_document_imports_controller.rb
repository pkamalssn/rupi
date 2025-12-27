# frozen_string_literal: true

class LoanDocumentImportsController < ApplicationController
  before_action :set_import, only: [:show, :review, :update, :publish, :destroy]

  def new
    @import = Current.family.loan_document_imports.new
  end

  def create
    @import = Current.family.loan_document_imports.new(import_params)
    
    if @import.documents.attached?
      # Set status to processing immediately
      @import.status = :processing
      @import.save!
      
      # Process inline for immediate feedback (simplifies dev/testing)
      # Gemini API takes ~5-10s which is acceptable for this UX
      @import.process_document!
      
      if @import.review?
        redirect_to review_loan_document_import_path(@import), 
                    notice: "Analysis complete! Please review the details."
      else
        redirect_to loan_document_import_path(@import), 
                    alert: "Analysis failed: #{@import.error}"
      end
    else
      flash.now[:alert] = "Please attach a loan document (PDF, image, or screenshot)"
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # Shows current status - processing, review, complete, or failed
  end

  def review
    unless @import.review?
      redirect_to loan_document_import_path(@import), 
                  alert: "This import is not ready for review"
      return
    end
  end

  def update
    if @import.update(edit_params)
      if params[:commit] == "publish" || params[:commit] == "Create Loan Account"
        return publish
      end

      redirect_to review_loan_document_import_path(@import), 
                  notice: "Changes saved"
    else
      render :review, status: :unprocessable_entity
    end
  end

  def publish
    unless @import.review?
      redirect_to loan_document_import_path(@import), 
                  alert: "This import is not ready to publish"
      return
    end

    if @import.publish!
      redirect_to account_path(@import.account), 
                  notice: "Loan account created successfully!"
    else
      flash.now[:alert] = @import.error || "Failed to create loan account"
      render :review, status: :unprocessable_entity
    end
  end

  def destroy
    @import.destroy
    redirect_to new_loan_document_import_path, notice: "Import cancelled"
  end

  private

  def set_import
    @import = Current.family.loan_document_imports.find(params[:id])
  end

  def import_params
    params.require(:loan_document_import).permit(documents: [])
  end

  def edit_params
    params.require(:loan_document_import).permit(
      :lender_name,
      :loan_type,
      :principal_amount,
      :currency,
      :interest_rate,
      :rate_type,
      :tenure_months,
      :emi_amount,
      :emi_day,
      :disbursement_date,
      :loan_account_number,
      :outstanding_balance,
      :maturity_date,
      :processing_fee,
      :prepayment_charges,
      :notes
    )
  end
end
