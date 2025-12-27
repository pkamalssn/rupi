# frozen_string_literal: true

class Assistant::Function::CalculatePrepayment < Assistant::Function
  class << self
    def name
      "calculate_prepayment"
    end

    def description
      "Calculate the impact of making a prepayment on a loan - shows savings on interest and tenure reduction options"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: ["prepayment_amount"],
      properties: {
        loan_name: {
          type: "string",
          description: "Name of the loan to analyze"
        },
        prepayment_amount: {
          type: "number",
          description: "Amount to prepay in INR"
        }
      }
    )
  end

  def call(params = {})
    prepayment_amount = params["prepayment_amount"].to_f
    loan_name_filter = params["loan_name"]

    return { error: "Prepayment amount must be positive" } if prepayment_amount <= 0

    loan_accounts = family.accounts.where(accountable_type: "Loan")
    
    if loan_name_filter.present?
      loan_accounts = loan_accounts.where("accounts.name ILIKE ?", "%#{loan_name_filter}%")
    end

    return { error: "No matching loans found" } if loan_accounts.empty?

    results = []

    loan_accounts.each do |account|
      loan = account.accountable
      next unless loan
      
      outstanding = loan.respond_to?(:outstanding_principal) ? (loan.outstanding_principal || 0) : account.balance.abs
      next unless outstanding > 0
      next unless loan.respond_to?(:prepayment_impact)

      impact = loan.prepayment_impact(prepayment_amount)
      next if impact.nil? || impact.empty?

      results << {
        loan_name: account.name,
        loan_type: loan.respond_to?(:subtype) ? (Loan::SUBTYPES.dig(loan.subtype, :long) || loan.subtype) : "Loan",
        lender: loan.respond_to?(:lender_name) ? loan.lender_name : nil,
        currency: account.currency,
        
        current_status: {
          outstanding: impact[:current_outstanding],
          outstanding_formatted: Money.new(impact[:current_outstanding], account.currency).format,
          remaining_months: loan.remaining_months,
          current_emi: loan.emi_amount&.amount,
          current_emi_formatted: loan.emi_amount&.format
        },

        prepayment: {
          amount: prepayment_amount,
          formatted: Money.new(prepayment_amount, account.currency).format,
          new_outstanding: impact[:new_outstanding],
          new_outstanding_formatted: Money.new(impact[:new_outstanding], account.currency).format
        },

        option_1_reduce_tenure: {
          description: "Keep same EMI, reduce tenure",
          new_tenure_months: impact[:option_reduce_tenure][:new_tenure_months],
          months_saved: impact[:option_reduce_tenure][:months_saved],
          years_saved: (impact[:option_reduce_tenure][:months_saved] / 12.0).round(1),
          interest_saved: impact[:option_reduce_tenure][:interest_saved],
          interest_saved_formatted: Money.new(impact[:option_reduce_tenure][:interest_saved], account.currency).format,
          recommendation: impact[:option_reduce_tenure][:interest_saved] > impact[:option_reduce_emi][:interest_saved] ? "Recommended" : nil
        },

        option_2_reduce_emi: {
          description: "Keep same tenure, reduce EMI",
          new_emi: impact[:option_reduce_emi][:new_emi],
          new_emi_formatted: Money.new(impact[:option_reduce_emi][:new_emi], account.currency).format,
          emi_reduction: impact[:option_reduce_emi][:emi_reduction],
          emi_reduction_formatted: Money.new(impact[:option_reduce_emi][:emi_reduction], account.currency).format,
          interest_saved: impact[:option_reduce_emi][:interest_saved],
          interest_saved_formatted: Money.new(impact[:option_reduce_emi][:interest_saved], account.currency).format,
          recommendation: impact[:option_reduce_emi][:interest_saved] >= impact[:option_reduce_tenure][:interest_saved] ? "Better for cash flow" : nil
        }
      }
    end

    return { error: "No loans with outstanding principal found" } if results.empty?

    {
      analysis_date: Date.current.to_s,
      prepayment_amount: prepayment_amount,
      prepayment_formatted: Money.new(prepayment_amount, family.currency).format,
      loans_analyzed: results.size,
      results: results,
      advice: generate_advice(results, prepayment_amount)
    }
  end

  private

  def generate_advice(results, prepayment_amount)
    best_option = results.max_by { |r| r[:option_1_reduce_tenure][:interest_saved] }
    
    if best_option
      interest_saved = best_option[:option_1_reduce_tenure][:interest_saved]
      months_saved = best_option[:option_1_reduce_tenure][:months_saved]
      
      "For maximum benefit, prepay ₹#{prepayment_amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} " \
      "on your #{best_option[:loan_name]}. This could save you " \
      "₹#{interest_saved.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} in interest " \
      "and reduce your loan tenure by #{months_saved} months."
    end
  end
end
