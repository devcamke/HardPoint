# Each device (a PC or tablet at a counter) is set to one till, remembered in a cookie, so
# cashiers don't choose it on every sale.
module TillSelection
  extend ActiveSupport::Concern

  included do
    helper_method :current_till, :current_shift
  end

  private
    def current_till
      @current_till ||= Current.account.registers.active.find_by(id: cookies.signed[:register_id])
    end

    def current_shift
      @current_shift ||= current_till&.open_shift
    end

    def remember_till(register)
      cookies.signed.permanent[:register_id] = { value: register.id, httponly: true, same_site: :lax }
    end

    def require_till_and_shift
      if current_till.nil?
        redirect_to new_pos_till_path
      elsif current_shift.nil?
        redirect_to new_shift_path
      end
    end
end
