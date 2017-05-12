require 'rollbar/scrubbers/params'

module Rollbar
  class Sidekiq
    PARAM_BLACKLIST = %w[backtrace error_backtrace error_message error_class]

    class ClearScope
      def call(worker, msg, queue)
        Rollbar.reset_notifier!

        yield
      end
    end

    def self.handle_exception(ctx_hash, e)
      job_hash = ctx_hash[:job] || ctx_hash
      return if skip_report?(job_hash, e)

      params = job_hash.reject{ |k| PARAM_BLACKLIST.include?(k) }
      scrubbed_params = scrub_params(params)
      scope = {
        :request => { :params => scrubbed_params },
        :framework => "Sidekiq: #{::Sidekiq::VERSION}"
      }
      if params.is_a?(Hash)
        scope[:context] = params['class']
        scope[:queue] = params['queue']
      end

      Rollbar.scope(scope).error(e, :use_exception_level_filters => true)
    end

    def self.scrub_params(params)
      options = {
        :params => params,
        :config => Rollbar.configuration.scrub_fields
      }

      Rollbar::Scrubbers::Params.call(options)
    end

    def self.skip_report?(job_hash, e)
      job_hash["retry"] && job_hash["retry_count"] &&
        job_hash["retry_count"] < ::Rollbar.configuration.sidekiq_threshold
    end

    def call(worker, msg, queue)
      Rollbar.reset_notifier!

      yield
    rescue Exception => e
      Rollbar::Sidekiq.handle_exception(msg, e)
      raise
    end
  end
end
