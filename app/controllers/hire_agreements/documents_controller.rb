class HireAgreements::DocumentsController < ApplicationController
  include HireAgreementScoped

  def show
    pdf = HireAgreementPdf.new(@hire_agreement)
    send_data pdf.render, filename: "#{@hire_agreement.reference}.pdf", type: :pdf, disposition: :inline
  end
end
