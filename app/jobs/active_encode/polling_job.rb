module ActiveEncode
  class PollingJob < ActiveJob::Base

    def perform(encode)
      encode.run_callbacks(:status_update) { encode }
      case encode.state
      when :error
        encode.run_callbacks(:error) { encode }
      when :cancelled
        encode.run_callbacks(:cancelled) { encode }
      when :complete
        encode.run_callbacks(:complete) { encode }
      when :running
        ActiveEncode::PollingJob.set(wait: ActiveEncode::Polling::POLLING_WAIT_TIME).perform_later(encode)
      else # other states are illegal and ignored
        raise StandardError, "Illegal state #{encode.state} in encode #{encode.id}!"
      end
    end
  end
end
