class Etims::TransmitJob < ApplicationJob
  def perform(submission)
    submission.transmit
  end
end
