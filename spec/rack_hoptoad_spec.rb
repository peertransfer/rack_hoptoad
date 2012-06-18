require File.dirname(__FILE__)+'/spec_helper'

class TestError < RuntimeError
end

class FailHopper < Toadhopper
  def post!(*)
  end
end

class ErroringHopper < Toadhopper
  def post!(*)
    Toadhopper::Response.new(500, "", ["Timeout"])
  end
end

describe 'Rack::Hoptoad' do
  let(:app)     { lambda { |env| raise TestError, 'Suffering Succotash!' } }
  let(:env)     { Rack::MockRequest.env_for("/foo?q=google", 'FOO' => 'BAR', :method => 'GET', :input => 'THE BODY') }
  let(:api_key) { ENV['MY_HOPTOAD_API_KEY'] }

  it 'allows for custom environmental variables to be excluded from hoptoad' do
    notifier = Rack::Hoptoad.new(app, 'pollywog') do |middleware|
      middleware.environment_filters << %w(MY_SECRET_STUFF MY_SECRET_KEY)
    end
    notifier.environment_filter_keys.should include('MY_SECRET_STUFF')
    notifier.environment_filter_keys.should include('MY_SECRET_KEY')
  end

  it 're-raises errors caught in the middleware' do
    notifier = Rack::Hoptoad.new(app, 'pollywog')
    lambda { notifier.call(env) }.should raise_error(TestError)
  end

  describe 'supports custom environments' do
    before { ENV['RACK_ENV'] = 'custom' }
    it 'works with a RACK_ENV of "custom"' do
      notifier =
        Rack::Hoptoad.new(app, api_key) do |middleware|
          middleware.report_under << 'custom'
          middleware.environment_filters << 'MY_HOPTOAD_API_KEY'
        end
      lambda { notifier.call(env) }.should raise_error(TestError)
      env['hoptoad.notified'].should eql(true)
    end
  end

  describe 'environmental variables other than RACK_ENV' do
    before { ENV['MERB_ENV'] = 'custom' }
    it 'works with MERB_ENV' do
      notifier =
        Rack::Hoptoad.new(app, api_key, 'MERB_ENV') do |middleware|
          middleware.report_under << 'custom'
          middleware.environment_filters << 'MY_HOPTOAD_API_KEY'
        end
      lambda { notifier.call(env) }.should raise_error(TestError)
      env['hoptoad.notified'].should eql(true)
    end
  end

  describe 'when hoptoad fails' do
    before { ENV['RACK_ENV'] = 'production' }
    it 'handles the failure' do
      failsafe = StringIO.new

      notifier =
        Rack::Hoptoad.new(app, api_key) do |middleware|
          middleware.environment_filters << 'MY_HOPTOAD_API_KEY'
          middleware.notifier_class = FailHopper
          middleware.failsafe       = failsafe
        end

      lambda { notifier.call(env) }.should raise_error(TestError)
      env['hoptoad.notified'].should eql(false)
      failsafe.string.should include("Fail safe error caught")
      failsafe.string.should include("No response from Toadhopper")
    end
  end

  describe "when toadhopper get overwritten the notify_host" do
    before { ENV['RACK_ENV'] = 'production' }
    it 'instanciated the notifier_class with the host' do
      failsafe = StringIO.new
      notifier_mock = double()
      notifier_mock.should_receive(:new).with(api_key, { :notify_host => "http://foo" }){ stub() }

      notifier =
        Rack::Hoptoad.new(app, api_key, 'RACK_ENV', 'http://foo') do |middleware|
          middleware.environment_filters << 'MY_HOPTOAD_API_KEY'
          middleware.notifier_class = notifier_mock
          middleware.failsafe       = failsafe
        end

      lambda { notifier.call(env) }.should raise_error(TestError)
      env['hoptoad.notified'].should eql(false)
    end
  end

  describe "when hoptoad returns an error" do
    before { ENV['RACK_ENV'] = 'production' }
    it 'outputs the errors' do
      failsafe = StringIO.new

      notifier =
        Rack::Hoptoad.new(app, api_key) do |middleware|
          middleware.environment_filters << 'MY_HOPTOAD_API_KEY'
          middleware.notifier_class = ErroringHopper
          middleware.failsafe       = failsafe
        end

      lambda { notifier.call(env) }.should raise_error(TestError)
      env['hoptoad.notified'].should eql(false)
      failsafe.string.should include("Fail safe error caught: Rack::Hoptoad::Error")
      failsafe.string.should include('Status: 500 ["Timeout"]')
    end
  end
end
