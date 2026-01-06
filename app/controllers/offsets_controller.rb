class OffsetsController < ApplicationController
  include StreamExtensions

  before_action :set_offset, only: %i[show destroy update]

  def show
  end

  def update
    Offset.transaction do
      update_offset_status
      @offset.update!(notes: offset_update_params[:notes]) if offset_update_params[:notes].present?
    end

    @offset.sync_account_later

    respond_to do |format|
      format.html { redirect_back_or_to transactions_url, notice: t(".success") }
      format.turbo_stream
    end
  end

  def destroy
    @offset.destroy!
    @offset.sync_account_later
    redirect_back_or_to transactions_url, notice: t(".success")
  end

  private

    def set_offset
      # Finds the offset and ensures the family owns it
      @offset = Offset
                  .where(id: params[:id])
                  .where(expense_transaction_id: Current.family.transactions.select(:id))
                  .first!
    end

    def offset_update_params
      params.require(:offset).permit(:notes, :status)
    end

    def update_offset_status
      if offset_update_params[:status] == "rejected"
        @offset.reject!
      elsif offset_update_params[:status] == "confirmed"
        @offset.confirm!
      end
    end
end
