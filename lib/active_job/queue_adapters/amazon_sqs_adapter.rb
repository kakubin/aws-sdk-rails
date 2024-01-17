# frozen_string_literal: true

require 'aws-sdk-sqs'

module ActiveJob
  module QueueAdapters
    class AmazonSqsAdapter
      def enqueue(job)
        _enqueue(job)
      end

      def enqueue_at(job, timestamp)
        delay = Params.assured_delay_seconds(timestamp)
        _enqueue(job, nil, delay_seconds: delay)
      end

      def enqueue_all(jobs)
        jobs.group_by(&:queue_name).each do |queue_name, same_queue_jobs|
          queue_url = Aws::Rails::SqsActiveJob.config.queue_url_for(queue_name)
          base_send_message_opts = { queue_url: queue_url }

          same_queue_jobs.each_slice(10) do |chunk|
            entries = chunk.map do |job|
              entry = Params.new(job, nil).entry
              entry[:delay_seconds] = Params.assured_delay_seconds(job.scheduled_at) if job.scheduled_at
              entry
            end

            send_message_opts = base_send_message_opts.deep_dup
            send_message_opts[:entries] = entries

            Aws::Rails::SqsActiveJob.config.client.send_message_batch(send_message_opts)
          end
        end
      end

      private

      def _enqueue(job, body = nil, send_message_opts = {})
        body ||= job.serialize
        params = Params.new(job, body)
        send_message_opts = send_message_opts.merge(params.entry)
        send_message_opts[:queue_url] = params.queue_url

        Aws::Rails::SqsActiveJob.config.client.send_message(send_message_opts)
      end
    end

    # create an alias to allow `:amazon` to be used as the adapter name
    # `:amazon` is the convention used for ActionMailer and ActiveStorage
    AmazonAdapter = AmazonSqsAdapter
  end
end
