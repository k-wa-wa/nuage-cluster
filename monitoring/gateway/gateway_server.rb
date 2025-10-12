require 'grpc'
require 'pg'
require 'active_support/time'
require 'active_support/core_ext/time'
require 'active_support/core_ext/date'
require 'active_support/core_ext/date_and_time/calculations'
require 'dotenv/load' # Load .env file

# Generated protocol buffers
$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
require 'report_service_pb'
require 'report_service_services_pb'

class GatewayServer < Gateway::ReportService::Service
  def initialize
    @db_conn = PG.connect(
      host: ENV['DB_HOST'],
      port: ENV['DB_PORT'],
      dbname: ENV['DB_NAME'],
      user: ENV['DB_USER'],
      password: ENV['DB_PASSWORD']
    )
  rescue PG::Error => e
    puts "Failed to connect to database: #{e.message}"
    exit 1
  end

  def get_report(get_report_request, _call)
    report_id = get_report_request.report_id
    result = @db_conn.exec_params('SELECT report_id, report_name, report_type, generated_at, content, status FROM reports WHERE report_id = $1', [report_id])

    if result.any?
      row = result.first
      report = Gateway::Report.new(
        report_id: row['report_id'],
        report_name: row['report_name'],
        report_type: row['report_type'],
        generated_at: row['generated_at'].to_time.iso8601,
        content: row['content'],
        status: row['status']
      )
      Gateway::GetReportResponse.new(report: report)
    else
      raise GRPC::NotFound, "Report with ID #{report_id} not found"
    end
  end

  def list_reports(list_reports_request, _call)
    query = 'SELECT report_id, report_name, report_type, generated_at, content, status FROM reports WHERE 1=1'
    params = []
    param_index = 1

    if list_reports_request.report_type && !list_reports_request.report_type.empty?
      query += " AND report_type = $#{param_index}"
      params << list_reports_request.report_type
      param_index += 1
    end

    if list_reports_request.start_date && !list_reports_request.start_date.empty?
      begin
        start_time = Time.parse(list_reports_request.start_date).beginning_of_day
        query += " AND generated_at >= $#{param_index}"
        params << start_time
        param_index += 1
      rescue ArgumentError
        raise GRPC::InvalidArgument, "Invalid start_date format: #{list_reports_request.start_date}"
      end
    end

    if list_reports_request.end_date && !list_reports_request.end_date.empty?
      begin
        end_time = Time.parse(list_reports_request.end_date).end_of_day
        query += " AND generated_at <= $#{param_index}"
        params << end_time
        param_index += 1
      rescue ArgumentError
        raise GRPC::InvalidArgument, "Invalid end_date format: #{list_reports_request.end_date}"
      end
    end

    query += ' ORDER BY generated_at DESC'

    if list_reports_request.limit > 0
      query += " LIMIT $#{param_index}"
      params << list_reports_request.limit
      param_index += 1
    end

    if list_reports_request.offset > 0
      query += " OFFSET $#{param_index}"
      params << list_reports_request.offset
      param_index += 1
    end

    result = @db_conn.exec_params(query, params)

    reports = result.map do |row|
      Gateway::Report.new(
        report_id: row['report_id'],
        report_name: row['report_name'],
        report_type: row['report_type'],
        generated_at: row['generated_at'].to_time.iso8601,
        content: row['content'],
        status: row['status']
      )
    end
    Gateway::ListReportsResponse.new(reports: reports)
  end
end

def main
  port = ENV['GRPC_PORT']
  s = GRPC::RpcServer.new
  s.add_http2_port("0.0.0.0:"+port, :this_port_is_insecure)
  s.handle(GatewayServer.new)
  puts "GatewayServer running on #{port}"
  s.run_till_terminated_or_interrupted([1, 'int', 'SIGQUIT'])
end

main if __FILE__ == $PROGRAM_NAME
