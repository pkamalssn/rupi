# frozen_string_literal: true

class Assistant::Function::GetLoans < Assistant::Function
  class << self
    def name
      "get_loans"
    end

    def description
      "Get user's loans including home loans, personal loans, car loans with EMI schedules, outstanding amounts, and tax benefits"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      properties: {
        type: {
          type: "string",
          description: "Filter by loan type. Options: all, home_loan, personal, auto, education_loan, gold"
        }
      }
    )
  end

  def call(params = {})
    filter_type = params.fetch("type", "all")

    loan_accounts = family.accounts.where(accountable_type: "Loan")

    loans_data = []
    total_outstanding = 0
    total_monthly_emi = 0

    loan_accounts.each do |account|
      loan = account.accountable
      next unless loan
      next unless filter_type == "all" || loan.subtype == filter_type

      # Safely get loan values with defaults
      outstanding = loan.respond_to?(:outstanding_principal) ? (loan.outstanding_principal || 0) : account.balance.abs
      emi = loan.respond_to?(:emi_amount) ? (loan.emi_amount&.amount || 0) : 0

      loan_data = {
        name: account.name,
        lender: loan.respond_to?(:lender_name) ? (loan.lender_name || "Unknown Lender") : "Unknown Lender",
        type: loan.respond_to?(:subtype) ? loan.subtype : "loan",
        type_display: loan.respond_to?(:subtype) ? (Loan::SUBTYPES.dig(loan.subtype, :long) || loan.subtype) : "Loan",
        
        # Amounts
        principal_amount: loan.respond_to?(:principal_amount) ? loan.principal_amount : nil,
        outstanding_principal: outstanding,
        outstanding_formatted: Money.new(outstanding, account.currency).format,
        
        # EMI details
        emi_amount: emi,
        emi_formatted: Money.new(emi, account.currency).format,
        emi_day: loan.respond_to?(:emi_day) ? loan.emi_day : nil,
        next_emi_date: loan.respond_to?(:next_emi_date) ? loan.next_emi_date&.to_s : nil,
        days_until_next_emi: loan.respond_to?(:days_until_next_emi) ? loan.days_until_next_emi : nil,
        
        # Loan terms
        interest_rate: loan.respond_to?(:interest_rate) ? loan.interest_rate : nil,
        rate_type: loan.respond_to?(:rate_type) ? loan.rate_type : nil,
        tenure_months: loan.respond_to?(:term_months) ? loan.term_months : nil,
        remaining_months: loan.respond_to?(:remaining_months) ? loan.remaining_months : nil,
        
        # Payment history
        principal_paid: loan.respond_to?(:principal_paid_to_date) ? loan.principal_paid_to_date : nil,
        interest_paid: loan.respond_to?(:interest_paid_to_date) ? loan.interest_paid_to_date : nil,
        
        # Tax benefits (if applicable)
        tax_benefits: loan.respond_to?(:tax_benefits_this_year) ? loan.tax_benefits_this_year : nil,
        
        currency: account.currency
      }

      loans_data << loan_data
      total_outstanding += outstanding
      total_monthly_emi += emi
    end

    {
      as_of_date: Date.current,
      summary: {
        headline: "You have #{loans_data.size} loan(s) with total outstanding of #{Money.new(total_outstanding, family.currency).format}",
        monthly_emi_burden: "Total monthly EMI: #{Money.new(total_monthly_emi, family.currency).format}"
      },
      total_loans: loans_data.size,
      total_outstanding: total_outstanding,
      total_outstanding_formatted: Money.new(total_outstanding, family.currency).format,
      total_monthly_emi: total_monthly_emi,
      total_monthly_emi_formatted: Money.new(total_monthly_emi, family.currency).format,
      currency: family.currency,
      loans: loans_data
    }
  end
end
