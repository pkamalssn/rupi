# frozen_string_literal: true

# Tracks individual EMI payments for a loan
class EmiPayment < ApplicationRecord
  belongs_to :loan
  belongs_to :entry, optional: true  # Links to actual transaction when detected

  # Status: pending -> paid | overdue | prepayment
  enum :status, {
    pending: "pending",
    paid: "paid",
    overdue: "overdue",
    prepayment: "prepayment"
  }, default: :pending

  validates :due_date, presence: true
  validates :emi_amount, numericality: { greater_than: 0 }, allow_nil: true

  scope :upcoming, -> { where(status: :pending).where("due_date >= ?", Date.current).order(:due_date) }
  scope :overdue, -> { where(status: :pending).where("due_date < ?", Date.current) }
  scope :paid_this_month, -> { where(status: :paid).where(paid_date: Date.current.beginning_of_month..Date.current.end_of_month) }
  scope :this_fiscal_year, -> {
    fy_start = Date.current.month >= 4 ? Date.new(Date.current.year, 4, 1) : Date.new(Date.current.year - 1, 4, 1)
    where(paid_date: fy_start..(fy_start + 1.year - 1.day))
  }

  before_save :calculate_components, if: -> { emi_amount.present? && principal_component.nil? }

  def mark_paid!(paid_date: Date.current, entry: nil)
    update!(
      status: :paid,
      paid_date: paid_date,
      entry: entry
    )
  end

  def mark_as_prepayment!
    update!(status: :prepayment)
  end

  def overdue?
    pending? && due_date < Date.current
  end

  def days_overdue
    return 0 unless overdue?
    (Date.current - due_date).to_i
  end

  def days_until_due
    return nil unless pending?
    (due_date - Date.current).to_i
  end

  private

  def calculate_components
    return unless loan.present? && loan.interest_rate.present?

    # Get outstanding principal at time of this EMI
    previous_payments = loan.emi_payments.where("due_date < ?", due_date)
    outstanding = loan.principal_amount - previous_payments.sum(:principal_component)

    monthly_rate = loan.interest_rate / 100.0 / 12.0
    
    self.interest_component = (outstanding * monthly_rate).round(2)
    self.principal_component = (emi_amount - interest_component).round(2)
  end
end
