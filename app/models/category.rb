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
          # ==========================================
          # INCOME CATEGORIES (8)
          # ==========================================
          [ "Salary", "#16a34a", "wallet", "income" ],                     # Green-600
          [ "Freelance Income", "#22c55e", "laptop", "income" ],           # Green-500
          [ "Business Income", "#15803d", "briefcase", "income" ],         # Green-700
          [ "Rental Income", "#10b981", "home", "income" ],                # Emerald-500
          [ "Investment Returns", "#047857", "trending-up", "income" ],    # Emerald-700
          [ "Dividends", "#059669", "piggy-bank", "income" ],              # Emerald-600
          [ "Interest Income", "#065f46", "landmark", "income" ],          # Emerald-800
          [ "Other Income", "#0d9488", "circle-dollar-sign", "income" ],   # Teal-600
          
          # ==========================================
          # FOOD & DINING (Parent + Subcategories)
          # ==========================================
          [ "Food & Dining", "#ca8a04", "utensils", "expense" ],           # Yellow-600
          [ "Groceries", "#eab308", "shopping-bag", "expense" ],           # Yellow-500
          [ "Swiggy/Zomato", "#f59e0b", "smartphone", "expense" ],         # Amber-500
          [ "Restaurants", "#d97706", "utensils", "expense" ],             # Amber-600
          [ "Coffee & Cafe", "#b45309", "coffee", "expense" ],             # Amber-700
          
          # ==========================================
          # SHOPPING & RETAIL
          # ==========================================
          [ "Shopping", "#8b5cf6", "shopping-cart", "expense" ],           # Violet-500
          [ "Amazon/Flipkart", "#7c3aed", "shopping-bag", "expense" ],     # Violet-600
          [ "Clothing", "#6d28d9", "shirt", "expense" ],                   # Violet-700
          [ "Electronics", "#5b21b6", "monitor", "expense" ],              # Violet-800
          
          # ==========================================
          # TRANSPORTATION
          # ==========================================
          [ "Transportation", "#3b82f6", "bus", "expense" ],               # Blue-500
          [ "Petrol/Fuel", "#2563eb", "fuel", "expense" ],                 # Blue-600
          [ "Uber/Ola/Rapido", "#1d4ed8", "car", "expense" ],              # Blue-700
          [ "Metro/Train", "#1e40af", "train", "expense" ],                # Blue-800
          [ "Auto/Taxi", "#1e3a8a", "car", "expense" ],                    # Blue-900
          [ "Parking/Toll/FASTag", "#0284c7", "tag", "expense" ],          # Sky-600
          
          # ==========================================
          # TRAVEL & HOLIDAYS
          # ==========================================
          [ "Travel", "#0891b2", "plane", "expense" ],                     # Cyan-600
          [ "Flights", "#06b6d4", "plane", "expense" ],                    # Cyan-500
          [ "Hotels/Stays", "#0e7490", "bed-single", "expense" ],          # Cyan-700
          [ "Travel Booking", "#155e75", "compass", "expense" ],           # Cyan-800
          
          # ==========================================
          # UTILITIES & BILLS
          # ==========================================
          [ "Utilities & Bills", "#f59e0b", "lightbulb", "expense" ],      # Amber-500
          [ "Electricity", "#d97706", "zap", "expense" ],                  # Amber-600
          [ "Water Bill", "#92400e", "droplet", "expense" ],               # Amber-800
          [ "Gas/LPG", "#78350f", "flame", "expense" ],                    # Amber-900
          [ "Mobile/Internet", "#f97316", "wifi", "expense" ],             # Orange-500
          [ "DTH/Cable", "#ea580c", "tv", "expense" ],                     # Orange-600
          
          # ==========================================
          # HEALTHCARE
          # ==========================================
          [ "Healthcare", "#ec4899", "pill", "expense" ],                  # Pink-500
          [ "Medicines", "#db2777", "pill", "expense" ],                   # Pink-600
          [ "Doctor/Consultation", "#be185d", "stethoscope", "expense" ],  # Pink-700
          [ "Hospital", "#9d174d", "ambulance", "expense" ],               # Pink-800
          [ "Pharmacy", "#831843", "pill", "expense" ],                    # Pink-900
          
          # ==========================================
          # EDUCATION
          # ==========================================
          [ "Education", "#6366f1", "graduation-cap", "expense" ],         # Indigo-500
          [ "School/College Fees", "#4f46e5", "book-open", "expense" ],    # Indigo-600
          [ "Coaching/Tuition", "#4338ca", "pencil", "expense" ],          # Indigo-700
          [ "Online Courses", "#3730a3", "laptop", "expense" ],            # Indigo-800
          [ "Books & Supplies", "#312e81", "book-open", "expense" ],       # Indigo-900
          
          # ==========================================
          # ENTERTAINMENT & LIFESTYLE
          # ==========================================
          [ "Entertainment", "#f97316", "drama", "expense" ],              # Orange-500
          [ "Movies/Theatre", "#ea580c", "film", "expense" ],              # Orange-600
          [ "Concerts/Events", "#c2410c", "ticket", "expense" ],           # Orange-700
          [ "Gaming", "#9a3412", "gamepad-2", "expense" ],                 # Orange-800
          
          # ==========================================
          # SUBSCRIPTIONS & STREAMING
          # ==========================================
          [ "Subscriptions", "#14b8a6", "wifi", "expense" ],               # Teal-500
          [ "Netflix/OTT", "#0d9488", "tv", "expense" ],                   # Teal-600
          [ "Spotify/Music", "#0f766e", "music", "expense" ],              # Teal-700
          [ "YouTube/Premium", "#115e59", "video", "expense" ],            # Teal-800
          [ "Cloud Storage", "#134e4a", "cloud", "expense" ],              # Teal-900
          
          # ==========================================
          # HOUSING & HOME
          # ==========================================
          [ "Housing", "#92400e", "home", "expense" ],                     # Amber-800
          [ "Rent", "#78350f", "home", "expense" ],                        # Amber-900
          [ "Society Maintenance", "#a16207", "building", "expense" ],     # Yellow-700
          [ "Home Repairs", "#b45309", "hammer", "expense" ],              # Amber-700
          [ "Domestic Help", "#78716c", "users", "expense" ],              # Stone-500
          [ "Furniture/Appliances", "#57534e", "sofa", "expense" ],        # Stone-600
          
          # ==========================================
          # LOAN PAYMENTS & EMI
          # ==========================================
          [ "Loan Payments", "#dc2626", "landmark", "expense" ],           # Red-600
          [ "Home Loan EMI", "#b91c1c", "home", "expense" ],               # Red-700
          [ "Car/Vehicle Loan EMI", "#991b1b", "car", "expense" ],         # Red-800
          [ "Personal Loan EMI", "#7f1d1d", "credit-card", "expense" ],    # Red-900
          [ "Education Loan EMI", "#881337", "graduation-cap", "expense" ],# Rose-900
          [ "Credit Card Payment", "#e11d48", "credit-card", "expense" ],  # Rose-600
          
          # ==========================================
          # INVESTMENTS & SAVINGS
          # ==========================================
          [ "Investments & Savings", "#059669", "piggy-bank", "expense" ], # Emerald-600
          [ "Mutual Funds SIP", "#047857", "chart-line", "expense" ],      # Emerald-700
          [ "Stocks/Trading", "#065f46", "trending-up", "expense" ],       # Emerald-800
          [ "PPF/EPF", "#064e3b", "piggy-bank", "expense" ],               # Emerald-900
          [ "NPS", "#14532d", "piggy-bank", "expense" ],                   # Green-900
          [ "Fixed Deposit", "#166534", "landmark", "expense" ],           # Green-800
          [ "Recurring Deposit", "#15803d", "coins", "expense" ],          # Green-700
          [ "Gold/Digital Gold", "#a16207", "coins", "expense" ],          # Yellow-700
          [ "Crypto", "#4f46e5", "coins", "expense" ],                     # Indigo-600
          
          # ==========================================
          # INSURANCE
          # ==========================================
          [ "Insurance", "#0369a1", "shield", "expense" ],                 # Sky-700
          [ "Health Insurance", "#0284c7", "heart-pulse", "expense" ],     # Sky-600
          [ "Life Insurance (LIC)", "#0ea5e9", "shield", "expense" ],      # Sky-500
          [ "Vehicle Insurance", "#38bdf8", "car", "expense" ],            # Sky-400
          [ "Term/ULIPs", "#7dd3fc", "shield", "expense" ],                # Sky-300
          
          # ==========================================
          # TAXES & GOVT
          # ==========================================
          [ "Taxes", "#dc2626", "receipt-text", "expense" ],               # Red-600
          [ "Income Tax", "#ef4444", "receipt", "expense" ],               # Red-500
          [ "Advance Tax", "#f87171", "receipt", "expense" ],              # Red-400
          [ "GST", "#fca5a5", "receipt", "expense" ],                      # Red-300
          [ "Property Tax", "#fee2e2", "receipt", "expense" ],             # Red-100
          
          # ==========================================
          # PERSONAL CARE & FITNESS
          # ==========================================
          [ "Personal Care", "#a855f7", "scissors", "expense" ],           # Purple-500
          [ "Salon/Grooming", "#9333ea", "scissors", "expense" ],          # Purple-600
          [ "Gym/Fitness", "#7e22ce", "dumbbell", "expense" ],             # Purple-700
          [ "Sports", "#6b21a8", "trophy", "expense" ],                    # Purple-800
          
          # ==========================================
          # KIDS & FAMILY
          # ==========================================
          [ "Kids & Family", "#f472b6", "baby", "expense" ],               # Pink-400
          [ "Childcare", "#ec4899", "baby", "expense" ],                   # Pink-500
          [ "Kids Education", "#db2777", "book-open", "expense" ],         # Pink-600
          [ "Toys & Games", "#be185d", "puzzle", "expense" ],              # Pink-700
          
          # ==========================================
          # CELEBRATIONS & OCCASIONS
          # ==========================================
          [ "Celebrations", "#f59e0b", "cake", "expense" ],                # Amber-500
          [ "Wedding/Functions", "#d97706", "heart", "expense" ],          # Amber-600
          [ "Festivals/Puja", "#b45309", "sparkles", "expense" ],          # Amber-700
          [ "Gifts", "#92400e", "gift", "expense" ],                       # Amber-800
          [ "Birthday/Anniversary", "#78350f", "cake", "expense" ],        # Amber-900
          
          # ==========================================
          # DONATIONS & CHARITY
          # ==========================================
          [ "Donations & Charity", "#14b8a6", "hand-helping", "expense" ], # Teal-500
          [ "Temple/Religious", "#0d9488", "sparkles", "expense" ],        # Teal-600
          [ "NGO/Charity", "#0f766e", "heart", "expense" ],                # Teal-700
          
          # ==========================================
          # FEES & CHARGES
          # ==========================================
          [ "Fees & Charges", "#6b7280", "receipt", "expense" ],           # Gray-500
          [ "Bank Charges", "#4b5563", "landmark", "expense" ],            # Gray-600
          [ "ATM Fees", "#374151", "credit-card", "expense" ],             # Gray-700
          [ "Card AMC", "#1f2937", "credit-card", "expense" ],             # Gray-800
          [ "UPI/Transaction Fees", "#111827", "smartphone", "expense" ],  # Gray-900
          
          # ==========================================
          # TRANSFERS (Internal)
          # ==========================================
          [ "Transfers", "#0ea5e9", "arrow-right-left", "expense" ],       # Sky-500
          
          # ==========================================
          # MISCELLANEOUS
          # ==========================================
          [ "Miscellaneous", "#78716c", "dots", "expense" ],               # Stone-500
          [ "ATM Withdrawal", "#57534e", "banknote", "expense" ],          # Stone-600
          [ "Cash", "#44403c", "wallet", "expense" ]                       # Stone-700
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
