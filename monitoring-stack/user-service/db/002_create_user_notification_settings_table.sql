CREATE TABLE user_notification_settings (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    setting_key VARCHAR(255) NOT NULL,
    setting_value TEXT,
    CONSTRAINT fk_user_id
        FOREIGN KEY (user_id)
        REFERENCES user_profiles (user_id)
        ON DELETE CASCADE
);
