# frozen_string_literal: true
require 'spec_helper'
require 'aws-sdk-cloudwatchevents'
require 'aws-sdk-cloudwatchlogs'
require 'aws-sdk-mediaconvert'
require 'aws-sdk-s3'
require 'json'
require 'active_encode/spec/shared_specs'
require 'active_support/json'
require 'active_support/time'

def reconstitute_response(fixture_path)
  HashWithIndifferentAccess.new(ActiveSupport::JSON.decode(File.read(File.join("spec/fixtures", fixture_path))))
end

describe ActiveEncode::EngineAdapters::MediaConvertAdapter do
  around do |example|
    ActiveSupport.parse_json_times = true
    Time.zone = 'America/Chicago'

    # Setting this before each test works around a stubbing + memoization limitation
    ActiveEncode::Base.engine_adapter = :media_convert
    ActiveEncode::Base.engine_adapter.role = 'arn:aws:iam::123456789012:role/service-role/MediaConvert_Default_Role'
    ActiveEncode::Base.engine_adapter.output_bucket = 'output-bucket'
    example.run
    ActiveEncode::Base.engine_adapter = :test
  end

  let(:job_id) { "1625859001514-vvqfwj" }
  let(:mediaconvert) { Aws::MediaConvert::Client.new(stub_responses: true) }
  let(:cloudwatch_events) { Aws::CloudWatchEvents::Client.new(stub_responses: true) }
  let(:cloudwatch_logs) { Aws::CloudWatchLogs::Client.new(stub_responses: true) }

  before do
    mediaconvert.stub_responses(:describe_endpoints, reconstitute_response("media_convert/endpoints.json"))

    allow(Aws::MediaConvert::Client).to receive(:new).and_return(mediaconvert)
    allow(Aws::CloudWatchEvents::Client).to receive(:new).and_return(cloudwatch_events)
    allow(Aws::CloudWatchLogs::Client).to receive(:new).and_return(cloudwatch_logs)
  end

  let(:created_job) do
    mediaconvert.stub_responses(:create_job, reconstitute_response("media_convert/job_created.json"))

    ActiveEncode::Base.create(
      "s3://input-bucket/test_files/source_file.mp4",
      output_prefix: "active-encode-test/output",
      outputs: [
        { preset: "System-Avc_16x9_1080p_29_97fps_8500kbps", modifier: "-1080" },
        { preset: "System-Avc_16x9_720p_29_97fps_5000kbps", modifier: "-720" },
        { preset: "System-Avc_16x9_540p_29_97fps_3500kbps", modifier: "-540" }
      ],
      use_original_url: true
    )
  end

  let(:running_job) do
    mediaconvert.stub_responses(:get_job, reconstitute_response("media_convert/job_progressing.json"))
    ActiveEncode::Base.find(job_id)
  end

  let(:canceled_job) do
    mediaconvert.stub_responses(:get_job, reconstitute_response("media_convert/job_canceled.json"))
    ActiveEncode::Base.find(job_id)
  end

  let(:cancelling_job) do
    mediaconvert.stub_responses(:get_job, reconstitute_response("media_convert/job_canceled.json"))
    ActiveEncode::Base.find(job_id)
  end

  let(:completed_job) do
    mediaconvert.stub_responses(:get_job, reconstitute_response("media_convert/job_completed.json"))
    cloudwatch_logs.stub_responses(:start_query, reconstitute_response("media_convert/job_completed_detail_query.json"))
    cloudwatch_logs.stub_responses(:get_query_results, reconstitute_response("media_convert/job_completed_detail.json"))

    ActiveEncode::Base.find(job_id)
  end

  let(:failed_job) do
    mediaconvert.stub_responses(:get_job, reconstitute_response("media_convert/job_failed.json"))

    ActiveEncode::Base.find(job_id)
  end

  let(:completed_output) do
    [
      { id: "1625859001514-vvqfwj-output-0", url: "s3://output-bucket/active-encode-test/output-1080.m3u8",
        label: "output-1080.m3u8", audio_bitrate: 128_000, audio_codec: "AAC", duration: 888_020,
        video_bitrate: 8_500_000, height: 1080, width: 1920, video_codec: "H_264", frame_rate: 29.97 },
      { id: "1625859001514-vvqfwj-output-1", url: "s3://output-bucket/active-encode-test/output-720.m3u8",
        label: "output-720.m3u8", audio_bitrate: 96_000, audio_codec: "AAC", duration: 888_020,
        video_bitrate: 5_000_000, height: 720, width: 1280, video_codec: "H_264", frame_rate: 29.97 },
      { id: "1625859001514-vvqfwj-output-2", url: "s3://output-bucket/active-encode-test/output-540.m3u8",
        label: "output-540.m3u8", audio_bitrate: 96_000, audio_codec: "AAC", duration: 888_020,
        video_bitrate: 3_500_000, height: 540, width: 960, video_codec: "H_264", frame_rate: 29.97 }
    ]
  end
  let(:completed_tech_metadata) { {} }
  let(:failed_tech_metadata) { {} }

  it_behaves_like "an ActiveEncode::EngineAdapter"
end
