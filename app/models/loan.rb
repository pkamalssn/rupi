# frozen_string_literal: true

class Loan < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "mortgage" => { short: "Mortgage", long: "Mortgage" },
    "home_loan" => { short: "Home Loan", long: "Home Loan (India)" },
    "student" => { short: "Student", long: "Student Loan" },
    "education_loan" => { short: "Education", long: "Education Loan (India)" },
    "auto" => { short: "Auto", long: "Auto Loan" },
    "car_loan" => { short: "Car", long: "Car Loan (India)" },
    "personal" => { short: "Personal", long: "Personal Loan" },
    "gold" => { short: "Gold", long: "Gold Loan (India)" },
    "business" => { short: "Business", long: "Business Loan" },
    "lap" => { short: "LAP", long: "Loan Against Property" },
    "two_wheeler" => { short: "Two Wheeler", long: "Two Wheeler Loan" },
    "consumer_durable" => { short: "Consumer", long: "Consumer Durable Loan" },
    "other" => { short: "Other", long: "Other Loan" }
  }.freeze

  # Enhanced loan tracking fields (set via migration)
  # - emi_day: Day of month when EMI is debited (1-28)
  # - lender_name: Bank/NBFC name
  # - loan_account_number: Loan account number (ENCRYPTED)
  # - disbursement_date: When loan was disbursed
  # - tenure_months: Original loan tenure
  # - interest_rate: Annual interest rate
  # - rate_type: fixed or floating

  # Encrypt sensitive financial data
  encrypts :loan_account_number, deterministic: true

  has_many :emi_payments, dependent: :destroy

  # Return the EMI amount - uses actual_emi from document import if available,
  # otherwise calculates using the standard formula
  def monthly_payment
    # Prefer actual EMI from imported documents
    if actual_emi.present? && actual_emi > 0
      return Money.new(actual_emi, account.currency)
    end
    
    # Fall back to calculated EMI
    calculated_emi
  end
  
  # Calculate EMI using standard formula
  # EMI = P × r × (1+r)^n / ((1+r)^n - 1)
  def calculated_emi
    return nil if term_months.nil? || interest_rate.nil?
    return Money.new(0, account.currency) if original_balance.amount.zero? || term_months.zero?

    annual_rate = interest_rate / 100.0
    monthly_rate = annual_rate / 12.0

    if monthly_rate.zero?
      payment = original_balance.amount / term_months
    else
      payment = (original_balance.amount * monthly_rate * (1 + monthly_rate)**term_months) / ((1 + monthly_rate)**term_months - 1)
    end

    Money.new(payment.round, account.currency)
  end

  alias_method :emi_amount, :monthly_payment

  def original_balance
    Money.new(account.first_valuation_amount, account.currency)
  end

  def principal_amount
    original_balance.amount
  end

  # Calculate outstanding principal
  def outstanding_principal
    return principal_amount unless emi_payments.any?
    
    paid_principal = emi_payments.sum(:principal_component)
    principal_amount - paid_principal
  end

  def outstanding_balance
    Money.new(outstanding_principal, account.currency)
  end

  # Calculate total interest paid
  def interest_paid_to_date
    emi_payments.sum(:interest_component)
  end

  # Calculate total principal paid
  def principal_paid_to_date
    emi_payments.sum(:principal_component)
  end

  # Remaining tenure in months
  def remaining_months
    return term_months unless emi_payments.any?
    [term_months - emi_payments.count, 0].max
  end

  # Months elapsed
  def months_elapsed
    emi_payments.count
  end

  # Generate amortization schedule
  def amortization_schedule
    return [] if term_months.nil? || interest_rate.nil? || principal_amount.zero?

    monthly_rate = interest_rate / 100.0 / 12.0
    emi = emi_amount&.amount || 0
    balance = principal_amount
    schedule = []

    (1..term_months).each do |month|
      interest = (balance * monthly_rate).round(2)
      principal = (emi - interest).round(2)
      balance = [balance - principal, 0].max.round(2)

      schedule << {
        month: month,
        emi: emi,
        principal: principal,
        interest: interest,
        balance: balance,
        date: disbursement_date ? disbursement_date + month.months : nil
      }

      break if balance <= 0
    end

    schedule
  end

  # Get upcoming EMI dates
  def upcoming_emi_dates(count = 3)
    return [] unless emi_day.present?

    dates = []
    current_date = Date.current

    count.times do |i|
      # Calculate next EMI date
      emi_date = Date.new(current_date.year, current_date.month, [emi_day, 28].min)
      
      # If we've passed this month's EMI, move to next month
      emi_date = emi_date + (i + (current_date.day >= emi_day ? 1 : 0)).months
      
      dates << emi_date
    end

    dates
  end

  # Next EMI date
  def next_emi_date
    upcoming_emi_dates(1).first
  end

  # Days until next EMI
  def days_until_next_emi
    return nil unless next_emi_date
    (next_emi_date - Date.current).to_i
  end

  # Calculate prepayment impact
  def prepayment_impact(prepayment_amount)
    return {} unless principal_amount > 0 && interest_rate > 0

    current_outstanding = outstanding_principal
    new_outstanding = [current_outstanding - prepayment_amount, 0].max
    
    monthly_rate = interest_rate / 100.0 / 12.0
    emi = emi_amount&.amount || 0

    # Option 1: Reduce tenure (same EMI)
    if emi > 0 && monthly_rate > 0
      new_tenure_formula = -Math.log(1 - (new_outstanding * monthly_rate / emi)) / Math.log(1 + monthly_rate)
      new_tenure = new_tenure_formula.finite? ? new_tenure_formula.ceil : remaining_months
    else
      new_tenure = remaining_months
    end

    original_total_payment = emi * remaining_months
    new_total_payment = emi * new_tenure
    interest_saved_tenure = original_total_payment - new_total_payment - prepayment_amount

    # Option 2: Reduce EMI (same tenure)
    if remaining_months > 0 && monthly_rate > 0
      new_emi = (new_outstanding * monthly_rate * (1 + monthly_rate)**remaining_months) / 
                ((1 + monthly_rate)**remaining_months - 1)
    else
      new_emi = 0
    end

    new_total_payment_emi = new_emi * remaining_months
    interest_saved_emi = original_total_payment - new_total_payment_emi - prepayment_amount

    {
      prepayment_amount: prepayment_amount,
      current_outstanding: current_outstanding,
      new_outstanding: new_outstanding,
      option_reduce_tenure: {
        new_tenure_months: new_tenure,
        months_saved: remaining_months - new_tenure,
        interest_saved: interest_saved_tenure.round(2)
      },
      option_reduce_emi: {
        new_emi: new_emi.round(2),
        emi_reduction: (emi - new_emi).round(2),
        interest_saved: interest_saved_emi.round(2)
      }
    }
  end

  # Tax benefits under Section 80C (principal) and Section 24 (interest)
  def tax_benefits_this_year
    fiscal_year_start = Date.current.month >= 4 ? Date.new(Date.current.year, 4, 1) : Date.new(Date.current.year - 1, 4, 1)
    fiscal_year_end = fiscal_year_start + 1.year - 1.day

    payments_this_year = emi_payments.where(paid_date: fiscal_year_start..fiscal_year_end)
    
    principal_paid = payments_this_year.sum(:principal_component)
    interest_paid = payments_this_year.sum(:interest_component)

    # Section 80C limit for home loan principal: ₹1,50,000
    # Section 24 limit for home loan interest: ₹2,00,000 (self-occupied)
    {
      principal_paid: principal_paid,
      interest_paid: interest_paid,
      section_80c_eligible: [principal_paid, 150000].min,  # Home loan only
      section_24_eligible: [interest_paid, 200000].min,    # Self-occupied property
      section_80e_eligible: subtype == "education_loan" ? interest_paid : 0  # Full interest for education loan
    }
  end

  class << self
    def color
      "#2563eb"
    end

    def icon
      "hand-coins"
    end

    def classification
      "liability"
    end
  end
end
