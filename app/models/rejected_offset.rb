class RejectedOffset < ApplicationRecord
  belongs_to :expense_transaction, class_name: "Transaction"
  belongs_to :offset_transaction, class_name: "Transaction"
end
