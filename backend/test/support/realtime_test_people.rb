module RealtimeTestPeople
  def person_with_session(name, role: "jobseeker")
    user = User.create!(name:, email: "#{name.parameterize}-#{SecureRandom.hex(3)}@example.com", password: "StrongPass123!", role:,
      status: "active", profile_complete: true)
    session = user.sessions.create!(token_digest: Digest::SHA256.hexdigest(SecureRandom.hex(16)), expires_at: 1.day.from_now)
    [user, session]
  end
end
