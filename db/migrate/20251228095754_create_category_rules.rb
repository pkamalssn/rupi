class CreateCategoryRules < ActiveRecord::Migration[7.2]
  def change
    create_table :category_rules, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :category, null: false, foreign_key: true, type: :uuid
      
      # Core matching
      t.string :pattern, null: false
      t.string :match_type, default: "contains", null: false  # exact, starts_with, ends_with, contains, regex
      
      # Source and trust
      t.string :source, default: "auto", null: false          # manual, system, ai, auto
      t.string :status, default: "candidate", null: false     # candidate, active, inactive
      
      # Confidence and scoring
      t.float :confidence, default: 0.65, null: false
      t.integer :priority, default: 0, null: false            # Calculated priority score
      t.boolean :user_confirmed, default: false, null: false
      
      # Stats for self-healing
      t.integer :times_matched, default: 0, null: false
      t.integer :times_overridden, default: 0, null: false
      
      # Metadata
      t.string :merchant_name

      t.timestamps
    end
    
    # Unique pattern per family
    add_index :category_rules, [:family_id, :pattern], unique: true
    
    # Fast lookups for active rules by priority
    add_index :category_rules, [:family_id, :status, :priority], order: { priority: :desc }
    
    # Find rules by category (for rule management UI)
    add_index :category_rules, [:family_id, :category_id]
  end
end
