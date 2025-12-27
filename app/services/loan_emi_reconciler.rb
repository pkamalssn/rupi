# frozen_string_literal: true

# Reconciles EMI payments from bank statements with loan accounts
# Finds debits like "HDFC LTD EMI" in bank accounts and links them to loan EMI entries
class LoanEmiReconciler
  # Common patterns for EMI debits in bank statements
  EMI_PATTERNS = [
    /\bEMI\b/i,
    /\bHOME\s*LOAN\b/i,
    /\bPERSONAL\s*LOAN\b/i,
    /\bCAR\s*LOAN\b/i,
    /\bVEHICLE\s*LOAN\b/i,
    /\bLOAN\s*(?:REPAY|PMT|PAYMENT)\b/i,
    /\bLOAN\s*EMI\b/i,
    /\bINSTAL?L?MENT\b/i,
    # Specific lenders
    /\bHDFC\s*(?:LTD|BANK|HOME)?\s*(?:LN|LOAN|EMI)\b/i,
    /\bICICI\s*(?:LTD|BANK|HOME)?\s*(?:LN|LOAN|EMI)\b/i,
    /\bSBI\s*(?:HOME)?\s*(?:LN|LOAN|EMI)\b/i,
    /\bAXIS\s*(?:LN|LOAN|EMI)\b/i,
    /\bBAJAJ\s*(?:FIN|FINANCE)?\s*(?:EMI|LOAN)\b/i,
    /\bCRED\s*(?:CASH|PAY|EMI)\b/i,
    /\bPAYTM\s*(?:LOAN|EMI)\b/i,
    /\bSLICE\s*(?:EMI|PAY)\b/i,
  ].freeze

  # Lender name patterns for matching
  LENDER_PATTERNS = {
    "HDFC" => /\bHDFC\b/i,
    "ICICI" => /\bICICI\b/i,
    "SBI" => /\bSBI\b/i,
    "Axis" => /\bAXIS\b/i,
    "Bajaj" => /\bBAJAJ\b/i,
    "Kotak" => /\bKOTAK\b/i,
    "CRED" => /\bCRED\b/i,
    "Paytm" => /\bPAYTM\b/i,
    "Slice" => /\bSLICE\b/i,
    "IndusInd" => /\bINDUS\b/i,
  }.freeze

  attr_reader :family, :results

  def initialize(family)
    @family = family
    @results = { 
      linked: [],       # Successfully linked transfers
      unmatched: [],    # EMI debits that couldn't be matched to a loan
      errors: [] 
    }
  end

  # Run reconciliation for all loan accounts in the family
  def reconcile_all
    loan_accounts = family.accounts.joins(:accountable)
                          .where(accountable_type: "Loan")
                          .where.not(status: "pending_deletion")

    return results if loan_accounts.empty?

    # Get all bank accounts with potential EMI debits
    bank_accounts = family.accounts
                          .where(accountable_type: "Depository")
                          .where.not(status: "pending_deletion")

    return results if bank_accounts.empty?

    # Find all potential EMI debits from bank statements
    potential_emi_debits = find_potential_emi_debits(bank_accounts)
    Rails.logger.info("LoanEmiReconciler: Found #{potential_emi_debits.count} potential EMI debits")

    # Match each loan account's EMIs
    loan_accounts.find_each do |loan_account|
      reconcile_loan_account(loan_account, potential_emi_debits)
    end

    # Flag remaining unmatched EMI debits
    flag_unmatched_debits(potential_emi_debits)

    Rails.logger.info("LoanEmiReconciler: Linked #{results[:linked].count}, Unmatched #{results[:unmatched].count}")
    results
  end

  # Reconcile EMIs for a specific loan account
  def reconcile_loan_account(loan_account, potential_emi_debits = nil)
    loan = loan_account.accountable
    return unless loan

    lender_name = loan_account.name || loan.lender_name || ""
    emi_amount = loan.emi_amount&.abs || loan_account.accountable.try(:emi_amount)&.abs

    # Find potential EMI debits if not provided
    if potential_emi_debits.nil?
      bank_accounts = family.accounts
                            .where(accountable_type: "Depository")
                            .where.not(status: "pending_deletion")
      potential_emi_debits = find_potential_emi_debits(bank_accounts)
    end

    # Get loan's payment entries (EMI payments)
    loan_entries = loan_account.entries
                               .joins(:entryable)
                               .where(entryable_type: "Transaction")
                               .where("entries.amount > 0")  # Payments are positive for loans
                               .where(transfer_id: nil)  # Not already linked
                               .to_a

    # Try to match EMI debits to this loan
    matched_debits = find_matching_debits(
      potential_emi_debits,
      lender_name: lender_name,
      emi_amount: emi_amount
    )

    matched_debits.each do |bank_entry|
      # Skip if already processed
      next if bank_entry.transfer_id.present?
      
      # Find a loan entry on the same date (or within 3 days)
      matching_loan_entry = loan_entries.find do |le|
        (le.date - bank_entry.date).abs <= 3 && 
        (le.amount.abs - bank_entry.amount.abs).abs < 100  # Within ₹100 tolerance
      end

      if matching_loan_entry
        # Create a transfer to link them
        link_result = create_emi_transfer(bank_entry, matching_loan_entry, loan_account)
        if link_result
          results[:linked] << link_result
          # Remove from further matching
          loan_entries.delete(matching_loan_entry)
          potential_emi_debits.delete(bank_entry)
        end
      end
    end
  end

  private

  # Create a transfer linking the bank debit to the loan payment
  def create_emi_transfer(bank_entry, loan_entry, loan_account)
    # Bank entry is outflow (negative/debit)
    # Loan entry is inflow (positive, reduces liability)
    
    outflow_transaction = bank_entry.entryable
    inflow_transaction = loan_entry.entryable
    
    return nil unless outflow_transaction.is_a?(Transaction) && inflow_transaction.is_a?(Transaction)

    begin
      Transfer.transaction do
        # Create the transfer
        transfer = Transfer.create!(
          inflow_transaction: inflow_transaction,
          outflow_transaction: outflow_transaction,
          status: "confirmed"
        )

        # Update transaction kinds
        outflow_transaction.update!(kind: "loan_payment")
        inflow_transaction.update!(kind: "loan_payment")

        # Update entry names to show linked status
        bank_entry.update!(name: "#{bank_entry.name} → #{loan_account.name}")
        loan_entry.update!(name: loan_entry.name.gsub(/\s*\(Linked\)$/, "") + " (Linked)")

        Rails.logger.info("LoanEmiReconciler: Linked #{bank_entry.name} to #{loan_account.name}")

        {
          transfer_id: transfer.id,
          bank_entry_id: bank_entry.id,
          loan_entry_id: loan_entry.id,
          date: bank_entry.date,
          amount: bank_entry.amount.abs,
          bank_account: bank_entry.account.name,
          loan_account: loan_account.name
        }
      end
    rescue => e
      Rails.logger.warn("LoanEmiReconciler: Failed to create transfer: #{e.message}")
      results[:errors] << { bank_entry_id: bank_entry.id, error: e.message }
      nil
    end
  end

  # Find all entries that look like EMI payments
  def find_potential_emi_debits(bank_accounts)
    return [] if bank_accounts.empty?

    # EMI debits are negative amounts (money going out)
    entries = Entry.joins(:entryable)
                   .where(account: bank_accounts)
                   .where(entryable_type: "Transaction")
                   .where("amount < 0")  # Debits
                   .where(transfer_id: nil)  # Not already linked
                   .where("date >= ?", 2.years.ago)  # Recent transactions

    # Filter by EMI patterns
    entries.select do |entry|
      EMI_PATTERNS.any? { |pattern| entry.name.match?(pattern) }
    end
  end

  # Find debits that match a specific loan
  def find_matching_debits(debits, lender_name:, emi_amount:)
    return [] if debits.empty?

    # Extract lender pattern from the loan's lender name
    lender_pattern = LENDER_PATTERNS.find { |name, _| lender_name.upcase.include?(name.upcase) }&.last

    debits.select do |entry|
      # Check if amount matches (within 10% tolerance for charges/fees)
      amount_match = emi_amount.nil? || emi_amount.zero? ||
                     (entry.amount.abs >= emi_amount * 0.9 && entry.amount.abs <= emi_amount * 1.1)

      # Check if lender matches (if we have a pattern)
      lender_match = lender_pattern.nil? || entry.name.match?(lender_pattern)

      amount_match && lender_match
    end
  end

  # Flag unmatched EMI debits for review
  def flag_unmatched_debits(remaining_debits)
    remaining_debits.each do |entry|
      # Already transferred or already flagged
      next if entry.transfer_id.present?
      next if entry.name.include?("(Unlinked EMI)")

      results[:unmatched] << {
        entry_id: entry.id,
        date: entry.date,
        amount: entry.amount.abs,
        description: entry.name,
        bank_account: entry.account.name
      }

      # Optionally update the entry name to flag it
      # entry.update!(name: entry.name + " (Unlinked EMI)")
    end
  end
end
