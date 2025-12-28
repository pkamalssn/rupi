class CreateCategoryRules < ActiveRecord::Migration[7.2]
  def change
    create_table :category_rules, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :category, null: false, foreign_key: true, type: :uuid
      t.references :account, foreign_key: true, type: :uuid  # For account-specific rules
      
      # Core matching
      t.string :pattern, null: false
      t.string :pattern_hash                                  # MD5 hash for fast exact lookup
      t.string :match_type, default: "contains", null: false  # exact, starts_with, ends_with, contains, regex, regex_anchored
      t.string :scope, default: "narration", null: false      # global, narration, merchant, account_specific
      
      # Source and trust
      t.string :source, default: "auto", null: false          # manual, system, ai, auto
      t.string :status, default: "candidate", null: false     # candidate, active, inactive, quarantined
      t.boolean :probationary, default: true, null: false     # Still in probation period?
      
      # Confidence and scoring
      t.float :confidence, default: 0.65, null: false
      t.integer :priority, default: 0, null: false            # Calculated priority score
      t.boolean :user_confirmed, default: false, null: false
      
      # Stats for self-healing
      t.integer :times_matched, default: 0, null: false
      t.integer :times_overridden, default: 0, null: false
      t.datetime :last_overridden_at                          # For cooldown logic
      
      # Quarantine (for debugging failed rules)
      t.string :quarantine_reason
      t.datetime :quarantined_at
      
      # Metadata
      t.string :merchant_name

      t.timestamps
    end
    
    # Unique pattern per family + scope
    add_index :category_rules, [:family_id, :pattern, :scope], unique: true
    
    # Fast hash-based exact lookup
    add_index :category_rules, [:family_id, :pattern_hash]
    
    # Fast lookups for active rules by priority
    add_index :category_rules, [:family_id, :status, :priority], order: { priority: :desc }
    
    # Find rules by category (for rule management UI)
    add_index :category_rules, [:family_id, :category_id]
    
    # Account-specific rule lookup
    add_index :category_rules, [:family_id, :account_id]
    
    # Scope-based queries
    add_index :category_rules, [:family_id, :scope, :status]
  end
end
