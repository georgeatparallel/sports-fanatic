defmodule SportsFanatic.Repo.Migrations.SeedXAgentFeatureFlags do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO system.feature_flags (id, key, enabled, description, inserted_at, updated_at)
    VALUES
      (gen_random_uuid(), 'x_agent_enabled', false,
        'Master switch for X (Twitter) auto-posting agent.', NOW(), NOW()),
      (gen_random_uuid(), 'x_agent_approval_required', true,
        'When true, posts wait for admin approval before sending.', NOW(), NOW()),
      (gen_random_uuid(), 'x_agent_outbound_replies_enabled', false,
        'Allow OutboundReplyWorker to post replies to watched accounts.', NOW(), NOW())
    ON CONFLICT (key) DO NOTHING
    """)
  end

  def down do
    execute("""
    DELETE FROM system.feature_flags
    WHERE key IN (
      'x_agent_enabled',
      'x_agent_approval_required',
      'x_agent_outbound_replies_enabled'
    )
    """)
  end
end
