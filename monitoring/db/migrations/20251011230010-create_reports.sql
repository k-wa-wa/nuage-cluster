
-- +migrate Up
-- Table for storing generated reports
CREATE TABLE IF NOT EXISTS reports (
    seq_id SERIAL PRIMARY KEY,
    report_id UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
    report_name VARCHAR(255) NOT NULL,
    report_type VARCHAR(100) NOT NULL, -- e.g., 'daily', 'weekly', 'monthly', 'on-demand'
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    content TEXT NOT NULL,
    status VARCHAR(50) NOT NULL -- e.g., 'pending', 'completed', 'failed'
);

-- Index for performance
CREATE INDEX IF NOT EXISTS idx_reports_generated_at ON reports(generated_at);
CREATE INDEX IF NOT EXISTS idx_reports_report_type ON reports(report_type);

-- +migrate Down
DROP INDEX IF EXISTS idx_reports_report_type;
DROP INDEX IF EXISTS idx_reports_generated_at;
DROP TABLE IF EXISTS reports;
