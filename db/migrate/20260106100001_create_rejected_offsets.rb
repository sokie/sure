class CreateRejectedOffsets < ActiveRecord::Migration[7.2]
  def change
    create_table :rejected_offsets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :expense_transaction, type: :uuid, null: false, foreign_key: { to_table: :transactions, on_delete: :cascade }
      t.references :offset_transaction, type: :uuid, null: false, foreign_key: { to_table: :transactions, on_delete: :cascade }

      t.timestamps
    end

    add_index :rejected_offsets, [ :expense_transaction_id, :offset_transaction_id ], unique: true, name: "idx_rejected_offsets_unique"
  end
end
