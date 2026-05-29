public enum SecretKeys {
    /// Keychain account key for the alert webhook URL. The app writes it; the
    /// daemon's alert layer reads it. One constant so they never drift.
    public static let webhookURL = "webhook-url"
}
