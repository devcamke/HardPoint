# Browser features HardPoint pages may use. The camera is for photographing signed delivery notes
# (through a file input); nothing uses the microphone, location, USB or payment request APIs.
Rails.application.config.permissions_policy do |policy|
  policy.camera      :self
  policy.microphone  :none
  policy.geolocation :none
  policy.usb         :none
  policy.payment     :none
  policy.gyroscope   :none
  policy.accelerometer :none
  policy.magnetometer :none
  policy.fullscreen :self
end
