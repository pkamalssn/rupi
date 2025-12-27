class Category < ApplicationRecord
  has_many :transactions, dependent: :nullify, class_name: "Transaction"
  has_many :import_mappings, as: :mappable, dependent: :destroy, class_name: "Import::Mapping"

  belongs_to :family

  has_many :budget_categories, dependent: :destroy
  has_many :subcategories, class_name: "Category", foreign_key: :parent_id, dependent: :nullify
  belongs_to :parent, class_name: "Category", optional: true

  validates :name, :color, :lucide_icon, :family, presence: true
  validates :name, uniqueness: { scope: :family_id }

  validate :category_level_limit
  validate :nested_category_matches_parent_classification

  before_save :inherit_color_from_parent

  scope :alphabetically, -> { order(:name) }
  scope :alphabetically_by_hierarchy, -> {
    left_joins(:parent)
      .order(Arel.sql("COALESCE(parents_categories.name, categories.name)"))
      .order(Arel.sql("parents_categories.name IS NOT NULL"))
      .order(:name)
  }
  scope :roots, -> { where(parent_id: nil) }
  scope :incomes, -> { where(classification: "income") }
  scope :expenses, -> { where(classification: "expense") }

  COLORS = %w[#eab308 #22c55e #14b8a6 #06b6d4 #f59e0b #10b981 #0ea5e9 #84cc16 #f97316 #ef4444]

  UNCATEGORIZED_COLOR = "#737373"
  TRANSFER_COLOR = "#0ea5e9" # Cyan-500
  PAYMENT_COLOR = "#ef4444"  # Red-500
  TRADE_COLOR = "#eab308"    # Gold-500

  class Group
    attr_reader :category, :subcategories

    delegate :name, :color, to: :category

    def self.for(categories)
      categories.select { |category| category.parent_id.nil? }.map do |category|
        new(category, category.subcategories)
      end
    end

    def initialize(category, subcategories = nil)
      @category = category
      @subcategories = subcategories || []
    end
  end

  class << self
    def icon_codes
      %w[
        ambulance apple award baby badge-dollar-sign banknote barcode bar-chart-3
        bath battery bed-single beer bike bluetooth bone book-open briefcase building
        bus cake calculator calendar-range camera car cat circle-dollar-sign coffee
        coins compass cookie cooking-pot credit-card dices dog drama drill droplet
        drum dumbbell film flame flower fuel gamepad-2 gift glasses globe graduation-cap
        hammer hand-helping headphones heart heart-pulse home ice-cream-cone key
        landmark laptop leaf lightbulb chart-line luggage mail map-pin mic monitor moon
        music package palette paw-print pencil percent phone pie-chart piggy-bank pill
        pizza plane plug power printer puzzle receipt receipt-text ribbon scale scissors
        settings shield shirt shopping-bag shopping-cart smartphone sparkles sprout
        stethoscope store sun tag target tent thermometer ticket train trees trophy truck
        tv umbrella users utensils video wallet wallet-cards waves wifi wine wrench zap
      ]
    end

    def bootstrap!
      default_categories.each do |name, color, icon, classification|
        find_or_create_by!(name: name) do |category|
          category.color = color
          category.classification = classification
          category.lucide_icon = icon
        end
      end
    end

    def uncategorized
      new(
        name: "Uncategorized",
        color: UNCATEGORIZED_COLOR,
        lucide_icon: "circle-dashed"
      )
    end

    private
      def default_categories
        [
          # Income Categories
          [ "Salary", "#16a34a", "wallet", "income" ],                     # Green-600
          [ "Freelance", "#22c55e", "laptop", "income" ],                  # Green-500
          [ "Investment Returns", "#15803d", "trending-up", "income" ],   # Green-700
          [ "Other Income", "#10b981", "circle-dollar-sign", "income" ],  # Emerald-500
          
          # Expense Categories - Food & Daily
          [ "Food & Dining", "#ca8a04", "utensils", "expense" ],          # Yellow-600
          [ "Groceries", "#65a30d", "shopping-bag", "expense" ],          # Lime-600
          [ "Shopping", "#0d9488", "shopping-cart", "expense" ],          # Teal-600
          
          # Transport & Travel
          [ "Transportation", "#0284c7", "bus", "expense" ],              # Sky-600
          [ "Fuel & Petrol", "#0891b2", "fuel", "expense" ],              # Cyan-600
          [ "Travel", "#0e7490", "plane", "expense" ],                    # Cyan-700
          
          # Lifestyle
          [ "Entertainment", "#d97706", "drama", "expense" ],             # Amber-600
          [ "Healthcare", "#059669", "pill", "expense" ],                 # Emerald-600
          [ "Personal Care", "#14b8a6", "scissors", "expense" ],          # Teal-500
          [ "Education", "#6366f1", "graduation-cap", "expense" ],        # Indigo-500
          [ "Sports & Fitness", "#15803d", "dumbbell", "expense" ],       # Green-700
          
          # Home & Utilities
          [ "Rent / Maintenance", "#92400e", "home", "expense" ],         # Amber-800
          [ "Utilities & Bills", "#a16207", "lightbulb", "expense" ],     # Yellow-700
          [ "Domestic Help", "#78716c", "users", "expense" ],             # Stone-500
          [ "Home Improvement", "#b45309", "hammer", "expense" ],         # Amber-700
          
          # Financial
          [ "EMI Payments", "#2563eb", "credit-card", "expense" ],        # Blue-600
          [ "Loan Payments", "#1d4ed8", "landmark", "expense" ],          # Blue-700
          [ "Insurance", "#0369a1", "shield", "expense" ],                # Sky-700
          [ "Taxes", "#dc2626", "receipt-text", "expense" ],              # Red-600
          [ "Bank Fees", "#4b5563", "receipt", "expense" ],               # Gray-600
          
          # Subscriptions & Services
          [ "Subscriptions", "#115e59", "wifi", "expense" ],              # Teal-800
          [ "Services", "#0e7490", "briefcase", "expense" ],              # Cyan-700
          [ "Recharges", "#8b5cf6", "smartphone", "expense" ],            # Violet-500
          
          # Transfers & Investments
          [ "Transfers", "#0ea5e9", "arrow-right-left", "expense" ],      # Sky-500
          [ "Investments", "#047857", "piggy-bank", "expense" ],          # Emerald-700
          [ "Gifts & Donations", "#06b6d4", "hand-helping", "expense" ]  # Cyan-500
        ]
      end
  end

  def inherit_color_from_parent
    if subcategory?
      self.color = parent.color
    end
  end

  def replace_and_destroy!(replacement)
    transaction do
      transactions.update_all category_id: replacement&.id
      destroy!
    end
  end

  def parent?
    subcategories.any?
  end

  def subcategory?
    parent.present?
  end

  def name_with_parent
    subcategory? ? "#{parent.name} > #{name}" : name
  end

  private
    def category_level_limit
      if (subcategory? && parent.subcategory?) || (parent? && subcategory?)
        errors.add(:parent, "can't have more than 2 levels of subcategories")
      end
    end

    def nested_category_matches_parent_classification
      if subcategory? && parent.classification != classification
        errors.add(:parent, "must have the same classification as its parent")
      end
    end

    def monetizable_currency
      family.currency
    end
end
