# frozen_string_literal: true

# Controller for bank statement uploads
class BankStatementsController < ApplicationController
  def new
    @import = Current.family.imports.new(type: "BankStatementImport")
    @banks = BankStatementImport::SUPPORTED_BANKS + BankStatementImport::SUPPORTED_CREDIT_CARDS
    @credit_card_mode = params[:type] == "credit_card"
    
    # Pre-select first credit card option if coming from credit card link
    @import.bank_name = BankStatementImport::SUPPORTED_CREDIT_CARDS.first if @credit_card_mode
  end

  def create
    # Handle params from Rails form helper (nested under bank_statement_import)
    import_params = params[:bank_statement_import] || params
    
    @import = Current.family.imports.new(
      type: "BankStatementImport",
      bank_name: import_params[:bank_name] || params[:bank_name],
      account_number: import_params[:account_number] || params[:account_number],
      status: :pending
    )

    if @import.save
      # Try to get file from nested params first, then flat params
      statement_file = import_params[:statement_file] || params[:statement_file]
      
      if statement_file&.respond_to?(:read)
        @import.statement_file.attach(statement_file)
        @import.password = params[:password] if params[:password].present?
        
        # Trigger the import process
        @import.publish_later
        
        redirect_to import_path(@import), notice: "Statement uploaded successfully. Processing will begin shortly."
      else
        @import.destroy
        redirect_to new_bank_statement_path, alert: "Please select a file to upload."
      end
    else
      @banks = BankStatementImport::SUPPORTED_BANKS + BankStatementImport::SUPPORTED_CREDIT_CARDS
      render :new, status: :unprocessable_entity
    end
  rescue => e
    Rails.logger.error("Bank statement upload failed: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    redirect_to new_bank_statement_path, alert: "Failed to upload statement: #{e.message}"
  end
end
