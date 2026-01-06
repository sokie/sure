class OffsetMatchesController < ApplicationController
  before_action :set_entry

  def new
    if @entry.amount.positive?
      # This is an expense - show potential offset candidates (refunds/cashback)
      @offset_candidates = @entry.transaction.offset_match_candidates
      @mode = :expense_to_offset
    else
      # This is a refund/income - show potential expenses to offset
      @expense_candidates = @entry.transaction.expense_match_candidates
      @mode = :offset_to_expense
    end
  end

  def create
    @offset = build_offset

    Offset.transaction do
      @offset.save!
    end

    @offset.sync_account_later

    redirect_back_or_to transactions_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => e
    flash[:alert] = e.record.errors.full_messages.join(", ")
    redirect_back_or_to transactions_path
  end

  private

    def set_entry
      @entry = Current.family.entries.find(params[:transaction_id])
    end

    def offset_match_params
      params.require(:offset_match).permit(:matched_entry_id)
    end

    def build_offset
      matched_entry = Current.family.entries.find(offset_match_params[:matched_entry_id])

      if @entry.amount.positive?
        # Current entry is expense, matched is the offset (refund)
        Offset.new(
          expense_transaction: @entry.transaction,
          offset_transaction: matched_entry.transaction,
          status: "confirmed"
        )
      else
        # Current entry is the offset (refund), matched is expense
        Offset.new(
          expense_transaction: matched_entry.transaction,
          offset_transaction: @entry.transaction,
          status: "confirmed"
        )
      end
    end
end
