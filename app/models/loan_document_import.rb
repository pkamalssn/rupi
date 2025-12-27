# frozen_string_literal: true

class LoanDocumentImport < ApplicationRecord
  belongs_to :family
  belongs_to :account, optional: true
  
  # Support multiple documents for comprehensive loan data
  has_many_attached :documents

  enum :status, {
    pending: "pending",
    processing: "processing",
    review: "review",
    complete: "complete",
    failed: "failed"
  }, validate: true, default: "pending"

  LOAN_TYPES = Loan::SUBTYPES.keys.freeze

  validates :lender_name, presence: true, on: :publish
  validates :principal_amount, numericality: { greater_than: 0 }, on: :publish
  validates :loan_type, inclusion: { in: LOAN_TYPES }, allow_blank: true

  # Process all uploaded documents with AI and merge results
  def process_document!
    return if documents.blank?
    
    update!(status: :processing)
    
    begin
      provider = Provider::Registry.get_provider(:gemini)
      
      unless provider
        update!(status: :failed, error: "Gemini AI provider not configured")
        return
      end

      # Process each document and collect results
      all_extracted = []
      all_transactions = []
      
      documents.each do |doc|
        result = provider.parse_loan_document(
          file: doc,
          family: family
        )

        if result.success?
          extracted = result.data
          all_extracted << extracted
          
          # Collect transactions from each document
          if extracted[:transactions].present?
            all_transactions.concat(extracted[:transactions])
          end
        else
          Rails.logger.warn("Failed to parse document #{doc.filename}: #{result.error&.message}")
        end
      end

      if all_extracted.empty?
        update!(status: :failed, error: "Failed to parse any documents")
        return
      end

      # Merge data from all documents, preferring non-nil values
      merged = merge_extracted_data(all_extracted)
      
      # Merge and deduplicate transactions
      merged[:transactions] = deduplicate_transactions(all_transactions)
      
      update!(
        status: :review,
        extracted_data: merged,
        lender_name: merged[:lender_name],
        loan_type: merged[:loan_type],
        principal_amount: merged[:principal_amount],
        currency: merged[:currency] || "INR",
        interest_rate: merged[:interest_rate],
        rate_type: merged[:rate_type],
        tenure_months: merged[:tenure_months],
        emi_amount: merged[:emi_amount],
        emi_day: merged[:emi_day],
        disbursement_date: merged[:disbursement_date],
        loan_account_number: merged[:loan_account_number],
        outstanding_balance: merged[:outstanding_balance],
        maturity_date: merged[:maturity_date],
        processing_fee: merged[:processing_fee],
        prepayment_charges: merged[:prepayment_charges],
        confidence: merged[:confidence],
        notes: merged[:notes]
      )
    rescue => e
      update!(status: :failed, error: e.message)
      Rails.logger.error("LoanDocumentImport#process_document! failed: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
    end
  end

  # Merge extracted data from multiple documents
  # Prefers: latest outstanding balance, longest transaction list, non-nil values
  def merge_extracted_data(extracts)
    return extracts.first if extracts.size == 1
    
    merged = {}
    
    # Fields where we want the first non-nil value
    [:lender_name, :loan_type, :principal_amount, :currency, :rate_type, 
     :emi_day, :disbursement_date, :loan_account_number, :maturity_date,
     :processing_fee, :prepayment_charges].each do |field|
      merged[field] = extracts.map { |e| e[field] }.compact.first
    end
    
    # For interest_rate, emi_amount, tenure_months - prefer latest (last extract often has updates)
    [:interest_rate, :emi_amount, :tenure_months].each do |field|
      values = extracts.map { |e| e[field] }.compact
      merged[field] = values.last if values.any?
    end
    
    # Outstanding balance - prefer the most recent (highest value usually means more recent statement)
    balances = extracts.map { |e| e[:outstanding_balance] }.compact
    merged[:outstanding_balance] = balances.min if balances.any?  # Lower = more recent for loans
    
    # Confidence - average
    confidences = extracts.map { |e| e[:confidence] }.compact
    merged[:confidence] = confidences.any? ? (confidences.sum / confidences.size) : nil
    
    # Notes - combine all
    notes = extracts.map { |e| e[:notes] }.compact
    merged[:notes] = notes.join("\n---\n") if notes.any?
    
    merged
  end

  # Deduplicate transactions by date + amount + type
  def deduplicate_transactions(transactions)
    return [] if transactions.blank?
    
    seen = Set.new
    transactions.select do |tx|
      date = tx[:date] || tx["date"]
      amount = (tx[:amount] || tx["amount"]).to_f.round(2)
      type = (tx[:type] || tx["type"]).to_s.downcase
      
      key = "#{date}_#{amount}_#{type}"
      if seen.include?(key)
        false
      else
        seen.add(key)
        true
      end
    end.sort_by { |tx| (tx[:date] || tx["date"]) || Date.new(1900) }
  end

  # Create the loan account from extracted/edited data
  def publish!
    return false unless valid?(:publish)
    return false unless review?
    
    transaction do
      # Try to match an existing account first
      loan_account = match_existing_account
      
      if loan_account
        # Update existing loan details specific to the loan (accountable)
        loan = loan_account.accountable
        loan.update!(
          interest_rate: interest_rate || loan.interest_rate,
          rate_type: rate_type || loan.rate_type,
          term_months: tenure_months || loan.term_months,
          emi_day: emi_day || loan.emi_day,
          actual_emi: emi_amount.present? && emi_amount.to_f > 0 ? emi_amount : loan.actual_emi,
          lender_name: lender_name || loan.lender_name,
          loan_account_number: loan_account_number || loan.loan_account_number
        )
      else
        # Create new loan account if no match found
        loan_account = family.accounts.create!(
          name: generate_account_name,
          balance: outstanding_balance.present? ? -outstanding_balance : -principal_amount,
          currency: currency || family.currency,
          accountable: Loan.new(
            subtype: loan_type || "other",
            interest_rate: interest_rate,
            rate_type: rate_type || "fixed",
            term_months: tenure_months,
            emi_day: emi_day,
            actual_emi: emi_amount,
            lender_name: lender_name,
            loan_account_number: loan_account_number,
            disbursement_date: disbursement_date
          )
        )

        # Create initial balance entry if we have disbursement date (only for new accounts)
        if disbursement_date.present? && principal_amount.present?
          manager = Account::OpeningBalanceManager.new(loan_account)
          manager.set_opening_balance(
            balance: -principal_amount,
            date: disbursement_date
          )
        end
      end

      # Import any extracted transactions
      if extracted_data.present? && extracted_data["transactions"].present?
        import_transactions(loan_account, extracted_data["transactions"])
      end

      # Run EMI reconciliation against bank statements
      # This matches bank debits (HDFC LTD EMI, etc.) to loan EMI entries
      begin
        reconciler = LoanEmiReconciler.new(family)
        reconciler.reconcile_loan_account(loan_account)
        
        if reconciler.results[:matched].any?
          Rails.logger.info("LoanDocumentImport: Reconciled #{reconciler.results[:matched].count} EMI payments from bank statements")
        end
      rescue => e
        Rails.logger.warn("LoanDocumentImport: EMI reconciliation failed: #{e.message}")
        # Don't fail the import if reconciliation fails
      end

      update!(
        status: :complete,
        account: loan_account
      )

      # PRIVACY: Delete uploaded documents after successful import
      # We only keep the extracted loan data, not the original documents
      purge_documents!

      loan_account
    end
  rescue => e
    update!(error: e.message)
    Rails.logger.error("LoanDocumentImport#publish! failed: #{e.message}")
    false
  end

  # Privacy-first: Delete all uploaded documents
  def purge_documents!
    return unless documents.attached?
    
    documents.purge
    Rails.logger.info "[Privacy] Loan documents purged for import ##{id}"
  end

  def match_existing_account
    return nil if loan_account_number.blank?
    
    # Clean matches: remove spaces/dashes for comparison
    clean_number = loan_account_number.to_s.gsub(/[\s-]/, "")
    
    # Try to find a loan account with matching number
    # We join Account -> Loan (accountable)
    Account.joins("INNER JOIN loans ON accounts.accountable_id = loans.id AND accounts.accountable_type = 'Loan'")
           .where(family: family)
           .where.not(status: "pending_deletion")
           .where("REPLACE(REPLACE(loans.loan_account_number, ' ', ''), '-', '') = ?", clean_number)
           .first
  end

  private

  def import_transactions(account, transactions)
    return if transactions.blank?

    transactions.each do |tx|
      # Normalize keys (handle string vs symbol)
      date = tx["date"] || tx[:date]
      amount_val = (tx["amount"] || tx[:amount]).to_f
      type = (tx["type"] || tx[:type]).to_s.downcase
      desc = tx["description"] || tx[:description]
      principal = (tx["principal_component"] || tx[:principal_component]).to_f
      interest = (tx["interest_component"] || tx[:interest_component]).to_f

      next if date.blank? || amount_val.zero?

      # Skip "Due for Installment" / "EMI Due" lines as they are just demand notices
      # and cancel out the actual payments, causing balance to stagnate.
      next if desc.to_s.downcase.match?(/due for (installment|instalment)|installment due|emi due/)

      # Calculate signed amount for Liability account
      # Payment/Prepayment increases balance (less negative) -> Positive
      # Interest/Charges decrease balance (more negative) -> Negative
      # Disbursement is the initial debt -> Negative
      signed_amount = case type
                      when "payment", "prepayment" then amount_val.abs
                      when "interest", "charge", "disbursement" then -amount_val.abs
                      else amount_val.abs # Default to payment if unknown
                      end

      # Build a descriptive name
      name = case type
             when "payment"
               if principal > 0 && interest > 0
                 "EMI Payment (P: ₹#{principal.round}, I: ₹#{interest.round})"
               else
                 desc.presence || "EMI Payment"
               end
             when "prepayment"
               desc.presence || "Loan Prepayment"
             when "interest"
               desc.presence || "Interest Charged"
             when "disbursement"
               desc.presence || "Loan Disbursement"
             when "charge"
               desc.presence || "Loan Charge/Fee"
             else
               desc.presence || "Imported #{type&.humanize}"
             end

      # Check for duplicate entry (same date, same amount)
      # This prevents re-importing same transactions
      next if account.entries.where(date: date, amount: signed_amount).exists?

      account.entries.create!(
        date: date,
        amount: signed_amount,
        currency: currency || family.currency,
        name: name,
        entryable: Transaction.new
      )
    end
  end

  public

  def low_confidence?
    confidence.present? && confidence < 0.7
  end

  def medium_confidence?
    confidence.present? && confidence >= 0.7 && confidence < 0.9
  end

  def high_confidence?
    confidence.present? && confidence >= 0.9
  end

  def confidence_label
    return "Unknown" unless confidence.present?
    
    if high_confidence?
      "High (#{(confidence * 100).round}%)"
    elsif medium_confidence?
      "Medium (#{(confidence * 100).round}%)"
    else
      "Low (#{(confidence * 100).round}%)"
    end
  end

  def loan_type_display
    return "Other" if loan_type.blank?
    Loan::SUBTYPES.dig(loan_type, :long) || loan_type.humanize
  end

  private

  def generate_account_name
    parts = []
    parts << lender_name if lender_name.present?
    parts << loan_type_display
    parts.join(" - ").presence || "Imported Loan"
  end
end
